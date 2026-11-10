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
    http.Client? client,
    this.maxParallel = 4,
    this.requestTimeout = const Duration(seconds: 20),
  })  : assert(baseUrls.isNotEmpty, 'baseUrls 不能为空'),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final List<String> baseUrls;
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
    String? workingBase;
    Object? manifestError;
    for (final base in baseUrls) {
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
        workingBase = base;
        break;
      } catch (e) {
        manifestError = e;
      }
    }
    if (remote == null || workingBase == null) {
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

    // 2. 比对 sha256，只取变化的文件。
    final local = await sink.appliedHashes();
    final pending = remote.files
        .where((f) => local[f.path] != f.sha256)
        .toList(growable: false);
    final pendingBytes = pending.fold<int>(0, (sum, f) => sum + f.bytes);

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
      await sink.commit(remote.version, remote.hashByPath);
      return UpdateResult(
          status: UpdateStatus.updated, version: remote.version);
    }

    // 3. 分批下载，每个文件校验 size + sha256；边下边写，不把全量放内存。
    await sink.begin();
    var downloaded = 0;
    var phase = 'download';
    final changed = <String>[];
    try {
      for (var i = 0; i < pending.length; i += maxParallel) {
        phase = 'download';
        final batch = pending.skip(i).take(maxParallel).toList(growable: false);
        final fetched = await Future.wait(
          batch.map((f) => _fetch(workingBase!, f)),
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
      await sink.commit(remote.version, remote.hashByPath);
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
  Future<_Fetched> _fetch(String primary, DataFileEntry entry) async {
    final ordered = <String>[primary, ...baseUrls.where((b) => b != primary)];
    Object? lastError;
    for (final base in ordered) {
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
    throw StateError('${entry.path}: $lastError');
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
