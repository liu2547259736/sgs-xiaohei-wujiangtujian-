// Web 分支：线上 Web 产物就是 legacy-web 里的原页面本身，不走 Flutter。
// 这个文件只为让条件导出在 Web 平台可编译；正常发布物里没有 main.dart.js。
import 'package:flutter/material.dart';

class ShellApp extends StatelessWidget {
  const ShellApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '三国杀武将图鉴',
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Web 版请直接使用同步发布的原页面（legacy-web），无需 Flutter 壳。',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
