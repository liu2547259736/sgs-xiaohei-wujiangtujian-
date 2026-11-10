import 'package:flutter/material.dart';

import 'data/atlas_controller.dart';
import 'ui/atlas_page.dart';

void main() => runApp(const AtlasApp());

class AtlasApp extends StatefulWidget {
  const AtlasApp({super.key});

  @override
  State<AtlasApp> createState() => _AtlasAppState();
}

class _AtlasAppState extends State<AtlasApp> {
  final AtlasController _controller = AtlasController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => MaterialApp(
        title: '三国杀武将图鉴',
        debugShowCheckedModeBanner: false,
        themeMode: _controller.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: AtlasPage(controller: _controller),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8C2E27), // 沿用主程序的蜀红主色
          brightness: brightness,
        ),
      );
}
