// 皮肤大图不在随包资源里（706 MB），ShellServer 必须把这类请求 302 到
// 独立皮肤仓 CDN，且不能误伤其它路径。这里验证重定向规则与破缓存参数透传。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/shell/shell_assets.dart';
import 'package:sgs_heroes/shell/shell_server.dart';

const _base = 'https://cdn.example.com/skins/';

/// 直连本地 server（绕开系统代理），且禁止 HttpClient 自动跟随 302。
Future<(int, String?, String)> _raw(int port, String path,
    {Map<String, String>? query}) async {
  final io = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: path,
      queryParameters: query,
    );
    final req = await io.getUrl(uri)..followRedirects = false;
    final resp = await req.close();
    final loc = resp.headers.value(HttpHeaders.locationHeader);
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, loc, body);
  } finally {
    io.close();
  }
}

void main() {
  late ShellServer server;
  late int port;

  Future<void> boot({String? skinBase = _base, Directory? dataDir}) async {
    server = ShellServer(
      dataDir: dataDir,
      assets: ShellAssets.fake(<String, Uint8List>{}),
      skinBase: skinBase,
    );
    port = await server.start();
    addTearDown(server.stop);
  }

  test('皮肤路径 302 到 CDN，并透传 ?iv= 破缓存参数', () async {
    await boot();
    final (code, loc, _) = await _raw(
      port, '/images/gjf/sk/104.webp', query: <String, String>{'iv': '1'},
    );
    expect(code, HttpStatus.found);
    expect(loc, 'https://cdn.example.com/skins/images/gjf/sk/104.webp?iv=1');
  });

  test('无 query 时 Location 干净，且各版本目录都命中', () async {
    await boot();
    for (final ver in <String>['gjf', 'hlsgs', 'msgs', 'sgs', 'sgsol', 'wxmini']) {
      final (code, loc, _) = await _raw(port, '/images/$ver/sk/1.webp');
      expect(code, HttpStatus.found, reason: ver);
      expect(loc, 'https://cdn.example.com/skins/images/$ver/sk/1.webp');
    }
  });

  test('非皮肤路径不重定向：立绘 / 语音 / 数据仍 404', () async {
    await boot();
    for (final path in <String>[
      '/images/gjf/il/gjf_liubei.webp',
      '/images/sgsol/voice/1001.ogg',
      '/heroes/sgsol-001.json',
      '/style.css',
    ]) {
      final (code, loc, _) = await _raw(port, path);
      expect(code, HttpStatus.notFound, reason: path);
      expect(loc, isNull, reason: path);
    }
  });

  test('主动留空资源根时不做任何重定向', () async {
    await boot(skinBase: '');
    final (code, loc, _) = await _raw(port, '/images/gjf/sk/104.webp');
    expect(code, HttpStatus.notFound);
    expect(loc, isNull);
  });

  test('本地覆盖层已有同名皮肤文件时优先本地，不再重定向', () async {
    final dir = await Directory.systemTemp.createTemp('sgs_skin_');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}${Platform.pathSeparator}images'
        '${Platform.pathSeparator}gjf${Platform.pathSeparator}sk'
        '${Platform.pathSeparator}104.webp');
    await f.create(recursive: true);
    await f.writeAsBytes(Uint8List.fromList(utf8.encode('local-skin')));
    await boot(dataDir: dir);
    final (code, loc, body) = await _raw(port, '/images/gjf/sk/104.webp');
    expect(code, HttpStatus.ok);
    expect(loc, isNull);
    expect(body, 'local-skin');
  });
}
