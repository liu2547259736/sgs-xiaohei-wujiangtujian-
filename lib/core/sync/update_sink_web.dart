// 生产 UpdateSink · Web 版。
//
// 浏览器没有文件系统，落盘用 IndexedDB：
//   database  sgs_heroes_data / object store `files` / key = data-repo 相对路径
//   value     文件内容的 base64 字符串（避免 typed-data 的 JS 互操作差异）
//   key       __meta__ 存 version / hashes / 覆盖清单（JSON 字符串）
//
// 事务语义：write() 先进内存暂存区，commit() 用**一个** IDBTransaction
// 把全部文件 + 新元数据一起 put，只有 oncomplete 才算成功；中途失败旧版本
// 的元数据保持不变，下次启动按 hash 重新拉差异文件。
//
// 本文件只在 Web 编译时被选中（见 persistent_update_sink.dart）。
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'data_file_source.dart';
import 'update_protocol.dart';

typedef PersistentUpdateSink = WebUpdateSink;

PersistentUpdateSink createPersistentSink() => WebUpdateSink();

class WebUpdateSink implements UpdateSink, DataFileSource {
  static const String _dbName = 'sgs_heroes_data';
  static const String _store = 'files';
  static const String _metaKey = '__meta__';

  web.IDBDatabase? _db;
  bool _primed = false;
  String? _version;
  Map<String, String> _hashes = <String, String>{};
  final Set<String> _overrides = <String>{};
  final Map<String, String> _staged = <String, String>{};
  final Map<String, Uint8List> _readCache = <String, Uint8List>{};

  Future<web.IDBDatabase> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final req = web.window.indexedDB.open(_dbName, 1);
    final done = Completer<web.IDBDatabase>();
    req.onupgradeneeded = ((web.Event e) {
      final db = req.result as web.IDBDatabase;
      // 版本 1 只在首次创建时触发；重复调用会抛，忽略即可。
      try {
        db.createObjectStore(_store);
      } catch (_) {}
    }).toJS;
    req.onsuccess = ((web.Event e) {
      if (!done.isCompleted) done.complete(req.result as web.IDBDatabase);
    }).toJS;
    req.onerror = ((web.Event e) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB open failed: ${req.error}'));
      }
    }).toJS;
    return _db = await done.future;
  }

  Future<String?> _get(String key) async {
    final db = await _open();
    final req = db
        .transaction(_store.toJS, 'readonly')
        .objectStore(_store)
        .get(key.toJS);
    final done = Completer<String?>();
    req.onsuccess = ((web.Event e) {
      final r = req.result;
      if (!done.isCompleted) {
        done.complete(r != null && r.isA<JSString>() ? (r as JSString).toDart : null);
      }
    }).toJS;
    req.onerror = ((web.Event e) {
      if (!done.isCompleted) done.completeError(StateError('IDB get failed'));
    }).toJS;
    return done.future;
  }

  Future<void> _putAll(Map<String, String> items) async {
    if (items.isEmpty) return;
    final db = await _open();
    final tx = db.transaction(_store.toJS, 'readwrite');
    final store = tx.objectStore(_store);
    for (final e in items.entries) {
      store.put(e.value.toJS, e.key.toJS);
    }
    final done = Completer<void>();
    tx.oncomplete = ((web.Event e) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    tx.onerror = ((web.Event e) {
      if (!done.isCompleted) {
        done.completeError(StateError('IDB commit failed: ${tx.error}'));
      }
    }).toJS;
    tx.onabort = ((web.Event e) {
      if (!done.isCompleted) {
        done.completeError(StateError('IDB commit aborted: ${tx.error}'));
      }
    }).toJS;
    await done.future;
  }

  @override
  Future<void> prime() async {
    if (_primed) return;
    try {
      final raw = await _get(_metaKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _version = j['version'] as String?;
        _hashes = (j['hashes'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString()));
        _overrides.addAll((j['overrides'] as List? ?? const [])
            .map((e) => e.toString()));
      }
    } catch (_) {
      _version = null;
      _hashes = <String, String>{};
      _overrides.clear();
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
    final raw = await _get(relPath);
    if (raw == null) return null;
    final bytes = base64Decode(raw);
    _readCache[relPath] = bytes;
    return bytes;
  }

  @override
  Future<void> begin() async {
    await prime();
    _staged.clear();
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    if (path.isEmpty || path.split('/').contains('..')) {
      throw ArgumentError('非法数据路径: $path');
    }
    _staged[path] = base64Encode(bytes);
  }

  @override
  Future<void> commit(String version, Map<String, String> hashes) async {
    final batch = Map<String, String>.from(_staged);
    _overrides.addAll(batch.keys);
    batch[_metaKey] = jsonEncode(<String, dynamic>{
      'version': version,
      'hashes': hashes,
      'overrides': _overrides.toList()..sort(),
    });
    await _putAll(batch);
    _version = version;
    _hashes = Map<String, String>.from(hashes);
    _readCache.clear();
    _staged.clear();
  }

  @override
  Future<void> rollback() async {
    _staged.clear();
  }
}
