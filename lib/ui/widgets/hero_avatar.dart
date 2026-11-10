// 通用武将头像：随包 av 优先，缺失时降级成「势力色 + 首字」占位卡。
//
// 主程序里 ni / na 占位标记对应的就是这种卡，视觉口径保持一致。
// il 主视觉和 sk 皮肤图第一版未随包，这里一律走占位，不发起必然失败的网络请求。
import 'package:flutter/material.dart';

import '../../core/seed_asset.dart';
import '../../data/models.dart';

class HeroAvatar extends StatelessWidget {
  const HeroAvatar({
    super.key,
    required this.relPath,
    required this.name,
    required this.kingdom,
    this.fontSize = 28,
    this.borderRadius = 10,
    this.fit = BoxFit.cover,
  });

  final String relPath;
  final String name;
  final String kingdom;
  final double fontSize;
  final double borderRadius;
  final BoxFit fit;

  Color get _color =>
      Color(kKingdomArgb[kingdom] ?? 0xFF88857E);

  @override
  Widget build(BuildContext context) {
    final bundled = relPath.isNotEmpty && SeedAsset.isBundled(relPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: bundled
          ? Image.asset(
              SeedAsset.of(relPath),
              fit: fit,
              errorBuilder: (_, _, _) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    final c = _color;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            c.withValues(alpha: 0.34),
            c.withValues(alpha: 0.08),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }
}
