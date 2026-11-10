// 数据仓库更新协议 —— 与 data-repo/tools/build_manifest.py 产出的 manifest.json 一一对应。
//
// 六端共用（Android / iOS / Windows / macOS / Linux / Web）。
// 本文件只用 Dart 核心库，不引 dart:io，Web 也能编译。
import 'dart:typed_data';

/// manifest.files[] 里的一条。
class DataFileEntry {
  const DataFileEntry({
    required this.path,
    required this.sha256,
    required this.bytes,
  });

  final String path;
  final String sha256;
  final int bytes;

  factory DataFileEntry.fromJson(Map<String, dynamic> json) => DataFileEntry(
        path: json['path'] as String,
        sha256: json['sha256'] as String,
        bytes: (json['bytes'] as num).toInt(),
      );
}

/// 数据仓库的唯一契约。App 只认 version 和 files[]，不知道数据是怎么抓来的。
class DataManifest {
  const DataManifest({
    required this.schema,
    required this.version,
    required this.updatedAt,
    required this.counts,
    required this.files,
  });

  final int schema;
  final String version;
  final String updatedAt;
  final Map<String, int> counts;
  final List<DataFileEntry> files;

  factory DataManifest.fromJson(Map<String, dynamic> json) {
    final schema = (json['schema'] as num?)?.toInt() ?? 0;
    if (schema != 1) {
      throw FormatException('unsupported manifest schema: $schema');
    }
    final rawFiles = (json['files'] as List?) ?? const [];
    return DataManifest(
      schema: schema,
      version: json['version'] as String,
      updatedAt: (json['updated_at'] as String?) ?? '',
      counts: ((json['counts'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
      files: rawFiles
          .map((e) => DataFileEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }

  Map<String, String> get hashByPath => {
        for (final f in files) f.path: f.sha256,
      };
}

enum UpdateStatus {
  /// 本地已是最新
  upToDate,

  /// dryRun 模式：发现新版本但没下载
  updateAvailable,

  /// 已下载并应用
  updated,

  /// 所有数据源都取不到 manifest（断网 / CDN 挂）—— 静默降级用 seed 数据
  offline,

  /// manifest 解析失败或 schema 不支持
  invalidManifest,

  /// 某个文件下载失败或 sha256 对不上
  downloadFailed,

  /// 落盘 / 事务提交失败
  writeFailed,
}

class UpdateResult {
  const UpdateResult({
    required this.status,
    required this.version,
    this.changedPaths = const <String>[],
    this.downloadedBytes = 0,
    this.pendingCount = 0,
    this.pendingBytes = 0,
    this.message,
  });

  final UpdateStatus status;
  final String version;
  final List<String> changedPaths;
  final int downloadedBytes;
  final int pendingCount;
  final int pendingBytes;
  final String? message;

  bool get succeeded =>
      status == UpdateStatus.upToDate || status == UpdateStatus.updated;

  /// 给设置页显示的一行状态。
  String get display {
    switch (status) {
      case UpdateStatus.upToDate:
        return '数据已是最新 $version';
      case UpdateStatus.updateAvailable:
        return '发现新版本 $version（$pendingCount 个文件待更新）';
      case UpdateStatus.updated:
        return '已更新到 $version（${changedPaths.length} 个文件）';
      case UpdateStatus.offline:
        return '数据可能不是最新（离线）';
      default:
        return '数据可能不是最新（${message ?? status.name}）';
    }
  }
}

/// 持久化适配层。更新服务只负责「拉取 + 校验 + 交付」，不假设文件系统。
///
/// native：appliedHashes 从 drift 表一次读出；begin 建临时目录，
///         commit 里原子替换并写 version，rollback 删临时目录。
/// Web   ：appliedHashes 从 shared_preferences / IndexedDB 读；
///         begin/commit 用一次 batch 写入。
///
/// 事务语义：只有 commit 才会推进 version。中途失败时旧数据保持可读。
abstract class UpdateSink {
  /// 当前已生效的数据版本；首次启动返回 null。
  Future<String?> appliedVersion();

  /// path -> sha256，尽量一次读出（8221 条约 1 MB）。
  Future<Map<String, String>> appliedHashes();

  /// 开始一次更新，可用来建临时区。默认空实现。
  Future<void> begin() async {}

  /// 写入一个已校验过 sha256 的文件。
  Future<void> write(String path, Uint8List bytes);

  /// 提交：切换临时区、登记全部 hash、推进 version。必须原子。
  Future<void> commit(String version, Map<String, String> hashes);

  /// 放弃本次更新，默认空实现。
  Future<void> rollback() async {}
}
