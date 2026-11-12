// 设置页：资源根配置 + 数据更新 + 关于。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/atlas_controller.dart';
import '../common/app_scopes.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.controller});

  final AtlasController? controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _skin;
  late final TextEditingController _voice;

  @override
  void initState() {
    super.initState();
    // initState 里不能建立 InheritedWidget 依赖，用不注册依赖的读取；
    // build 里的 AssetRootsScope.of(context) 才负责订阅更新。
    final roots = context
        .getInheritedWidgetOfExactType<AssetRootsScope>()!
        .notifier!;
    _skin = TextEditingController(text: roots.skinBase);
    _voice = TextEditingController(text: roots.voiceBase);
  }

  @override
  void dispose() {
    _skin.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roots = AssetRootsScope.of(context);
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          _title(context, '外部资源根'),
          Text(
            '皮肤 12901 张 / 706 MB 已托管到独立仓 sgs-skins 的 CDN，'
            '壳会自动把皮肤请求转到 CDN；语音 26556 个 / 1621 MB 仍不进 git、不随包。'
            '自建静态站时把访问前缀填在下面；留空 = 主动禁用，不请求无效地址。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _skin,
            decoration: const InputDecoration(
              labelText: '皮肤资源根',
              hintText: 'https://example.com/sgs-heroes/',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _voice,
            decoration: const InputDecoration(
              labelText: '语音资源根',
              hintText: 'https://example.com/sgs-heroes/',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              await roots.setSkinBase(_skin.text);
              await roots.setVoiceBase(_voice.text);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('资源根已保存，重新打开皮肤/语音页生效')));
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存资源根'),
          ),
          const Divider(height: 28),
          _title(context, '数据更新'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: Text('当前数据版本 ${c?.dataVersion ?? '（未加载）'}'),
            subtitle: Text(c?.updateSummary ?? '数据仓库更新走 jsDelivr 增量下载'),
          ),
          FilledButton.icon(
            onPressed: c == null || c.checkingUpdate
                ? null
                : () async {
                    await c.checkUpdate();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(c.updateResult?.display ?? '检查完成')));
                  },
            icon: const Icon(Icons.cloud_sync_outlined),
            label: Text(c?.checkingUpdate == true ? '正在检查…' : '检查并应用更新'),
          ),
          const Divider(height: 28),
          _title(context, '关于'),
          Text(
            '三国杀武将图鉴 · Flutter 六端版\n'
            '数据来自本体 sgs-heroes-app，单向同步到 data-repo，再由 CDN 分发。\n'
            '图片版权归原作者及官方所有，仅供个人学习欣赏，请勿商用。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                  text: 'sgs-heroes / ${c?.dataVersion ?? 'unknown'}'));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已复制版本信息')));
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制版本信息'),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      );
}
