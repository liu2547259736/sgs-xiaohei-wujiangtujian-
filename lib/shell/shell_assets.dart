// 随包原页面资源的只读访问。
//
// 刻意不解压到磁盘：assets 里的文件可以通过 rootBundle 按需读取，
// 省掉首次启动复制 438MB 的等待，也不占双份空间。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'shell_config.dart';

class ShellAssets {
  ShellAssets._(this._known, this.version);

  final Set<String> _known;
  final String version;

  static Future<ShellAssets> load() async {
    final meta = jsonDecode(await rootBundle.loadString(kShellMeta))
        as Map<String, dynamic>;
    final raw = await rootBundle.loadString(kShellFileList);
    final known = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return ShellAssets._(known, (meta['version'] ?? '0').toString());
  }

  bool has(String relPath) => _known.contains(relPath);

  /// 不存在时返回 null，交给 server 回 404；不抛异常。
  Future<ByteData?> read(String relPath) async {
    if (!has(relPath)) return null;
    try {
      return await rootBundle.load(kShellAssetPrefix + relPath);
    } catch (_) {
      return null;
    }
  }
}
