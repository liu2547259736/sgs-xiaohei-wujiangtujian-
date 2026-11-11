// 原生端 WebView 壳：起本地 server → 加载随包的原页面。
//
// 这里没有任何重绘的 UI，屏幕上的每个像素都由 index.html / style.css /
// app.js 决定，和主程序在浏览器里打开完全一致。
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'shell_server.dart';

class ShellApp extends StatefulWidget {
  const ShellApp({super.key});

  @override
  State<ShellApp> createState() => _ShellAppState();
}

class _ShellAppState extends State<ShellApp> {
  final ShellServer _server = ShellServer();
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _error = null;
      _controller = null;
    });
    try {
      final port = await _server.start();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFF7F3EC));
      await controller.loadRequest(Uri.parse('http://127.0.0.1:$port/'));
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
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
    final controller = _controller;
    if (controller == null) {
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
    // 安全区由原页面 CSS 的 env(safe-area-inset-*) 自己处理；
    // 这里只做系统栏避让，不改动页面布局。
    return SafeArea(
      top: true,
      bottom: false,
      child: WebViewWidget(controller: controller),
    );
  }
}
