// 条件导出：原生端用 WebView 壳，Web 端不引入 dart:io / WebView 插件。
export 'shell_app_native.dart'
    if (dart.library.js_interop) 'shell_app_web.dart';
