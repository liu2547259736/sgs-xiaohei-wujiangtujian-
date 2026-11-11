// 本地 HTTP server：把随包的原页面喂给 WebView。
//
// 为什么不用 file:// —— 原页面大量使用 fetch('data/...')、CSS @font-face、
// localStorage，file:// 下会被 CORS / opaque origin 拦掉，界面能出但数据是空的。
// 走 127.0.0.1 的 http 则与用户在浏览器里打开主程序完全同构。
//
// 查找顺序：更新覆盖层（CDN 落盘） > 随包资源。两者路径同构时，
// GitUpdateService 拉下来的新文件会被原页面直接读到，不需要改 app.js。
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'shell_assets.dart';
import 'shell_config.dart';

class ShellServer {
  HttpServer? _server;
  ShellAssets? _assets;
  Directory? _dataDir;

  int? get port => _server?.port;
  String get version => _assets?.version ?? '0';

  Future<int> start() async {
    _assets = await ShellAssets.load();
    try {
      final base = await getApplicationSupportDirectory();
      _dataDir = Directory('${base.path}/$kDataDirName');
    } catch (_) {
      // 桌面端没有 path_provider 插件时降级成纯随包页面，不影响 1:1。
      _dataDir = null;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = (req.uri.path.isEmpty || req.uri.path == '/')
          ? kShellEntry
          : req.uri.path;
      final rel = _safe(path);
      if (rel == null) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }

      final dir = _dataDir;
      if (dir != null) {
        final f = File('${dir.path}/$rel');
        if (await f.exists()) {
          await _send(req, rel, await f.readAsBytes());
          return;
        }
      }

      final data = await _assets?.read(rel);
      if (data != null) {
        final bytes = data.buffer
            .asUint8List(data.offsetInBytes, data.lengthInBytes);
        await _send(req, rel, bytes);
        return;
      }

      // 原页面有两个可选的资讯同步接口（api/olnews/sync、api/x10news/sync），
      // 纯离线场景下静默 404 即可，主界面不依赖它们。
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _send(HttpRequest req, String rel, List<int> bytes) async {
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = _mime(rel);
    req.response.headers
        .add('Cache-Control', 'no-cache');
    req.response.add(bytes);
    await req.response.close();
  }

  /// 防路径穿越：只接受相对路径，拒绝 ./、../、空段。
  static String? _safe(String raw) {
    var s = raw.replaceAll('\\', '/');
    try {
      s = Uri.decodeComponent(s);
    } catch (_) {}
    if (s.startsWith('/')) s = s.substring(1);
    if (s.isEmpty) return kShellEntry;
    final parts = s.split('/');
    if (parts.any((e) => e.isEmpty || e == '.' || e == '..')) return null;
    return parts.join('/');
  }

  static ContentType _mime(String rel) {
    final ext = rel.split('.').last.toLowerCase();
    const map = <String, String>{
      'html': 'text/html; charset=utf-8',
      'htm': 'text/html; charset=utf-8',
      'css': 'text/css; charset=utf-8',
      'js': 'application/javascript; charset=utf-8',
      'mjs': 'application/javascript; charset=utf-8',
      'json': 'application/json; charset=utf-8',
      'txt': 'text/plain; charset=utf-8',
      'svg': 'image/svg+xml',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'ico': 'image/x-icon',
      'woff': 'font/woff',
      'woff2': 'font/woff2',
      'ttf': 'font/ttf',
      'otf': 'font/otf',
      'mp3': 'audio/mpeg',
      'ogg': 'audio/ogg',
      'mp4': 'video/mp4',
      'webmanifest': 'application/manifest+json',
    };
    return ContentType.parse(map[ext] ?? 'application/octet-stream');
  }
}
