// 随包原页面资源的只读访问。
//
// 刻意不解压到磁盘：assets 里的文件可以通过 rootBundle 按需读取，
// 省掉首次启动复制 438MB 的等待，也不占双份空间。
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
    final memory = _memory;
    if (memory != null) {
      final bytes = memory[relPath];
      return bytes == null ? null : ByteData.sublistView(bytes);
    }
    try {
      return await rootBundle.load(kShellAssetPrefix + relPath);
    } catch (_) {
      return null;
    }
  }
}
