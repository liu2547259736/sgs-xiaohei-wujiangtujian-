// 端到端验证「本体更新 → data-repo → App 覆盖层 → 原页面」链路：
// 只下原页面文件、覆盖层落盘、本地 server 覆盖层优先、元数据不泄露。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgs_heroes/core/sync/git_update_service.dart';
import 'package:sgs_heroes/core/sync/in_memory_update_sink.dart';
import 'package:sgs_heroes/core/sync/update_protocol.dart';
import 'package:sgs_heroes/core/sync/update_sink_io.dart';
import 'package:sgs_heroes/shell/shell_assets.dart';
import 'package:sgs_heroes/shell/shell_server.dart';
import 'package:sgs_heroes/shell/shell_updater.dart';

const _base = 'https://cdn.example.com/sgs-data@data-v2026.11.12';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

Map<String, dynamic> _manifest(
        String version, Map<String, Uint8List> files) =>
    <String, dynamic>{
      'schema': 1,
      'version': version,
      'updated_at': '2026-11-12T00:00:00+08:00',
      'counts': {'files': files.length},
      'files': <Map<String, dynamic>>[
        for (final e in files.entries)
          <String, dynamic>{
            'path': e.key,
            'sha256': sha256.convert(e.value).toString(),
            'bytes': e.value.length,
          }
      ],
    };

/// 直连本地 server，绕开环境里可能设置的系统代理。
Future<(int, String)> _fetch(int port, String path) async {
  final io = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final req = await io.get('127.0.0.1', port, path);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, body);
  } finally {
    io.close();
  }
}

