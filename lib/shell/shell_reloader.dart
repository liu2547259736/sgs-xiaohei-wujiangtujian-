// 更新完成后让当前承载原页面的 WebView 重新加载。
//
// 移动/苹果端是内嵌 WebViewWidget.reload()，Windows/Linux 是桌面原生窗口
// Webview.reload()，两者 API 不同。用一个极小的句柄把差异收在 view 内部，
// ShellApp 只管「更新好了 → 调一下」，不用知道当前跑在哪一端。
class ShellReloader {
  Future<void> Function()? _reload;

  void attach(Future<void> Function() fn) => _reload = fn;

  void detach(Future<void> Function() fn) {
    if (identical(_reload, fn)) _reload = null;
  }

  /// 没有挂载 view（加载中 / 桌面窗口没起来）时静默跳过，不抛异常。
  Future<void> call() async {
    final fn = _reload;
    if (fn != null) await fn();
  }
}
