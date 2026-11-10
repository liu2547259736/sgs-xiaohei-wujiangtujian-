import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'hero_avatar.dart';

class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.hero,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  final HeroSummary hero;
  final bool isFavorite;
  final VoidCallback onTap;
  final void Function(String key) onFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kingdomColor =
        Color(kKingdomArgb[hero.kingdom] ?? 0xFF88857E);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  HeroAvatar(
                    relPath: hero.avatar,
                    name: hero.name,
                    kingdom: hero.kingdom,
                    borderRadius: 0,
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 4, color: kingdomColor),
                  ),
                  Positioned(
                    right: 4,
                    top: 2,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        color: isFavorite
                            ? Colors.amber
                            : Colors.white.withValues(alpha: 0.92),
                        icon: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                        onPressed: () => onFavorite(hero.key),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.favorite,
                              size: 11, color: Colors.redAccent),
                          const SizedBox(width: 3),
                          Text(
                            hero.hpText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hero.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hero.title.isEmpty
                        ? (kKingdomLabel[hero.kingdom] ?? '—')
                        : hero.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
