// Android / iOS / macOS：内嵌 WebView 承载 1:1 原页面。
//
// 屏幕上每个像素仍由 index.html / style.css / app.js 决定；这里只做两件事：
//   1. 让 WebView 真正铺满整屏（edge-to-edge），安全区交给页面自己的
//      --sb-top / --sb-bottom（原页面为 viewport-fit=cover 写好了，见 style.css）；
//   2. 把系统栏底色与图标明暗跟着页面主题走 —— 页面通过 SGSHost.setTheme()
//      回报当前实际主题，这里据此染状态栏 / 导航栏。
//
// 为什么不再包一层 SafeArea：页面已经用 env(safe-area-inset-*) 避让过一次，
// Flutter 再避让一次就是双份留白；更糟的是状态栏那一条露出来的是 Scaffold 的
// 米白底色，切到夜间主题时页面已经变深、那条还是米白 —— 就是用户看到的
// 「状态栏颜色和页面不一致」。全屏 + 透明系统栏 + 页面自己避让，三者才自洽。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _MobileWebViewState extends State<MobileWebView>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _ready = false;

  /// 页面回报的实际主题：'paper' / 'ink'；空 = 还没回报。
  String _theme = '';

  /// 上次上报给页面的安全区（CSS px），用来去重。
  double _insetTop = -1;
  double _insetBottom = -1;

  bool get _isDark => _theme == 'ink';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final systemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
          systemDark ? const Color(0xFF191612) : const Color(0xFFF7F3EC))
      ..addJavaScriptChannel('SgsHostTheme', onMessageReceived: _onHostTheme)
      ..setNavigationDelegate(NavigationDelegate(
        // 页面首帧就绪：撤掉加载遮罩，并把安全区喂进去。
        onPageFinished: (_) {
          _pushInsets();
          if (mounted && !_ready) setState(() => _ready = true);
        },
      ));
    widget.reloader.attach(_reload);
    _boot();
  }

  Future<void> _reload() async {
    _insetTop = -1;
    _insetBottom = -1;
    await _controller.reload();
  }

  Future<void> _boot() async {
    await _controller.loadRequest(Uri.parse(widget.url));
    // 兜底：本地 server 异常时 onPageFinished 不一定会来，别让遮罩永远盖着。
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted && !_ready) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.reloader.detach(_reload);
    super.dispose();
  }

  /// 系统深浅色变化：通知页面重取色。页面在 auto 模式下会重新 applyTheme，
  /// 随后通过 setTheme 回报结果，系统栏再由 _onHostTheme 跟着改。
  @override
  void didChangePlatformBrightness() {
    final dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    unawaited(_controller.runJavaScript(
        'window.__sgsShellDark && window.__sgsShellDark($dark)'));
  }

  /// 旋转、分屏、折叠屏展开等导致窗口尺寸/安全区变化时重新上报。
  /// 用这个回调而不是在 build 里挂 postFrameCallback —— 后者每次 rebuild 都会
  /// 堆积一个回调，滚动时父级一 setState 就会白跑一遍 JS。
  @override
  void didChangeMetrics() {
    _insetTop = -1;
    _insetBottom = -1;
    _pushInsets();
  }

  void _onHostTheme(JavaScriptMessage msg) {
    final t = msg.message.trim();
    if (t == _theme) return;
    _theme = t;
    _applySystemBar(_isDark);
  }

  /// 把系统栏染成和页面同色系，并同步图标明暗。
  ///
  /// edge-to-edge 下状态栏本身是透明的，透上来的是 WebView 里页面的背景，
  /// 所以这里只需要管**图标**的颜色；底色留透明，避免出现一条硬边。
  void _applySystemBar(bool dark) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      // iOS：StatusBar 的 brightness 语义与 Android 相反 —— dark 表示深色底、浅色字
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    ));
  }

  /// 把真实的安全区高度喂给页面。
  ///
  /// Android WebView 的 env(safe-area-inset-*) 恒为 0，页面靠 --host-inset-*
  /// 兜底；iOS 上 env() 有值，页面取 max()，两者一致不会重复留白。
  /// MediaQuery.padding 是逻辑像素，与 WebView 的 CSS px 同量纲，不需要再除 dpr。
  void _pushInsets() {
    if (!mounted) return;
    final padding = MediaQuery.of(context).padding;
    final top = padding.top;
    final bottom = padding.bottom;
    if ((top - _insetTop).abs() < 0.5 && (bottom - _insetBottom).abs() < 0.5) {
      return;
    }
    _insetTop = top;
    _insetBottom = bottom;
    unawaited(_controller.runJavaScript(
      'window.__sgsShellInsets && window.__sgsShellInsets('
      '${top.toStringAsFixed(1)}, ${bottom.toStringAsFixed(1)})',
    ));
  }

  @override
  Widget build(BuildContext context) {
    // 一上来就把 WebView 挂进视图树：原生 view 越早进入布局，首帧越连续。
    // 加载遮罩只是盖在上面的一层纯色，不靠「换掉整棵子树」来切换 ——
    // 那种写法会让原生 view 在挂载时重新 layout 一次，旋转/重建时能看到跳一下。
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        WebViewWidget(controller: _controller),
        if (!_ready)
          ColoredBox(
            color: dark ? const Color(0xFF191612) : const Color(0xFFF7F3EC),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(
                    '正在载入图鉴…',
                    style: TextStyle(
                      color: dark ? const Color(0xFFECE3D0) : const Color(0xFF2B2B2B),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
