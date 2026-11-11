// 更新覆盖层：让业务代码「优先读已下载的数据，回落随包 seed」。
//
// 只落盘还不够 —— 如果 HeroRepository 仍然只读 rootBundle，下载完的文件
// 永远不会生效。这里定义统一的读取契约，native / Web 各给一份实现。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../seed_asset.dart';

abstract class DataFileSource {
  /// 同步判断某个 data-repo 相对路径是否存在已落盘的更新版本。
  /// 必须是同步的：图鉴一屏几百张卡片，不能每张都做一次异步 IO 探测。
  bool hasOverride(String relPath);

  /// 读回覆盖内容；不存在时返回 null，调用方自动回落 asset。
  Future<Uint8List?> readOverride(String relPath);

  /// 启动时把元数据（version / hashes / 覆盖文件清单）载入内存。可重复调用。
  Future<void> prime() async {}
}

/// 纯随包模式：单元测试、以及未接入更新时的默认实现。
class BundleOnlySource implements DataFileSource {
  const BundleOnlySource();

  @override
  bool hasOverride(String relPath) => false;

  @override
  Future<Uint8List?> readOverride(String relPath) async => null;

  @override
  Future<void> prime() async {}
}

/// 统一读字节：覆盖优先，回落 asset bundle。
Future<Uint8List> readDataBytes(DataFileSource source, String relPath) async {
  if (source.hasOverride(relPath)) {
    final bytes = await source.readOverride(relPath);
    if (bytes != null) return bytes;
  }
  final data = await rootBundle.load(SeedAsset.of(relPath));
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 统一读文本，供所有 JSON 分片使用。
Future<String> readDataString(DataFileSource source, String relPath) async =>
    utf8.decode(await readDataBytes(source, relPath), allowMalformed: true);
