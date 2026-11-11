// 多端共用的「从 Git 托管的数据仓库拉文件更新」服务。
//
// 一份代码覆盖 Flutter 六端（Android / iOS / Windows / macOS / Linux / Web）：
// 只用 package:http + package:crypto，不引 dart:io，Web 也能编译。
// 平台差异全部收在 UpdateSink 里（native 落文件系统，Web 落 IndexedDB）。
//
// P1 建工程时 pubspec.yaml 需要：
//   dependencies:
//     http: ^1.2.0
//     crypto: ^3.0.3
//
// 数据源按顺序回退（tag 是 immutable，命中后天然永久缓存）：
//   https://cdn.jsdelivr.net/gh/<user>/<repo>@data-v<version>
//   https://fastly.jsdelivr.net/gh/<user>/<repo>@data-v<version>
//   https://raw.githubusercontent.com/<user>/<repo>/data-v<version>
//
// 重要：这里更新的是「数据 / 图片 / 配置」，不是 Dart 代码。
// Flutter 是 AOT 编译，代码变更必须重新打包发版，不能靠拉 git 文件热更新。
//
// 典型用法：
//   final service = GitUpdateService(baseUrls: Env.dataBaseUrls, sink: sink);
//   final seed = DataManifest.fromJson(
//       jsonDecode(await rootBundle.loadString('assets/seed/manifest.json')));
//   final result = await service.checkAndApply(seed: seed);
//   // 启动流程：先用 seed 渲染，后台跑 checkAndApply，失败静默降级。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'update_protocol.dart';

class GitUpdateService {
  GitUpdateService({
    required this.baseUrls,
    required this.sink,
    this.manifestUrls,
    this.urlBuilder,
    this.accept,
    this.allowDowngrade = true,
    this.fetchRounds = 1,
    http.Client? client,
    this.maxParallel = 4,
    this.requestTimeout = const Duration(seconds: 20),
  })  : assert(baseUrls.isNotEmpty, 'baseUrls 不能为空'),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final List<String> baseUrls;

  /// 版本发现源（浮动分支）。不传则直接用 baseUrls，行为与旧版一致。
  final List<String>? manifestUrls;

  /// 拿到远端 version 后，按该版本重新生成文件源（immutable tag）。
  /// 不传则所有文件都从 baseUrls 拉。
  final List<String> Function(String version)? urlBuilder;

  /// 只处理这些路径的文件。原页面壳用它可以跳过 heroes/ skins/ meta/
  /// history/ 等 Flutter 数据分片，只拉 index.html / style.css / app.js /
  /// data/** / fonts/** / images/**，避免一次下载几十 MB 无关 JSON。
  /// 不传 = 全量接收，行为与旧版一致。
  final bool Function(String path)? accept;

  /// 远端版本比本地旧时不覆盖（避免新装 App 被旧 tag 回退）。
  /// 默认 true 以兼容既有测试与「强制重拉」场景，壳里显式传 false。
  final bool allowDowngrade;

  /// 所有源都失败后再从头重试的轮数。jsDelivr 新 tag 刚发布时，
  /// 边缘节点会对个别文件间歇性返回 403（缓存未热），隔几百毫秒再试
  /// 通常就 200 了。默认 1 保持既有行为，壳端传 2。
  final int fetchRounds;

