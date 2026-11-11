// Windows / Linux：用桌面原生浏览器窗口承载 1:1 原页面。
//
// webview_flutter 官方只实现 Android 与 WKWebView(iOS/macOS)，桌面端调用会抛
// UnimplementedError。desktop_webview_window 补上 Windows WebView2 与 Linux
// WebKitGTK：它是独立原生窗口，但里面加载的仍是同一个 index.html / style.css /
// app.js，页面内容一个像素都不差。
//
// 插件不可用（缺 WebView2 Runtime / WebKitGTK）时不白屏：降级成系统浏览器打开
// 同一个本地地址，并给出可直接点的按钮。
import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'shell_reloader.dart';

class DesktopWebView extends StatefulWidget {
  const DesktopWebView({
    super.key,
    required this.url,
    required this.reloader,
  });

  final String url;
  final ShellReloader reloader;

  @override
  State<DesktopWebView> createState() => _DesktopWebViewState();
}

class _DesktopWebViewState extends State<DesktopWebView> {
  Webview? _webview;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _reload() async => _webview?.reload();

  Future<void> _boot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await WebviewWindow.isWebviewAvailable()) {
        throw StateError(
          Platform.isWindows
              ? '未检测到 WebView2 Runtime（Windows 10 需要单独安装）'
              : '未检测到可用的 WebKitGTK 运行时',
        );
      }

      // WebView2 的用户数据目录必须可写；装到 Program Files 时默认目录只读，
      // 会导致 create_failed。统一放到应用支持目录下。
      WindowsWebviewOptions windowsOptions = const WindowsWebviewOptions();
      if (Platform.isWindows) {
        final base = await getApplicationSupportDirectory();
        final dir = Directory(
            '${base.path}${Platform.pathSeparator}WebView2Profile');
        if (!await dir.exists()) await dir.create(recursive: true);
        windowsOptions = WindowsWebviewOptions(userDataFolder: dir.path);
      }

      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: '三国杀武将图鉴',
          windowWidth: 1280,
          windowHeight: 820,
          windows: windowsOptions,
        ),
      );
      await webview.launch(widget.url);
      _webview = webview;
      widget.reloader.attach(_reload);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _reopen() async {
    final webview = _webview;
    if (webview != null) {
      await webview.launch(widget.url);
    } else {
      await _boot();
    }
  }

  Future<void> _openInBrowser() async {
    final url = widget.url;
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      }
    } catch (_) {
      // 系统浏览器也打不开时，错误页上的地址仍可手动复制。
    }
  }

  @override
  void dispose() {
    widget.reloader.detach(_reload);
    final webview = _webview;
    if (webview != null) unawaited(webview.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在打开图鉴窗口…'),
          ],
        ),
      );
    }
    final error = _error;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                error == null
                    ? Icons.open_in_new
                    : Icons.error_outline,
                size: 40,
                color: error == null
                    ? const Color(0xFF982B2B)
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                error == null ? '图鉴已在独立窗口打开' : '独立窗口打开失败',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error ??
                    '主界面由原页面 1:1 呈现。若窗口被关闭，点下面的按钮重新打开；'
                        '也可以在系统浏览器里查看同一个地址。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              SelectableText(
                widget.url,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: error == null ? _reopen : _boot,
                    icon: const Icon(Icons.refresh),
                    label: Text(error == null ? '重新打开' : '重试'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openInBrowser,
                    icon: const Icon(Icons.public),
                    label: const Text('用浏览器打开'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
