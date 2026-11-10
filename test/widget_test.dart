// 首屏组件冒烟测试：不依赖 seed assets，验证「无图时降级占位卡」这条路径。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sgs_heroes/ui/widgets/hero_avatar.dart';

void main() {
  testWidgets('头像缺失时显示势力色 + 首字占位卡', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: HeroAvatar(
              relPath: '',
              name: '关羽',
              kingdom: 'shu',
            ),
          ),
        ),
      ),
    );
    expect(find.text('关'), findsOneWidget);
  });

  testWidgets('未随包的 il 主视觉同样走占位，不触发网络加载',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: HeroAvatar(
              relPath: 'images/sgsol/il/std_guanyu.webp',
              name: '关羽',
              kingdom: 'shu',
            ),
          ),
        ),
      ),
    );
    expect(find.text('关'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
