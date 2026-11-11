// 皮肤大图浏览。
// 资源本身按设计未进 git / CDN / 随包，这里不伪造内容：
// 配了资源根就真加载，没配就清楚显示占位与配置入口。
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../common/app_scopes.dart';
import '../settings/settings_page.dart';

class SkinGalleryPage extends StatelessWidget {
  const SkinGalleryPage({super.key, required this.detail});

  final HeroDetail detail;

  @override
  Widget build(BuildContext context) {
    final roots = AssetRootsScope.of(context);
    final theme = Theme.of(context);
    final items = detail.skins.isNotEmpty
        ? detail.skins
            .map((s) => (name: s.name, painter: s.painter, path: s.img))
            .toList()
        : detail.skinPaths
            .map((p) => (name: p.split('/').last, painter: '', path: p))
            .toList();

    return Scaffold(
      appBar: AppBar(title: Text('${detail.name} · 皮肤 (${items.length})')),
      body: items.isEmpty
          ? const Center(child: Text('该版本没有收录皮肤数据'))
          : Column(
              children: <Widget>[
                if (!roots.hasSkinSource)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: theme.colorScheme.errorContainer,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.info_outline,
                            color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '皮肤图共 12901 张 / 706 MB，按规则未进 git 与随包。'
                            '在「设置」里填入资源根地址后即可按需加载。',
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const SettingsPage()),
                          ),
                          child: const Text('去设置'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final it = items[i];
                      final url = roots.skinUrl(it.path);
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: url == null
                              ? null
                              : () => _preview(context, url, it.name),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: url == null
                                    ? Container(
                                        color: theme
                                            .colorScheme.surfaceContainerHighest,
                                        alignment: Alignment.center,
                                        child: Icon(Icons.image_not_supported_outlined,
                                            size: 38,
                                            color: theme
                                                .colorScheme.onSurfaceVariant),
                                      )
                                    : Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Icon(
                                            Icons.broken_image_outlined,
                                            color: theme
                                                .colorScheme.onSurfaceVariant),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(it.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium),
                                    if (it.painter.isNotEmpty)
                                      Text('画师：${it.painter}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _preview(BuildContext context, String url, String name) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(name,
                  style: const TextStyle(color: Colors.white70)),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('图片加载失败，请检查资源根地址',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }
}
