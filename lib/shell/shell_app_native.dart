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
  final ShellServer _server = ShellServer();
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
    _boot();
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
    return MaterialApp(
      title: '三国杀武将图鉴',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F3EC),
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
