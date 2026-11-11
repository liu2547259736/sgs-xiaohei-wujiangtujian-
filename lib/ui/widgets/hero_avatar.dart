// 通用武将头像：已下载的更新图 > 随包 av > 「势力色 + 首字」占位卡。
//
// 主程序里 ni / na 占位标记对应的就是这种卡，视觉口径保持一致。
// il 主视觉和 sk 皮肤图未随包，走占位，不发起必然失败的网络请求。
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/seed_asset.dart';
import '../../core/sync/data_file_scope.dart';
import '../../core/sync/data_file_source.dart';
import '../../data/models.dart';

class HeroAvatar extends StatelessWidget {
  const HeroAvatar({
    super.key,
    required this.relPath,
    required this.name,
    required this.kingdom,
    this.source = const BundleOnlySource(),
    this.fontSize = 28,
    this.borderRadius = 10,
    this.fit = BoxFit.cover,
  });

  final String relPath;
  final String name;
  final String kingdom;
  final DataFileSource source;
  final double fontSize;
  final double borderRadius;
  final BoxFit fit;

  Color get _color => Color(kKingdomArgb[kingdom] ?? 0xFF88857E);

  @override
  Widget build(BuildContext context) {
    final effective = DataFileScope.maybeOf(context) ?? source;
    final hasPath = relPath.isNotEmpty;
    final overridden = hasPath && effective.hasOverride(relPath);
    final bundled = hasPath && SeedAsset.isBundled(relPath);
    if (!overridden && !bundled) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _placeholder(),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: overridden
          ? FutureBuilder<Uint8List?>(
              future: effective.readOverride(relPath),
              builder: (context, snap) {
                final bytes = snap.data;
                if (bytes != null) {
                  return Image.memory(
                    bytes,
                    fit: fit,
                    errorBuilder: (_, _, _) => _fallback(bundled),
                  );
                }
                return bundled
                    ? Image.asset(
                        SeedAsset.of(relPath),
                        fit: fit,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                    : _placeholder();
              },
            )
          : Image.asset(
              SeedAsset.of(relPath),
              fit: fit,
              errorBuilder: (_, _, _) => _placeholder(),
            ),
    );
  }

  Widget _fallback(bool bundled) => bundled
      ? Image.asset(
          SeedAsset.of(relPath),
          fit: fit,
          errorBuilder: (_, _, _) => _placeholder(),
        )
      : _placeholder();

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
