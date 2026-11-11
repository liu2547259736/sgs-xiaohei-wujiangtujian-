// 生产 UpdateSink 的平台入口。
//
// 条件导出：native 编译选 update_sink_io.dart（dart:io + path_provider），
// Web 编译选 update_sink_web.dart（IndexedDB）。业务层只 import 本文件，
// 拿到的永远是同名的 PersistentUpdateSink / createPersistentSink()，
// 不需要在任何地方写 if (kIsWeb)。
//
// 用法：
//   final sink = createPersistentSink();
//   await sink.prime();                       // 启动时载入元数据
//   final service = GitUpdateService(baseUrls: ..., sink: sink);
//   await service.checkAndApply(seed: data.seed);   // 注意：不再传 dryRun
export 'update_sink_io.dart'
    if (dart.library.js_interop) 'update_sink_web.dart';