  final UpdateSink sink;
  final int maxParallel;
  final Duration requestTimeout;
  final http.Client _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// [seed] 是随 App 打包的基线 manifest（首次启动传一次即可），
  /// 登记它的 hash 后不会把 148 MB 数据重下一遍。
  /// [dryRun] 为 true 时只检查不下载，给设置页「检查更新」按钮用。
  Future<UpdateResult> checkAndApply({
    DataManifest? seed,
    bool dryRun = false,
  }) async {
    // 首次启动：把随包 seed 的 hash 登记为基线。
    if (await sink.appliedVersion() == null && seed != null) {
      await sink.begin();
      await sink.commit(seed.version, seed.hashByPath);
    }
    final currentVersion = await sink.appliedVersion() ?? '';

    // 1. 取远端 manifest，任一镜像成功即可。
    DataManifest? remote;
    Uint8List? manifestBytes;
    Object? manifestError;
    for (final base in (manifestUrls ?? baseUrls)) {
      try {
        final resp = await _client
            .get(Uri.parse(_join(base, 'manifest.json')))
            .timeout(requestTimeout);
        if (resp.statusCode != 200) {
          manifestError = 'HTTP ${resp.statusCode}';
          continue;
        }
        remote = DataManifest.fromJson(
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
        manifestBytes = resp.bodyBytes;
        break;
      } catch (e) {
        manifestError = e;
      }
    }
    if (remote == null) {
      return UpdateResult(
        status: UpdateStatus.offline,
        version: currentVersion,
        message: '取不到 manifest: $manifestError',
      );
    }
    if (remote.version == currentVersion) {
      return UpdateResult(
          status: UpdateStatus.upToDate, version: remote.version);
    }
    if (!allowDowngrade &&
        currentVersion.isNotEmpty &&
        compareVersion(remote.version, currentVersion) <= 0) {
      return UpdateResult(
          status: UpdateStatus.upToDate, version: currentVersion);
    }

    // 2. 比对 sha256，只取变化的文件（并按壳的白名单过滤）。
    final local = await sink.appliedHashes();
    final acceptPath = accept;
    final pending = remote.files
        .where((f) => local[f.path] != f.sha256)
        .where((f) => acceptPath == null || acceptPath(f.path))
        .toList(growable: false);
    final pendingBytes = pending.fold<int>(0, (sum, f) => sum + f.bytes);

    // commit 只登记本次真正纳入管理的文件，别把被过滤掉的路径虚报成
    // 「已应用」，否则下次 hash 比对会失去意义。
    final effectiveHashes = acceptPath == null
        ? remote.hashByPath
        : <String, String>{
            for (final e in remote.hashByPath.entries)
              if (acceptPath(e.key)) e.key: e.value,
          };

    // 版本发现走浮动分支，但文件必须锁到远端版本对应的 immutable tag，
    // 否则下载途中分支又更新，会出现 manifest 与文件版本错配。
    final built = urlBuilder == null ? null : urlBuilder!(remote.version);
    final fileSources =
        (built == null || built.isEmpty) ? baseUrls : built;

    if (dryRun) {
      return UpdateResult(
        status: UpdateStatus.updateAvailable,
        version: remote.version,
        pendingCount: pending.length,
        pendingBytes: pendingBytes,
      );
    }
    if (pending.isEmpty) {
      // 只有 version 变了、文件内容没变：直接推进版本号。
      await sink.begin();
      await _writeManifest(manifestBytes);
      await sink.commit(remote.version, effectiveHashes);
      return UpdateResult(
          status: UpdateStatus.updated, version: remote.version);
    }

    // 3. 分批下载，每个文件校验 size + sha256；边下边写，不把全量放内存。
    await sink.begin();
    await _writeManifest(manifestBytes);
    var downloaded = 0;
    var phase = 'download';
    final changed = <String>[];
    try {
      for (var i = 0; i < pending.length; i += maxParallel) {
        phase = 'download';
        final batch = pending.skip(i).take(maxParallel).toList(growable: false);
        final fetched = await Future.wait(
          batch.map((f) => _fetch(fileSources, f)),
        );
        phase = 'write';
        for (final item in fetched) {
          await sink.write(item.entry.path, item.bytes);
          changed.add(item.entry.path);
          downloaded += item.bytes.length;
        }
      }
      // 4. 全部成功后才推进 version —— 中途失败旧数据仍然完整可读。
      phase = 'commit';
      await sink.commit(remote.version, effectiveHashes);
    } catch (e) {
      await sink.rollback();
      return UpdateResult(
        status: phase == 'download'
            ? UpdateStatus.downloadFailed
            : UpdateStatus.writeFailed,
        version: currentVersion,
        changedPaths: changed,
        downloadedBytes: downloaded,
        message: '$e',
      );
    }
    return UpdateResult(
      status: UpdateStatus.updated,
      version: remote.version,
      changedPaths: changed,
      downloadedBytes: downloaded,
    );
  }

  /// 单文件下载，主源失败时自动试其它镜像。
  Future<_Fetched> _fetch(List<String> sources, DataFileEntry entry) async {
    Object? lastError;
    for (var round = 0; round < fetchRounds; round++) {
      for (final base in sources) {
        try {
          final resp = await _client
              .get(Uri.parse(_join(base, entry.path)))
              .timeout(requestTimeout);
          if (resp.statusCode != 200) {
            lastError = 'HTTP ${resp.statusCode}';
            continue;
          }
          final bytes = resp.bodyBytes;
          if (bytes.length != entry.bytes) {
            lastError = 'size mismatch';
            continue;
          }
          if (sha256.convert(bytes).toString() != entry.sha256) {
            lastError = 'sha256 mismatch';
            continue;
          }
          return _Fetched(entry, bytes);
        } catch (e) {
          lastError = e;
        }
      }
      // 只在不同轮之间留一点时间，让 CDN 边缘节点缓存有机会热起来。
      if (round + 1 < fetchRounds) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw StateError('${entry.path}: $lastError');
  }

  /// 把远端 manifest 一并写进覆盖层：Repository 会优先用它当 seed 基线，
  /// 这样更新后页面里的「数据版本」和分片清单能立刻跟着新版本走。
  Future<void> _writeManifest(Uint8List? bytes) async {
    if (bytes != null) await sink.write('manifest.json', bytes);
  }

  /// 点分/短横分隔的数字版本比较，如 2026.11.10-2 < 2026.11.11。
  /// 非数字段按 0 处理，未知格式不会抛异常。
  static int compareVersion(String a, String b) {
    List<int> parts(String s) => s
        .split(RegExp(r'[.\-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static String _join(String base, String path) {
    final prefix = base.endsWith('/') ? base : '$base/';
    return prefix + path.split('/').map(Uri.encodeComponent).join('/');
  }
}

class _Fetched {
  const _Fetched(this.entry, this.bytes);

  final DataFileEntry entry;
  final Uint8List bytes;
}
