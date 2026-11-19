// 随包原页面资源的只读访问。
//
// 刻意不解压到磁盘：assets 里的文件可以通过 rootBundle 按需读取，
// 省掉首次启动复制 438MB 的等待，也不占双份空间。
//
// 加了一层按字节封顶的 LRU 内存缓存：一次滚动会连续请求几百张立绘，
// 每张都走一遍 rootBundle.load（读 APK 条目 + 可能解压）在低端机上就是掉帧。
// 缓存只放小文件，单张超限的大图不进缓存，避免一张 5MB 的图挤掉几十张头像。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'shell_config.dart';

class ShellAssets {
  ShellAssets._(this._known, this.version, this._memory);

  final Set<String> _known;
  final String version;

  /// 测试用的内存资源；生产环境为 null，走 rootBundle。
  final Map<String, Uint8List>? _memory;

  /// LRU：Dart 的 Map 保持插入顺序，命中时先 remove 再放回即可把最近使用的
  /// 排到队尾，淘汰永远从 keys.first 开始。
  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  int _cacheBytes = 0;

  /// 缓存总上限。头像 / 立绘 webp 多在 10~80 KB，40 MB 够放一千多张，
  /// 在 2 GB 内存的低端机上也不会挤掉 WebView 自己的图像缓存。
  static const int cacheLimit = 40 * 1024 * 1024;

  /// 单张上限：超过这个大小的文件不进内存缓存，只透传一次。
  static const int cacheMaxItem = 2 * 1024 * 1024;

  /// 给测试与诊断用。
  int get cacheBytes => _cacheBytes;
  int get cacheCount => _cache.length;


  /// 给单元测试造一份最小随包页面，不依赖真实 asset bundle。
  factory ShellAssets.fake(Map<String, Uint8List> files,
          {String version = 'test'}) =>
      ShellAssets._(files.keys.toSet(), version, files);

  static Future<ShellAssets> load() async {
    final meta = jsonDecode(await rootBundle.loadString(kShellMeta))
        as Map<String, dynamic>;
    final raw = await rootBundle.loadString(kShellFileList);
    final known = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return ShellAssets._(known, (meta['version'] ?? '0').toString(), null);
  }

  bool has(String relPath) => _known.contains(relPath);

  /// 不存在时返回 null，交给 server 回 404；不抛异常。
  Future<ByteData?> read(String relPath) async {
    if (!has(relPath)) return null;
    // 缓存对内存替身同样生效 —— 真实环境与测试走同一条路径，行为才一致。
    final hit = _cache.remove(relPath);
    if (hit != null) {
      _cache[relPath] = hit; // 放回队尾 = 标记为最近使用
      return ByteData.sublistView(hit);
    }
    final memory = _memory;
    if (memory != null) {
      final bytes = memory[relPath];
      if (bytes == null) return null;
      _remember(relPath, bytes);
      return ByteData.sublistView(bytes);
    }
    try {
      final data = await rootBundle.load(kShellAssetPrefix + relPath);
      // 存一份 Uint8List 视图（与 data 共用同一块内存，不额外拷贝）。
      _remember(
        relPath,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return data;
    } catch (_) {
      return null;
    }
  }

  void _remember(String relPath, Uint8List bytes) {
    if (bytes.length > cacheMaxItem) return;
    // 同一路径重复放入时先扣掉旧占位。
    final old = _cache.remove(relPath);
    if (old != null) _cacheBytes -= old.length;
    _cache[relPath] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > cacheLimit && _cache.length > 1) {
      final oldest = _cache.keys.first;
      final dropped = _cache.remove(oldest);
      if (dropped == null) break;
      _cacheBytes -= dropped.length;
    }
  }
}
