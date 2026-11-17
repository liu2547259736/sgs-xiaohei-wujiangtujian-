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
  /// [preferredPort] 仅供测试注入；不传则用 Env.shellPort（生产必须固定）。
  /// [apiBase] 仅供测试注入；不传则读应用支持目录的 sgs_api_base.txt，再退回 Env.backendBase。
  ShellServer({
    Directory? dataDir,
    ShellAssets? assets,
    String? skinBase,
    int? preferredPort,
    String? apiBase,
    this.onCheckUpdate,
  }) {
    _dataDir = dataDir;
    _assets = assets;
    _skinBaseOverride = skinBase;
    _preferredPort = preferredPort ?? Env.shellPort;
    _apiBaseOverride = apiBase;
  }

  HttpServer? _server;
  ShellAssets? _assets;
  Directory? _dataDir;
  String? _skinBaseOverride;
  String? _apiBaseOverride;
  int _preferredPort = Env.shellPort;
  String _apiBase = '';

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
    final server = await _bind(_preferredPort);
    _apiBase = _resolveApiBase();
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    return server.port;
  }

  /// 账号服务器地址：显式注入 > 应用支持目录的 sgs_api_base.txt > Env.backendBase。
  ///
  /// WebView 的 origin 是 127.0.0.1，命不中页面里的「同源自动判断」，
  /// 所以 App 端必须显式把地址喂给页面，否则云端账号是关着的。
  String _resolveApiBase() {
    final injected = _apiBaseOverride;
    if (injected != null) return injected.trim();
    try {
      final parent = _dataDir?.parent;
      if (parent != null) {
        final f = File('${parent.path}${Platform.pathSeparator}$kApiBaseFile');
        if (f.existsSync()) {
          final s = f.readAsStringSync().trim();
          if (s.isNotEmpty) return s;
        }
      }
    } catch (_) {
      // 读不到就用编译期常量，不影响启动
    }
    return Env.backendBase.trim();
  }

  /// 绑定端口：首选端口 → 顺延 8 个 → 随机兜底。
  ///
  /// 为什么必须固定：原页面的账号 / 收藏 / 历史都落在 localStorage，而
  /// localStorage 以 origin（含端口）为键。之前用 `bind(..., 0)` 每次启动
  /// 换端口，等于每次都是新站点 —— 注册完重启就找不到账号。顺延只在端口
  /// 被占用时发生（例如同时开了两个实例），此时如实换端口，不假装成功。
  Future<HttpServer> _bind(int preferred) async {
    Object? last;
    // 首选端口试两次：上一个进程刚退出时端口可能还没完全释放。
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, preferred);
      } on SocketException catch (e) {
        last = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }
    for (var i = 1; i <= 8; i++) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, preferred + i);
      } on SocketException catch (e) {
        last = e;
      }
    }
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException catch (e) {
      last = e;
    }
    throw StateError('本地端口绑定失败：$last');
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
    // 入口页做两处内存注入（磁盘上的 index.html 一个字节都不动）：
    //   1. <head> 里塞账号服务器地址 —— 必须早于 app.js，否则 initAuth() 已经跑完，
    //      CloudAuth 会以为没配服务器而整段关掉；
    //   2. </body> 前塞「检测更新」桥。
    var body = bytes;
    if (rel == kShellEntry) {
      body = _injectApiBase(body, _apiBase);
      if (onCheckUpdate != null) body = _injectProbe(body);
    }
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = _mime(rel);
    req.response.headers
        .add('Cache-Control', 'no-cache');
    req.response.add(body);
    await req.response.close();
  }

  static const String _apiBaseMarker = '/*sgs-shell-api-base*/';

  /// 在 `<head>` 后插入 `window.SGS_API_BASE`。
  /// 原页面里那句 `window.SGS_API_BASE = window.SGS_API_BASE || ''` 会保留我们塞进去的值。
  static Uint8List _injectApiBase(List<int> bytes, String base) {
    if (base.isEmpty) return Uint8List.fromList(bytes);
    final html = utf8.decode(bytes, allowMalformed: true);
    if (html.contains(_apiBaseMarker)) return Uint8List.fromList(bytes);
    final tag =
        '<script>$_apiBaseMarker\nwindow.SGS_API_BASE=${jsonEncode(base)};</script>';
    final at = html.indexOf('<head>');
    final out = at < 0 ? '$tag$html' : html.replaceRange(at + 6, at + 6, tag);
    return Uint8List.fromList(utf8.encode(out));
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
