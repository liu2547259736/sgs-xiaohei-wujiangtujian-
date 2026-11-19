// 「检测更新」桥：原页面的按钮经本地控制面真的去查/拉远端。
// 这里验证路由、dry/apply 两条分支，以及入口页注入不破坏原 HTML。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/shell/shell_assets.dart';
import 'package:sgs_heroes/shell/shell_server.dart';

const String _html = '<!doctype html><html><body>'
    '<button id="checkBtn">检测更新</button>'
    '<p id="checkNote"></p></body></html>';

ShellAssets _assets() => ShellAssets.fake(<String, Uint8List>{
      'index.html': Uint8List.fromList(utf8.encode(_html)),
    });

Future<(int, String)> _get(int port, String path, {String? query}) async {
  final io = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final req = await io.getUrl(Uri(
        scheme: 'http', host: '127.0.0.1', port: port, path: path, query: query));
    final resp = await req.close();
    return (resp.statusCode, await resp.transform(utf8.decoder).join());
  } finally {
    io.close();
  }
}

void main() {
  test('dry=1 只检查，控制面返回 JSON', () async {
    final calls = <bool>[];
    final server = ShellServer(
      assets: _assets(),
      onCheckUpdate: ({required bool dry}) async {
        calls.add(dry);
        return <String, Object?>{'status': 'up_to_date', 'version': '2026.11.16'};
      },
    );
    final port = await server.start();
    addTearDown(server.stop);

    final (code, body) = await _get(port, '/_shell/check-update', query: 'dry=1');
    expect(code, HttpStatus.ok);
    expect(jsonDecode(body), containsPair('version', '2026.11.16'));
    expect(calls, <bool>[true]);
  });

  test('dry=0 走真实下载分支', () async {
    final calls = <bool>[];
    final server = ShellServer(
      assets: _assets(),
      onCheckUpdate: ({required bool dry}) async {
        calls.add(dry);
        return <String, Object?>{'status': 'updated', 'version': '2026.11.17'};
      },
    );
    final port = await server.start();
    addTearDown(server.stop);

    final (_, body) = await _get(port, '/_shell/check-update', query: 'dry=0');
    expect(jsonDecode(body), containsPair('status', 'updated'));
    expect(calls, <bool>[false]);
  });

  test('入口页注入桥脚本，原 HTML 与 </body> 都保留', () async {
    final server = ShellServer(
      assets: _assets(),
      onCheckUpdate: ({required bool dry}) async =>
          <String, Object?>{'status': 'up_to_date', 'version': '1'},
    );
    final port = await server.start();
    addTearDown(server.stop);

    final (code, body) = await _get(port, '/');
    expect(code, HttpStatus.ok);
    expect(body, contains('sgs-shell-update-probe'));
    expect(body, contains('id="checkBtn"'));
    expect(body, contains('</body>'));
    // 注入脚本必须在 </body> 之前，否则浏览器可能不执行。
    expect(body.indexOf('sgs-shell-update-probe'), lessThan(body.indexOf('</body>')));
  });

  test('非入口页不注入', () async {
    final server = ShellServer(
      assets: ShellAssets.fake(<String, Uint8List>{
        'style.css': Uint8List.fromList(utf8.encode('body{}')),
      }),
      onCheckUpdate: ({required bool dry}) async =>
          <String, Object?>{'status': 'up_to_date', 'version': '1'},
    );
    final port = await server.start();
    addTearDown(server.stop);

    final (_, body) = await _get(port, '/style.css');
    expect(body, 'body{}');
  });

  test('没有注入桥时：页面原样，控制面明确回 unsupported', () async {
    // apiBase: '' + injectHost: false —— 这条用例断言的是「没桥就没任何注入」，
    // 账号地址与宿主桥注入都属于壳的另一层行为，由各自的用例单独锁。
    final server =
        ShellServer(assets: _assets(), apiBase: '', injectHost: false);
    final port = await server.start();
    addTearDown(server.stop);

    final (_, page) = await _get(port, '/');
    expect(page, isNot(contains('sgs-shell-update-probe')));
    expect(page, _html);

    final (code, body) = await _get(port, '/_shell/check-update');
    expect(code, HttpStatus.ok);
    expect(jsonDecode(body), containsPair('status', 'unsupported'));
  });
}