void main() {
  test('白名单只放行原页面路径，跳过 Flutter 数据分片', () {
    for (final p in <String>[
      'index.html',
      'style.css',
      'app.js',
      'data/index.json',
      'data/sgsol/characters.json',
      'images/sgsol/av/x.webp',
      'fonts/sgs-juan.woff2',
      'services/localAuth.js',
    ]) {
      expect(ShellUpdater.isShellPath(p), isTrue, reason: p);
    }
    for (final p in <String>[
      'heroes/sgsol-001.json',
      'skins/sgsol-001.json',
      'meta/cards.json',
      'history/books/1.json',
      'tools/migrate.py',
    ]) {
      expect(ShellUpdater.isShellPath(p), isFalse, reason: p);
    }
  });

  test('版本比较：2026.11.10-2 < 2026.11.11', () {
    expect(GitUpdateService.compareVersion('2026.11.11', '2026.11.10-2'),
        greaterThan(0));
    expect(GitUpdateService.compareVersion('2026.11.11', '2026.11.11'), 0);
    expect(GitUpdateService.compareVersion('2026.11.9', '2026.11.11'),
        lessThan(0));
  });

  test('远端版本更旧时不回退，也不下载任何文件', () async {
    var fileRequests = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/manifest.json')) {
        return http.Response.bytes(
            utf8.encode(jsonEncode(_manifest('2026.11.10', {
              'index.html': _b('old'),
            }))),
            200);
      }
      fileRequests++;
      return http.Response('should not be called', 500);
    });
    final service = GitUpdateService(
      baseUrls: const [_base],
      manifestUrls: const [_base],
      sink: InMemoryUpdateSink(),
      accept: ShellUpdater.isShellPath,
      allowDowngrade: false,
      client: client,
    );
    final result = await service.checkAndApply(
      seed: DataManifest.fromJson(_manifest('2026.11.12', {
        'index.html': _b('new'),
      })),
    );
    expect(result.status, UpdateStatus.upToDate);
    expect(result.version, '2026.11.12');
    expect(fileRequests, 0);
    service.dispose();
  });

  test('新版本只下变化的原页面文件；落盘后 server 返回新内容', () async {
    final tmp = await Directory.systemTemp.createTemp('sgs_shell_update_');
    addTearDown(() => tmp.delete(recursive: true));
    final overlay = Directory('${tmp.path}${Platform.pathSeparator}sgs_data');

    final oldIndex = _b('<html>old</html>');
    final newIndex = _b('<html>new 1:1</html>');
    final css = _b('body{color:red}');
    final hero = _b('{"data":{}}');

    final requests = <String>[];
    final client = MockClient((req) async {
      requests.add(req.url.path);
      if (req.url.path.endsWith('/manifest.json')) {
        return http.Response.bytes(
            utf8.encode(jsonEncode(_manifest('2026.11.12', {
              'index.html': newIndex,
              'style.css': css,
              'heroes/sgsol-001.json': hero, // 变了，但不属于原页面
            }))),
            200);
      }
      if (req.url.path.endsWith('/index.html')) {
        return http.Response.bytes(newIndex, 200);
      }
      if (req.url.path.endsWith('/heroes/sgsol-001.json')) {
        return http.Response.bytes(hero, 200);
      }
      return http.Response('missing', 404);
    });

    final sink = FileUpdateSink(rootProvider: () async => tmp);
    final service = GitUpdateService(
      baseUrls: const [_base],
      manifestUrls: const [_base],
      urlBuilder: (_) => const [_base],
      sink: sink,
      accept: ShellUpdater.isShellPath,
      allowDowngrade: false,
      client: client,
    );
    final result = await service.checkAndApply(
      seed: DataManifest.fromJson(_manifest('2026.11.11', {
        'index.html': oldIndex,
        'style.css': css,
      })),
    );

    expect(result.status, UpdateStatus.updated);
    expect(result.version, '2026.11.12');
    expect(result.changedPaths, ['index.html'],
        reason: 'style.css 没变、数据分片被白名单排除');
    expect(requests.any((p) => p.contains('heroes/')), isFalse,
        reason: '不该为数据分片发请求');
    expect(await File('${overlay.path}${Platform.pathSeparator}index.html')
        .readAsString(), '<html>new 1:1</html>');

    // 随包是旧页面，覆盖层是新页面：server 必须优先返回新内容。
    final server = ShellServer(
      dataDir: overlay,
      assets: ShellAssets.fake(<String, Uint8List>{
        'index.html': oldIndex,
        'style.css': css,
      }),
    );
    final port = await server.start();
    addTearDown(server.stop);

    expect(await _fetch(port, '/index.html'), (200, '<html>new 1:1</html>'));
    expect(await _fetch(port, '/'), (200, '<html>new 1:1</html>'),
        reason: '根路径也要走 index.html');
    expect(await _fetch(port, '/style.css'), (200, 'body{color:red}'),
        reason: '没被更新的文件继续用随包资源');
    expect((await _fetch(port, '/_meta.json')).$1, 400,
        reason: '覆盖层元数据不能当页面资源读出去');
    expect((await _fetch(port, '/%2e%2e/_meta.json')).$1, 400,
        reason: '路径穿越必须拒绝');
    expect((await _fetch(port, '/heroes/sgsol-001.json')).$1, 404);
    service.dispose();
  });

  test('所有源首轮 403、第二轮恢复时仍能完成更新', () async {
    final content = _b('retry-ok');
    var calls = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/manifest.json')) {
        return http.Response.bytes(
            utf8.encode(jsonEncode(_manifest('2026.11.12', {
              'index.html': content,
            }))),
            200);
      }
      calls++;
      // 第一轮两个源都失败，第二轮首个源恢复。
      if (calls <= 2) return http.Response('edge not ready', 403);
      return http.Response.bytes(content, 200);
    });
    final service = GitUpdateService(
      baseUrls: const [_base, 'https://cdn2.example.com/repo@data-v2'],
      manifestUrls: const [_base],
      sink: InMemoryUpdateSink(),
      fetchRounds: 2,
      client: client,
    );
    final result = await service.checkAndApply(
      seed: DataManifest.fromJson(_manifest('2026.11.11', {
        'index.html': _b('old'),
      })),
    );
    expect(result.status, UpdateStatus.updated);
    expect(result.version, '2026.11.12');
    expect(calls, 3);
    service.dispose();
  });
}
