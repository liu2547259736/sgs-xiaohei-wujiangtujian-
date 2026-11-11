// 验证「浮动分支发现版本 → 锁定新 tag 下载文件」这条两级链路。
// 修复前 URL 固定写死在本地版本 tag 上，检查更新永远发现不了新版本。
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgs_heroes/core/env.dart';
import 'package:sgs_heroes/core/sync/git_update_service.dart';
import 'package:sgs_heroes/core/sync/in_memory_update_sink.dart';
import 'package:sgs_heroes/core/sync/update_protocol.dart';

const _path = 'heroes/sgsol-001.json';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('manifest 走 master，文件下载走远端版本对应的新 tag', () async {
    final content = _bytes('new shard');
    final seen = <String>[];
    final client = MockClient((req) async {
      final url = req.url.toString();
      seen.add(url);
      if (url.endsWith('manifest.json')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'schema': 1,
            'version': '2026.12.01',
            'updated_at': '2026-12-01T00:00:00+08:00',
            'counts': <String, int>{'heroes': 1},
            'files': <Map<String, dynamic>>[
              <String, dynamic>{
                'path': _path,
                'sha256': sha256.convert(content).toString(),
                'bytes': content.length,
              }
            ],
          })),
          200,
        );
      }
      if (url.endsWith(_path)) return http.Response.bytes(content, 200);
      return http.Response('missing', 404);
    });

    final service = GitUpdateService(
      baseUrls: const <String>['https://cdn.example.com/repo@data-v1'],
      manifestUrls: const <String>['https://cdn.example.com/repo@master'],
      urlBuilder: (v) => <String>['https://cdn.example.com/repo@data-v$v'],
      sink: InMemoryUpdateSink(),
      client: client,
    );

    final result = await service.checkAndApply();
    service.dispose();

    expect(result.status, UpdateStatus.updated);
    expect(result.version, '2026.12.01');
    expect(
      seen.any((u) => u.contains('@master/manifest.json')),
      isTrue,
      reason: '版本必须从浮动分支发现',
    );
    expect(
      seen.any((u) => u.contains('@data-v2026.12.01/$_path')),
      isTrue,
      reason: '文件必须锁到远端新版本的 immutable tag',
    );
    expect(
      seen.any((u) => u.contains('@data-v1/')),
      isFalse,
      reason: '不该再从旧版本 tag 下载文件',
    );
  });

  test('Env 的发现源与版本源指向不同 ref', () {
    expect(Env.hasRemote, isTrue);
    final discovery = Env.manifestUrls();
    final pinned = Env.dataBaseUrls('2026.11.11');
    expect(discovery.first.contains('@${Env.defaultBranch}'), isTrue);
    expect(pinned.first.contains('@${Env.tagPrefix}2026.11.11'), isTrue);
    expect(discovery.first, isNot(pinned.first));
  });
}
