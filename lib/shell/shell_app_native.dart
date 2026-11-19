// 原生端壳：起本地 server → 后台检查数据更新 → 用平台各自的 WebView 加载
// 随包的 1:1 原页面。
//
// 这里没有任何重绘的图鉴 UI：屏幕上的每个像素都由 index.html / style.css /
// app.js 决定。加载中、出错时那几页只是壳自己的状态提示，不是图鉴界面。
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/env.dart';
import '../core/sync/update_protocol.dart';
import 'shell_reloader.dart';
import 'shell_server.dart';
import 'shell_updater.dart';
import 'shell_view_desktop.dart';
import 'shell_view_mobile.dart';

class ShellApp extends StatefulWidget {
  const ShellApp({super.key});

  @override
  State<ShellApp> createState() => _ShellAppState();
}

class _ShellAppState extends State<ShellApp> with WidgetsBindingObserver {
  late final ShellServer _server =
      ShellServer(onCheckUpdate: _onCheckUpdate);
  final ShellReloader _reloader = ShellReloader();
  ShellUpdater? _updater;
  String? _url;
  String? _error;
  bool _updating = false;
  DateTime? _lastCheck;

  /// 回到前台也检查，但半小时内不重复打 CDN。
  static const Duration _minInterval = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 注入宿主桥时要带上真实的系统深浅色，否则深色系统下页面会先按浅色渲染一帧。
    _server.systemDark = _systemDark;
    _boot();
  }

  bool get _systemDark =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;

  /// 系统深浅色变化：记住给下次注入用，并让外层底色（WebView 之外的加载/报错页）
  /// 立刻跟着变。当前页面里的取色由 MobileWebView 通知，不重复处理。
  @override
  void didChangePlatformBrightness() {
    _server.systemDark = _systemDark;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_server.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkUpdate());
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      final port = await _server.start();
      if (!mounted) return;
      setState(() => _url = 'http://127.0.0.1:$port/');
      // 不阻塞首屏：页面先出来，更新在后台跑，成功后自动 reload。
      unawaited(_checkUpdate());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// 注入脚本的更新桥：dry=1 只查，dry=0 真下载。
  /// 更新成功后由页面脚本自己 reload，这里不重复触发。
  Future<Map<String, Object?>> _onCheckUpdate({required bool dry}) async {
    final updater = _updater ??= ShellUpdater();
    final r = dry ? await updater.checkOnly() : await updater.checkAndApply();
    switch (r.status) {
      case UpdateStatus.updated:
        return <String, Object?>{'status': 'updated', 'version': r.version};
      case UpdateStatus.upToDate:
        return <String, Object?>{'status': 'up_to_date', 'version': r.version};
      case UpdateStatus.updateAvailable:
        return <String, Object?>{
          'status': 'update_available',
          'version': r.version,
          'files': r.pendingCount,
          'mb': (r.pendingBytes / 1048576).toStringAsFixed(1),
        };
      case UpdateStatus.offline:
      case UpdateStatus.invalidManifest:
        return <String, Object?>{
          'status': 'offline',
          'version': r.version,
          'message': r.message ?? '取不到版本清单',
        };
      case UpdateStatus.downloadFailed:
      case UpdateStatus.writeFailed:
        return <String, Object?>{
          'status': 'failed',
          'version': r.version,
          'message': r.message ?? '下载或写入失败',
        };
    }
  }

  Future<void> _checkUpdate() async {
    if (_updating || !Env.hasRemote) return;
    final now = DateTime.now();
    final last = _lastCheck;
    if (last != null && now.difference(last) < _minInterval) return;
    _updating = true;
    _lastCheck = now;
    try {
      final result = await (_updater ??= ShellUpdater()).checkAndApply();
      if (result.status == UpdateStatus.updated) {
        // 覆盖层已落盘，reload 后原页面 fetch 到的就是新数据。
        await _reloader();
      }
    } catch (_) {
      // 断网 / CDN 挂 / 未配置远端：静默用随包页面，不打断 1:1 体验。
    } finally {
      _updating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 全屏后状态栏/导航栏是透明的，透上来的是这里 —— 跟着系统深浅色走，
    // 避免深色系统下启动瞬间闪一块米白。页面自己的配色仍由 app.js 决定。
    final dark = _systemDark;
    return MaterialApp(
      title: '三国杀武将图鉴',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor:
            dark ? const Color(0xFF191612) : const Color(0xFFF7F3EC),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text('本地页面服务启动失败：$error', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: _boot, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final url = _url;
    if (url == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在载入图鉴…'),
          ],
        ),
      );
    }
    final desktop = Platform.isWindows || Platform.isLinux;
    return desktop
        ? DesktopWebView(url: url, reloader: _reloader)
        : MobileWebView(url: url, reloader: _reloader);
  }
}
