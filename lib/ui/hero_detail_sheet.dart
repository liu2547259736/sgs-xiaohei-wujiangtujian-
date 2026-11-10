// 武将详情底部抽屉：立绘 / 技能 / 标签 / 生平 / 台词 / 皮肤。
//
// 主程序 detailHTML() 的功能在这里保留核心部分；第一版没有皮肤图与语音播放，
// 对应区域明确标注「未随包」，不做假数据、不发起无效请求。
import 'package:flutter/material.dart';

import '../data/models.dart';
import 'widgets/hero_avatar.dart';

class HeroDetailSheet extends StatelessWidget {
  const HeroDetailSheet({
    super.key,
    required this.detail,
    required this.isFavorite,
    required this.onFavorite,
    required this.scrollController,
  });

  final HeroDetail detail;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final ScrollController scrollController;

  static Future<T?> show<T>(
    BuildContext context, {
    required HeroDetail detail,
    required bool Function() isFavorite,
    required VoidCallback onFavorite,
    Listenable? animation,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (ctx, controller) {
          Widget sheet() => HeroDetailSheet(
                detail: detail,
                isFavorite: isFavorite(),
                onFavorite: onFavorite,
                scrollController: controller,
              );
          return animation == null
              ? sheet()
              : AnimatedBuilder(
                  animation: animation,
                  builder: (_, _) => sheet(),
                );
        },
      ),
    );
  }

  static const Map<String, String> _skillTypes = <String, String>{
    'active': '主动',
    'passive': '被动',
    'lock': '锁定',
    'limited': '限定',
    'awakening': '觉醒',
    'transform': '转换',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kingdomColor =
        Color(kKingdomArgb[detail.kingdom] ?? 0xFF88857E);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${detail.name} · ${detail.title.isEmpty ? (kKingdomLabel[detail.kingdom] ?? '') : detail.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: isFavorite ? '取消收藏' : '收藏',
                  color: isFavorite ? Colors.amber : null,
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  onPressed: onFavorite,
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 210,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        HeroAvatar(
                          relPath: detail.avatar,
                          name: detail.name,
                          kingdom: detail.kingdom,
                          borderRadius: 0,
                          fontSize: 72,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                kingdomColor.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 12,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                detail.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  shadows: <Shadow>[
                                    Shadow(color: Colors.black54, blurRadius: 8)
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Text(
                                  '体力 ${detail.hpText}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    shadows: <Shadow>[
                                      Shadow(
                                          color: Colors.black54, blurRadius: 6)
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _tag(kKingdomLabel[detail.kingdom] ?? detail.kingdom),
                    if (detail.level.isNotEmpty) _tag(detail.level),
                    if (detail.group.isNotEmpty) _tag(detail.group),
                    if (detail.subPack.isNotEmpty) _tag(detail.subPack),
                    if (detail.gender == 'male') _tag('男'),
                    if (detail.gender == 'female') _tag('女'),
                  ],
                ),
                if (detail.skills.isNotEmpty)
                  _Section(
                    title: '技能',
                    child: Column(
                      children: detail.skills
                          .map((s) => Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                      color: theme.colorScheme.outlineVariant),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Text(
                                            s.name,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700),
                                          ),
                                          const SizedBox(width: 8),
                                          if (s.type.isNotEmpty)
                                            Text(
                                              _skillTypes[s.type] ?? s.type,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: theme
                                                    .colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        s.description.isEmpty
                                            ? s.oneSentence
                                            : s.description,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                if (detail.tags.isNotEmpty || detail.otherTags.isNotEmpty)
                  _Section(
                    title: '定位',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        ...detail.tags.map(_tag),
                        ...detail.otherTags.map(_tag),
                      ],
                    ),
                  ),
                if (detail.bio.isNotEmpty)
                  _Section(
                      title: '生平', child: Text(detail.bio, style: theme.textTheme.bodyMedium)),
                if (detail.footnote.isNotEmpty)
                  _Section(
                      title: '一句话点评',
                      child: Text(detail.footnote, style: theme.textTheme.bodyMedium)),
                if (detail.quotes.isNotEmpty || detail.voiceLines.isNotEmpty)
                  _Section(
                    title: '台词',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ...detail.quotes.entries.take(6).map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('${e.key}：${e.value}',
                                    style: theme.textTheme.bodyMedium),
                              ),
                            ),
                        ...detail.voiceLines.take(4).map(
                              (l) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(l,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                              ),
                            ),
                      ],
                    ),
                  ),
                if (detail.skinPaths.isNotEmpty || detail.skins.isNotEmpty)
                  _Section(
                    title: '皮肤（${detail.skinPaths.length}）',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (detail.skins.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: detail.skins
                                .take(8)
                                .map((s) => _tag(s.name))
                                .toList(),
                          )
                        else
                          Text('该版本未提供皮肤名称',
                              style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Text(
                          '皮肤图未随包分发，需联网后按需下载。',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  '图片版权归原作者及官方所有，仅供个人学习欣赏，请勿商用。'
                  '${detail.quoteSource.isEmpty ? '' : ' 台词出处：${detail.quoteSource}'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label) => Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
