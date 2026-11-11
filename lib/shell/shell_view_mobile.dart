// Android / iOS / macOS：内嵌 WebView 承载 1:1 原页面。
//
// 屏幕上每个像素仍由 index.html / style.css / app.js 决定；
// 这里只做系统栏避让，safe-area 由原页面 CSS 自己处理。
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'shell_reloader.dart';

class MobileWebView extends StatefulWidget {
  const MobileWebView({
    super.key,
    required this.url,
    required this.reloader,
  });

  final String url;
  final ShellReloader reloader;

  @override
  State<MobileWebView> createState() => _MobileWebViewState();
}

class _MobileWebViewState extends State<MobileWebView> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF7F3EC));
    widget.reloader.attach(_reload);
    _boot();
  }

  Future<void> _reload() async => _controller.reload();

  Future<void> _boot() async {
    await _controller.loadRequest(Uri.parse(widget.url));
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    widget.reloader.detach(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
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
    return SafeArea(
      top: true,
      bottom: false,
      child: WebViewWidget(controller: _controller),
    );
  }
}
