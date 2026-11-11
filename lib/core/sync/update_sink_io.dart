// 生产 UpdateSink · native 版（Android / iOS / Windows / macOS / Linux）。
//
// 落盘位置：<ApplicationSupportDirectory>/sgs_data/
//   _meta.json           version + 全量 path->sha256 + 已覆盖文件清单
//   <data-repo 相对路径>  实际下载的文件，目录结构与 CDN 完全一致
//   .staging/            本次更新的临时区，commit 成功后整体并入
//
// 事务语义：全部文件写进 .staging 之后才逐个搬到正式目录，且 _meta.json
// 最后用 rename 原子替换。中途失败时旧 version 不变，下次启动会按 hash
// 重新拉差异文件；已搬过去的文件内容都是 sha256 校验过的，不会污染读取。
//
// 不引 dart:html，本文件只在 native 编译时被选中（见 persistent_update_sink.dart）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'data_file_source.dart';
import 'update_protocol.dart';

typedef PersistentUpdateSink = FileUpdateSink;

PersistentUpdateSink createPersistentSink() => FileUpdateSink();

class FileUpdateSink implements UpdateSink, DataFileSource {
  FileUpdateSink({Future<Directory> Function()? rootProvider})
      : _rootProvider = rootProvider ?? getApplicationSupportDirectory;

  /// 可注入，方便测试用临时目录跑真实文件事务，不依赖平台通道。
  final Future<Directory> Function() _rootProvider;

  static const String _metaName = '_meta.json';
  static const String _stagingName = '.staging';

  Directory? _root;
  bool _primed = false;
  String? _version;
  Map<String, String> _hashes = <String, String>{};
  final Set<String> _overrides = <String>{};
  final Map<String, Uint8List> _readCache = <String, Uint8List>{};
  Directory? _staging;
  final List<String> _stagedPaths = <String>[];

  Future<Directory> get _dataDir async {
    final d = _root ??= Directory(
        '${(await _rootProvider()).path}${Platform.pathSeparator}sgs_data');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safe(String relPath) {
    final p = relPath.replaceAll('\\', '/');
    if (p.isEmpty ||
        p.startsWith('/') ||
        p.split('/').any((s) => s == '..' || s == '.')) {
      throw ArgumentError('非法数据路径: $relPath');
    }
    return p;
  }

  @override
  Future<void> prime() async {
    if (_primed) return;
    final f = File('${(await _dataDir).path}${Platform.pathSeparator}$_metaName');
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _version = j['version'] as String?;
        _hashes = (j['hashes'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString()));
        _overrides.addAll((j['overrides'] as List? ?? const [])
            .map((e) => e.toString()));
      } catch (_) {
        // 元数据损坏：当作首次启动，让 GitUpdateService 重新登记 seed 基线。
        _version = null;
        _hashes = <String, String>{};
        _overrides.clear();
      }
    }
    _primed = true;
  }

  @override
  Future<String?> appliedVersion() async {
    await prime();
    return _version;
  }

  @override
  Future<Map<String, String>> appliedHashes() async {
    await prime();
    return Map<String, String>.unmodifiable(_hashes);
  }

  @override
  bool hasOverride(String relPath) =>
      _overrides.contains(relPath.replaceAll('\\', '/'));

  @override
  Future<Uint8List?> readOverride(String relPath) async {
    if (!hasOverride(relPath)) return null;
    final cached = _readCache[relPath];
    if (cached != null) return cached;
    final f = File('${(await _dataDir).path}${Platform.pathSeparator}'
        '${_safe(relPath).replaceAll('/', Platform.pathSeparator)}');
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    _readCache[relPath] = bytes;
    return bytes;
  }

  @override
  Future<void> begin() async {
    await prime();
    final dir = Directory('${(await _dataDir).path}'
        '${Platform.pathSeparator}$_stagingName');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    _staging = dir;
    _stagedPaths.clear();
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final dir = _staging;
    if (dir == null) throw StateError('write() 之前必须先 begin()');
    final rel = _safe(path);
    final f = File('${dir.path}${Platform.pathSeparator}'
        '${rel.replaceAll('/', Platform.pathSeparator)}');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: false);
    _stagedPaths.add(rel);
  }

  @override
  Future<void> commit(String version, Map<String, String> hashes) async {
    final root = await _dataDir;
    final dir = _staging;
    if (dir != null && await dir.exists()) {
      for (final rel in _stagedPaths) {
        final src = File('${dir.path}${Platform.pathSeparator}'
            '${rel.replaceAll('/', Platform.pathSeparator)}');
        if (!await src.exists()) continue;
        final dst = File('${root.path}${Platform.pathSeparator}'
            '${rel.replaceAll('/', Platform.pathSeparator)}');
        await dst.parent.create(recursive: true);
        if (await dst.exists()) await dst.delete();
        await src.rename(dst.path);
        _overrides.add(rel);
      }
    }

    final meta = File('${root.path}${Platform.pathSeparator}$_metaName');
    final tmp = File('${meta.path}.tmp');
    await tmp.writeAsString(jsonEncode(<String, dynamic>{
      'version': version,
      'hashes': hashes,
      'overrides': _overrides.toList()..sort(),
    }), flush: true);
    if (await meta.exists()) await meta.delete();
    await tmp.rename(meta.path);

    _version = version;
    _hashes = Map<String, String>.from(hashes);
    _readCache.clear();
    await rollback();
  }

  @override
  Future<void> rollback() async {
    final dir = _staging ?? Directory('${(await _dataDir).path}'
        '${Platform.pathSeparator}$_stagingName');
    if (await dir.exists()) await dir.delete(recursive: true);
    _staging = null;
    _stagedPaths.clear();
  }
}
