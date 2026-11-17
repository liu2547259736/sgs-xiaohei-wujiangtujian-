// 账号服务器地址注入：必须在 <head> 里、早于 app.js。
//
// 页面里 `initAuth()` 在 app.js 执行时就跑完了；如果地址晚于它注入，
// CloudAuth 会以为没配服务器，整段云端账号直接关掉 —— 这个顺序不能错。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/shell/shell_assets.dart';
import 'package:sgs_heroes/shell/shell_server.dart';

const String _html = '<!doctype html><html><head><title>t</title></head><body>'
    '<script src="services/localAuth.js"></script>'
    '<script src="app.js"></script></body></html>';

ShellAssets _assets() => ShellAssets.fake(<String, Uint8List>{
      'index.html': Uint8List.fromList(utf8.encode(_html)),
    });

Future<String> _getHtml(int port) async {
  final io = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final req = await io.getUrl(Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return body;
  } finally {
    io.close();
  }
}

void main() {
  test('注入地址进 <head>，且早于 app.js', () async {
    final server = ShellServer(
      assets: _assets(),
      preferredPort: 0,
      apiBase: 'http://192.168.1.20:8080',
    );
    final port = await server.start();
    addTearDown(server.stop);

    final html = await _getHtml(port);
    expect(html, contains('sgs-shell-api-base'));
    expect(html, contains('window.SGS_API_BASE="http://192.168.1.20:8080"'));
    expect(html.indexOf('SGS_API_BASE'), lessThan(html.indexOf('app.js')));
    // 必须落在 head 内，不能跑到 body 末尾
    expect(html.indexOf('SGS_API_BASE'), lessThan(html.indexOf('</head>')));
  });

  test('没配服务器就不注入，页面保持原样', () async {
    final server = ShellServer(assets: _assets(), preferredPort: 0, apiBase: '');
    final port = await server.start();
    addTearDown(server.stop);

    final html = await _getHtml(port);
    expect(html, isNot(contains('sgs-shell-api-base')));
    expect(html, contains('<script src="app.js"></script>'));
  });

  test('应用支持目录的 sgs_api_base.txt 覆盖编译期常量', () async {
    final tmp = await Directory.systemTemp.createTemp('sgs-apibase-');
    addTearDown(() => tmp.delete(recursive: true));
    await File('${tmp.path}${Platform.pathSeparator}sgs_api_base.txt')
        .writeAsString('http://10.0.0.5:9000\n');

    final server = ShellServer(
      assets: _assets(),
      preferredPort: 0,
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}sgs_data'),
      apiBase: null, // 走真实解析：文件优先
    );
    // apiBase 传 null 时会退回 Env.backendBase（空），文件优先于它
    final port = await server.start();
    addTearDown(server.stop);

    final html = await _getHtml(port);
    expect(html, contains('window.SGS_API_BASE="http://10.0.0.5:9000"'));
  });
}
