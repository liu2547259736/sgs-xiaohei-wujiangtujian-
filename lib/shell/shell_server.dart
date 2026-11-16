// 本地 HTTP server：把随包的原页面喂给 WebView。
//
// 为什么不用 file:// —— 原页面大量使用 fetch('data/...')、CSS @font-face、
// localStorage，file:// 下会被 CORS / opaque origin 拦掉，界面能出但数据是空的。
// 走 127.0.0.1 的 http 则与用户在浏览器里打开主程序完全同构。
//
// 查找顺序：更新覆盖层（CDN 落盘） > 随包资源。两者路径同构时，
// GitUpdateService 拉下来的新文件会被原页面直接读到，不需要改 app.js。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/env.dart';
import 'shell_assets.dart';
import 'shell_config.dart';

class ShellServer {
  /// 测试可注入覆盖层目录；不传则用 ApplicationSupportDirectory/sgs_data。
  // 显式赋值而非 initializing formal：字段名是私有实现细节，不做公开参数名。
  // 测试可注入覆盖层目录与随包资源；不传则走真实平台目录与 asset bundle。
  /// [skinBase] 仅供测试注入；不传则用 Env.skinCdnBase。
  ShellServer({
    Directory? dataDir,
    ShellAssets? assets,
    String? skinBase,
    this.onCheckUpdate,
  }) {
    _dataDir = dataDir;
    _assets = assets;
    _skinBaseOverride = skinBase;
  }

  HttpServer? _server;
  ShellAssets? _assets;
  Directory? _dataDir;
  String? _skinBaseOverride;

  /// 「检测更新」按钮的桥。由壳注入：dry=1 只查不下载，dry=0 真下载。
  /// 返回体直接 jsonEncode 给页面脚本。不传时（测试 / 纯静态）不拦截路由，
  /// 页面保持原样行为。
  final Future<Map<String, Object?>> Function({required bool dry})? onCheckUpdate;

  String get _skinCdnBase => _skinBaseOverride ?? Env.skinCdnBase;

  int? get port => _server?.port;
  String get version => _assets?.version ?? '0';

  Future<int> start() async {
    _assets ??= await ShellAssets.load();
    if (_dataDir == null) {
      try {
        final base = await getApplicationSupportDirectory();
        _dataDir = Directory('${base.path}/$kDataDirName');
      } catch (_) {
        // 桌面端没有 path_provider 插件时降级成纯随包页面，不影响 1:1。
        _dataDir = null;
      }
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
      // 壳自己的控制面，不是页面资源，必须在 _safe 之前拦。
      if (path == _checkPath) {
        await _handleCheck(req);
        return;
      }
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

      // 皮肤大图不随包（706 MB），走独立皮肤仓 CDN。302 让 WebView 直接
      // 向 CDN 取图并自行缓存，不把图片下载到设备覆盖层。
      final skinUrl = _skinRedirect(rel, req.uri.query);
      if (skinUrl != null) {
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set(HttpHeaders.locationHeader, skinUrl);
        await req.response.close();
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

  /// 只重定向皮肤大图；其它路径（含语音、数据）仍按原有规则处理。
  static final RegExp _skinPath = RegExp(r'^images/[^/]+/sk/[^/]+\.webp$');

  /// 透传 `?iv=N` 破缓存参数，避免 CDN / WebView 命中旧图。
  String? _skinRedirect(String rel, String query) {
    final base = _skinCdnBase;
    if (base.isEmpty || !_skinPath.hasMatch(rel)) return null;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final url = '$b/$rel';
    return query.isEmpty ? url : '$url?$query';
  }

  static const String _checkPath = '/_shell/check-update';

  /// 控制面：给注入脚本查更新状态。dry=1 只比对 manifest（1~2 秒），
  /// dry=0 才真下载。字段与 [_probeJs] 里约定的一致。
  Future<void> _handleCheck(HttpRequest req) async {
    final cb = onCheckUpdate;
    Map<String, Object?> body;
    if (cb == null) {
      body = <String, Object?>{
        'status': 'unsupported',
        'message': '当前版本不支持在线更新',
      };
    } else {
      try {
        body = await cb(dry: req.uri.queryParameters['dry'] != '0');
      } catch (e) {
        body = <String, Object?>{'status': 'failed', 'message': '$e'};
      }
    }
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.add('Cache-Control', 'no-store');
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  static const String _probeMarker = '/*sgs-shell-update-probe*/';

  /// 只在内存响应里注入，磁盘上的 index.html 一个字节都不动。
  static Uint8List _injectProbe(List<int> bytes) {
    final html = utf8.decode(bytes, allowMalformed: true);
    if (html.contains(_probeMarker)) return Uint8List.fromList(bytes);
    final script = '<script>$_probeMarker\n$_probeJs\n</script>';
    final at = html.lastIndexOf('</body>');
    final out = at < 0 ? '$html$script' : html.replaceRange(at, at, script);
    return Uint8List.fromList(utf8.encode(out));
  }

  /// 把原页面的「检测更新」从「重数一遍本地武将」改成「真的查/拉远端」。
  /// 用 capture 阶段拦掉原 listener，避免它把 note 覆盖成「检测完成」。
  static const String _probeJs = r'''
(function(){
  var btn=document.getElementById('checkBtn');
  var note=document.getElementById('checkNote');
  if(!btn) return;
  function setNote(t){ if(note) note.textContent=t; }
  function done(){ btn.disabled=false; btn.classList.remove('loading'); }
  btn.addEventListener('click', function(ev){
    ev.preventDefault();
    ev.stopImmediatePropagation();
    if(btn.disabled) return;
    btn.disabled=true;
    btn.classList.add('loading');
    setNote('正在检查数据更新…');
    fetch('/_shell/check-update?dry=1',{cache:'no-store'})
      .then(function(r){ return r.json(); })
      .then(function(d){
        if(d.status==='up_to_date'){
          setNote('已是最新版本 '+(d.version||'')); done(); return null;
        }
        if(d.status!=='update_available'){
          setNote('检查失败：'+(d.message||'网络不可用')); done(); return null;
        }
        setNote('发现新版本 '+(d.version||'')+'（'+(d.files||0)+' 个文件 / '+(d.mb||0)+' MB），正在更新…');
        return fetch('/_shell/check-update?dry=0',{cache:'no-store'})
          .then(function(r){ return r.json(); })
          .then(function(e){
            if(e.status==='updated'){
              setNote('已更新到 '+(e.version||'')+'，正在刷新…');
              setTimeout(function(){ location.reload(); },800);
              return;
            }
            setNote('更新失败：'+(e.message||'未知错误')); done();
          });
      })
      .catch(function(){ setNote('检查失败：无法连接本地更新服务'); done(); });
  }, true);
})();
''';

  Future<void> _send(HttpRequest req, String rel, List<int> bytes) async {
    // 入口页注入更新桥；其它资源原样直出。
    final body = (rel == kShellEntry && onCheckUpdate != null)
        ? _injectProbe(bytes)
        : bytes;
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = _mime(rel);
    req.response.headers
        .add('Cache-Control', 'no-cache');
    req.response.add(body);
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
    // 覆盖层的元数据（_meta.json、.staging/）不该被当成页面资源读出去。
    if (s == '_meta.json' || s == '_meta.json.tmp') return null;
    if (parts.any((e) =>
        e.isEmpty || e == '.' || e == '..' || e.startsWith('.'))) {
      return null;
    }
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
