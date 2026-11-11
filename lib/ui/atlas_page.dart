// 图鉴主页：吸顶筛选 + 虚拟滚动网格 + 详情抽屉。
// 对应主程序 index.html 的「图鉴页」，但只保留已定范围内的功能。
import 'package:flutter/material.dart';

import '../data/atlas_controller.dart';
import '../data/models.dart';
import 'hero_detail_sheet.dart';
import 'widgets/filter_bar.dart';
import 'widgets/hero_card.dart';

class AtlasPage extends StatefulWidget {
  const AtlasPage({super.key, required this.controller});

  final AtlasController controller;

  @override
  State<AtlasPage> createState() => _AtlasPageState();
}

class _AtlasPageState extends State<AtlasPage> {
  final TextEditingController _search = TextEditingController();

  AtlasController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('三国杀武将图鉴'),
          centerTitle: false,
          actions: <Widget>[
            IconButton(
              tooltip: '切换主题（跟随系统 / 浅色 / 深色）',
              icon: Icon(switch (c.themeMode) {
                ThemeMode.system => Icons.brightness_auto,
                ThemeMode.light => Icons.light_mode,
                ThemeMode.dark => Icons.dark_mode,
              }),
              onPressed: c.toggleTheme,
            ),
            IconButton(
              tooltip: '检查并应用数据更新',
              icon: c.checkingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined),
              onPressed: c.checkingUpdate ? null : c.checkUpdate,
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    switch (c.status) {
      case AtlasStatus.loading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在加载随包武将数据…'),
            ],
          ),
        );
      case AtlasStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                Text('加载失败：${c.errorMessage}'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: c.init,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      case AtlasStatus.ready:
        return Column(
          children: <Widget>[
            FilterBar(controller: c, searchController: _search),
            _statusBar(),
            Expanded(child: _grid()),
          ],
        );
    }
  }

  Widget _statusBar() {
    final theme = Theme.of(context);
    final v = c.data.versionOf(c.selectedVersion);
    return InkWell(
      onTap: c.checkingUpdate ? null : c.checkUpdate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.45),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.storage_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                c.updateSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${v?.label ?? c.selectedVersion} · ${c.visibleHeroes.length}/${v?.count ?? c.heroCount} 将',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final list = c.visibleHeroes;
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.search_off, size: 42),
            const SizedBox(height: 10),
            const Text('没有符合条件的武将'),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _search.clear();
                c.clearFilters();
              },
              child: const Text('清除筛选'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.72,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final h = list[i];
        return HeroCard(
          hero: h,
          isFavorite: c.isFavorite(h.key),
          onTap: () => _openDetail(h),
          onFavorite: c.toggleFavorite,
        );
      },
    );
  }

  Future<void> _openDetail(HeroSummary h) async {
    final detail = await c.detailOf(h);
    if (!mounted) return;
    await HeroDetailSheet.show<void>(
      context,
      detail: detail,
      animation: c,
      isFavorite: () => c.isFavorite(h.key),
      onFavorite: () => c.toggleFavorite(h.key),
    );
  }
}
