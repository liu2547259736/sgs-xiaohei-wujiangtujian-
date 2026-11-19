import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shell/shell_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 全屏（edge-to-edge）：让内容延伸到状态栏与导航栏后面。
  //
  // 这样「屏幕上没有第二条颜色」—— 状态栏区域透上来的是 WebView 里页面自己的
  // 背景，而不是 Flutter 的一层底色。安全区由原页面 CSS 的 --sb-top / --sb-bottom
  // 自己避让（壳通过 window.__sgsShellInsets 把真实高度喂进去），
  // 状态栏图标明暗由 MobileWebView 按页面回报的主题染色。
  //
  // Web 端没有系统栏，这个调用在 web 上是空操作，不影响浏览器版本。
  // ignore: discarded_futures
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ShellApp());
}
