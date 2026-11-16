// 把「本体更新 → 数据仓库 → 多端原页面」这条链路接到 WebView 壳上。
//
// 数据流：
//   主程序 sgs-heroes-app
//     → snapshot.py 刷新 legacy-web（原页面完整镜像）
//     → migrate.py::copy_shell() 把原页面骨架按**同样的相对路径**放进 data-repo
//     → build_manifest.py 把这些文件纳入 manifest（带 sha256）
//     → sync.py push + 打 tag，jsDelivr 上就是一份可直接浏览的原页面
//     → 这里拉差异文件写进覆盖层
//     → ShellServer 覆盖层优先，原页面 fetch('data/...') 直接读到新数据
//     → WebView reload，用户看到的就是新版，全程不用重新发安装包
//
// 为什么能不改原页面：覆盖层路径 == URL 路径 == data-repo 相对路径。
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../core/env.dart';
import '../core/sync/git_update_service.dart';
import '../core/sync/persistent_update_sink.dart';
import '../core/sync/update_protocol.dart';
import 'shell_config.dart';

class ShellUpdater {
  ShellUpdater({UpdateSink? sink}) : _sink = sink ?? createPersistentSink();

  final UpdateSink _sink;

  UpdateSink get sink => _sink;

  /// data-repo 里只有这几类目录是 Flutter 数据分片，原页面不会请求，
  /// 拉下来纯属浪费带宽。其余（根级页面文件 + data/ images/ fonts/ …）
  /// 全部按原页面路径纳入。
  static bool isShellPath(String path) {
    const dataOnly = <String>['heroes/', 'skins/', 'meta/', 'history/', 'tools/'];
    for (final prefix in dataOnly) {
      if (path.startsWith(prefix)) return false;
    }
    return true;
  }

  /// 首次启动用的随包基线：sync_shell_assets.py 为每个随包文件算好 sha256，
  /// 与 data-repo/manifest.json 里的 hash 是同一份字节、同一个值。
  /// 登记后只下载真正变化的文件，不会把 200MB 重下一遍。
  Future<DataManifest> _seedBaseline() async {
    final raw = jsonDecode(await rootBundle.loadString(kShellHashes))
        as Map<String, dynamic>;
    final hashes = (raw['hashes'] as Map? ?? const {})
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    return DataManifest(
      schema: 1,
      version: (raw['version'] ?? '0').toString(),
      updatedAt: '',
      counts: const <String, int>{},
      files: <DataFileEntry>[
        for (final e in hashes.entries)
          DataFileEntry(path: e.key, sha256: e.value, bytes: 0),
      ],
    );
  }

  Future<UpdateResult> checkAndApply() async {
    final seed = await _seedBaseline();
    if (!Env.hasRemote) {
      return UpdateResult(
        status: UpdateStatus.offline,
        version: seed.version,
        message: Env.notConfigured,
      );
    }
    final service = GitUpdateService(
      baseUrls: Env.dataBaseUrls(seed.version),
      manifestUrls: Env.manifestUrls(),
      urlBuilder: Env.dataBaseUrls,
      sink: _sink,
      accept: isShellPath,
      allowDowngrade: false,
      // jsDelivr 新 tag 刚发布时边缘节点会偶发 403，第二轮通常就通了。
      fetchRounds: 2,
      // 2.9MB 的 characters.json 在健康源上要 1~6 秒，20 秒默认值对
      // 移动网络偏紧；45 秒能给到约 520Kbps 的下限，同时卡死源也能
      // 在可接受时间内放弃、回退到下一源。
      requestTimeout: const Duration(seconds: 45),
    );
    try {
      return await service.checkAndApply(seed: seed);
    } finally {
      service.dispose();
    }
  }
}
