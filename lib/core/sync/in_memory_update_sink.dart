// UpdateSink 的内存实现：单元测试专用，不持久化。
//
// 生产实现见 persistent_update_sink.dart 的条件导出：
//   native：update_sink_io.dart，落 ApplicationSupportDirectory/sgs_data/
//   Web   ：update_sink_web.dart，落 IndexedDB
// 两者同时实现 DataFileSource，下载完的文件会直接被 Repository 读到。
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
