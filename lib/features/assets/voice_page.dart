// 武将台词与官方语音播放。
// 语音文件 26556 个 / 1621 MB，按规则未进 git 与随包，所以只在配置了
// 语音资源根时才真正播放；未配置时台词文本照常可读、按钮明确禁用。
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../common/app_scopes.dart';
import '../settings/settings_page.dart';
import 'asset_roots.dart';
import 'voice_player.dart';

class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.detail});

  final HeroDetail detail;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final VoicePlayer _player = VoicePlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roots = AssetRootsScope.of(context);
    final theme = Theme.of(context);
    final d = widget.detail;
    final supported =
        d.version == 'sgsol' || d.version == 'msgs';

    return AnimatedBuilder(
      animation: _player,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('${d.name} · 台词与语音'),
          actions: <Widget>[
            if (_player.isPlaying)
              IconButton(
                tooltip: '停止播放',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: _player.stop,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: <Widget>[
            _notice(theme, roots, supported, d.version),
            const SizedBox(height: 10),
            if (d.voiceGroups.isNotEmpty)
              for (final group in d.voiceGroups) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(group.name.isEmpty ? '台词' : group.name,
                      style: theme.textTheme.titleSmall),
                ),
                for (final item in group.items) _itemCard(theme, roots, item),
              ]
            else ...<Widget>[
              Text('该版本没有官方语音分组数据，以下为武将台词文本。',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final e in d.quotes.entries)
                Card(
                  child: ListTile(
                    title: Text(e.key),
                    subtitle: Text(e.value),
                  ),
                ),
              if (d.voiceLines.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('OL 台词摘录', style: theme.textTheme.titleSmall),
                for (final l in d.voiceLines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(l, style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
            if (_player.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_player.error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notice(ThemeData theme, AssetRoots roots, bool supported, String v) {
    final missing = !roots.hasVoiceSource;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: missing
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(missing ? Icons.info_outline : Icons.volume_up_outlined,
              color: missing ? theme.colorScheme.onErrorContainer : null),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              missing
                  ? '语音库未托管（26556 个 / 1621 MB）。在设置里填语音资源根后可播放；台词文本不受影响。'
                  : supported
                      ? '语音资源根已配置，点击 ▶ 播放（${v == 'sgsol' ? 'ogg' : 'mp3'}）。'
                      : '主程序只有 sgsol / msgs 两个版本收录官方语音，当前版本 ($v) 无音频包。',
              style: TextStyle(
                  color: missing ? theme.colorScheme.onErrorContainer : null),
            ),
          ),
          if (missing)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
              child: const Text('去设置'),
            ),
        ],
      ),
    );
  }

  Widget _itemCard(ThemeData theme, AssetRoots roots, VoiceItem item) {
    final urls = item.clipIds
        .map((id) => roots.voiceUrl(widget.detail.version, id))
        .whereType<String>()
        .toList();
    final canPlay = urls.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.kind.isEmpty ? '台词' : item.kind,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final l in item.lines)
                    Text('「$l」', style: theme.textTheme.bodySmall),
                  if (!canPlay)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('该条无可用音频',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: canPlay ? '播放 ${urls.length} 条语音' : '语音不可用',
              icon: Icon(
                (urls.isNotEmpty && _player.playingUrl == urls.first)
                    ? Icons.stop
                    : Icons.play_arrow,
              ),
              onPressed: canPlay ? () => _player.toggle(urls.first) : null,
            ),
          ],
        ),
      ),
    );
  }
}
