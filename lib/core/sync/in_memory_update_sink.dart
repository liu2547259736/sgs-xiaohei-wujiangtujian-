// UpdateSink 的最小可用实现：主要用于单元测试和 Web 端原型。
//
// 生产实现请另写（P1 接入时替换）：
//   native：lib/core/sync/file_update_sink_io.dart
//           appliedHashes 从 drift 表读；begin 建 temp 目录；
//           commit 用 Directory.rename 原子切换 + 写 version；rollback 删 temp。
//   Web   ：lib/core/sync/web_update_sink.dart
//           appliedHashes 从 shared_preferences 读；write 存 IndexedDB；
//           图片交给浏览器 HTTP 缓存，不进本地库。
//
// 这个文件不引 dart:io，六端都能编译。
import 'dart:typed_data';

import 'update_protocol.dart';

class InMemoryUpdateSink implements UpdateSink {
  String? _version;
  final Map<String, String> _hashes = <String, String>{};
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Map<String, Uint8List> _pending = <String, Uint8List>{};

  /// 测试用：查看当前已提交的文件内容。
  Map<String, Uint8List> get files => Map<String, Uint8List>.unmodifiable(_files);

  @override
  Future<String?> appliedVersion() async => _version;

  @override
  Future<Map<String, String>> appliedHashes() async =>
      Map<String, String>.unmodifiable(_hashes);

  @override
  Future<void> begin() async => _pending.clear();

  @override
  Future<void> write(String path, Uint8List bytes) async =>
      _pending[path] = bytes;

  @override
  Future<void> commit(String version, Map<String, String> hashes) async {
    _files.addAll(_pending);
    _hashes
      ..clear()
      ..addAll(hashes);
    _version = version;
    _pending.clear();
  }

  @override
  Future<void> rollback() async => _pending.clear();
}
