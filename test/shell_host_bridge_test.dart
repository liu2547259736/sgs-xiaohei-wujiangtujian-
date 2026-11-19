// 宿主桥注入、静态资源缓存头、随包资源 LRU。
//
// 这三条都是为了「手机端不卡」与「系统栏不断层」服务的，容易在后续重构里
// 被无意改坏（比如把注入从 head 挪到 body、把 Cache-Control 改回 no-cache），
// 所以各锁一条。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/shell/shell_assets.dart';
import 'package:sgs_heroes/shell/shell_server.dart';

const String _html = '<!doctype html><html><head><title>t</title></head><body>'
    '<script src="app.js"></script></body></html>';

ShellAssets _assets([Map<String, Uint8List>? extra]) =>
    ShellAssets.fake(<String, Uint8List>{
      'index.html': Uint8List.fromList(utf8.encode(_html)),
      'app.js': Uint8List.fromList(utf8.encode('// app')),
      'images/sgsol/av/a.webp': Uint8List.fromList(List<int>.filled(64, 7)),
      'data/index.json': Uint8List.fromList(utf8.encode('{"versions":[]}')),
      ...?extra,
    });

Future<(int, String, HttpHeaders)> _get(int port, String path) async {
  final io = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final req = await io.getUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, body, resp.headers);
  } finally {
    io.close();
  }
}

Future<HttpHeaders> _headers(int port, String path) async {
  final io = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final req = await io.getUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
    final resp = await req.close();
    await resp.drain<void>();
    return resp.headers;
  } finally {
    io.close();
  }
}

void main() {
  group('宿主桥注入', () {
    test('写入 <head>，且早于 app.js —— 页面在脚本开头就取成常量了', () async {
      final server = ShellServer(assets: _assets(), apiBase: '');
      final port = await server.start();
      addTearDown(server.stop);

      final (_, html, _) = await _get(port, '/');
      expect(html, contains('sgs-shell-host'));
      expect(html, contains('window.SGSHost'));
      expect(html, contains('window.__sgsShellInsets'));
      // 用 src= 前缀，避免命中 shim 注释里的普通字样。
      expect(html.indexOf('SGSHost'), lessThan(html.indexOf('src="app.js"')));
      expect(html.indexOf('SGSHost'), lessThan(html.indexOf('</head>')));
    });

    test('系统深色时 isSystemDark 初值就是 1，避免先按浅色渲染一帧', () async {
      final server = ShellServer(assets: _assets(), apiBase: '');
      server.systemDark = true;
      final port = await server.start();
      addTearDown(server.stop);

      final (_, html, _) = await _get(port, '/');
      expect(html, contains('dark: 1'));
      expect(html, isNot(contains('dark: 0')));
    });

    test('浅色系统时初值是 0', () async {
      final server = ShellServer(assets: _assets(), apiBase: '');
      final port = await server.start();
      addTearDown(server.stop);

      final (_, html, _) = await _get(port, '/');
      expect(html, contains('dark: 0'));
    });

    test('injectHost: false 时页面完全原样', () async {
      final server =
          ShellServer(assets: _assets(), apiBase: '', injectHost: false);
      final port = await server.start();
      addTearDown(server.stop);

      final (_, html, _) = await _get(port, '/');
      expect(html, _html);
    });

    test('非入口页不注入（不能给 app.js 塞 HTML）', () async {
      final server = ShellServer(assets: _assets(), apiBase: '');
      final port = await server.start();
      addTearDown(server.stop);

      final (_, js, _) = await _get(port, '/app.js');
      expect(js, '// app');
    });
  });

  group('静态资源缓存头', () {
    test('图片给长缓存，避免每次滚动都回源解压', () async {
      final server = ShellServer(assets: _assets(), apiBase: '');
      final port = await server.start();
      addTearDown(server.stop);

      final h = await _headers(port, '/images/sgsol/av/a.webp');
      expect(h.value('cache-control'), contains('max-age=86400'));
    });

    test('入口页与 JSON 必须每次校验（覆盖层更新后要立刻生效）', () async {
      final server = ShellServer(assets: _assets(), apiBase: '');
      final port = await server.start();
      addTearDown(server.stop);

      expect((await _headers(port, '/')).value('cache-control'), 'no-cache');
      expect((await _headers(port, '/data/index.json')).value('cache-control'),
          'no-cache');
    });
  });

  group('随包资源 LRU', () {
    test('小文件进缓存，重复读取走内存', () async {
      final assets = _assets();
      expect(assets.cacheCount, 0);

      await assets.read('images/sgsol/av/a.webp');
      expect(assets.cacheCount, 1);
      expect(assets.cacheBytes, 64);

      // 第二次读到的仍是同样的内容，字节数不变（没有重复累加）
      final again = await assets.read('images/sgsol/av/a.webp');
      expect(again!.lengthInBytes, 64);
      expect(assets.cacheBytes, 64);
    });

    test('超过单张上限的大文件不进缓存（不挤掉一堆头像）', () async {
      final big = Uint8List.fromList(
          List<int>.filled(ShellAssets.cacheMaxItem + 1, 1));
      final assets = _assets(<String, Uint8List>{'images/big.webp': big});

      final got = await assets.read('images/big.webp');
      expect(got!.lengthInBytes, big.length);
      expect(assets.cacheCount, 0, reason: '大图只透传，不占缓存');
    });

    test('超过总上限时淘汰最旧的', () async {
      // 每个刚好等于单张上限，21 个 = 42 MB > 40 MB 上限。
      final extra = <String, Uint8List>{};
      for (var i = 0; i < 21; i++) {
        extra['images/sgsol/av/p$i.webp'] =
            Uint8List.fromList(List<int>.filled(ShellAssets.cacheMaxItem, 1));
      }
      final assets = _assets(extra);

      for (var i = 0; i < 21; i++) {
        await assets.read('images/sgsol/av/p$i.webp');
      }

      expect(assets.cacheBytes, lessThanOrEqualTo(ShellAssets.cacheLimit));
      expect(assets.cacheCount, lessThan(21), reason: '最早的几份必须被淘汰');
    });
  });
}
