// 用假 CDN 验证 GitUpdateService 的三条关键路径：
// 首次 seed 基线不重下、增量只下变化文件、校验失败回滚且版本不推进。
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sgs_heroes/core/sync/git_update_service.dart';
import 'package:sgs_heroes/core/sync/in_memory_update_sink.dart';
import 'package:sgs_heroes/core/sync/update_protocol.dart';

const _base = 'https://cdn.example.com/sgs-data@data-v1';
const _heroPath = 'heroes/sgsol-001.json';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Map<String, dynamic> _manifest(String version, Map<String, Uint8List> files) => {
      'schema': 1,
      'version': version,
      'updated_at': '2026-11-10T00:00:00+08:00',
      'counts': {'heroes': files.length},
      'files': [
        for (final e in files.entries)
          {
            'path': e.key,
            'sha256': sha256.convert(e.value).toString(),
            'bytes': e.value.length,
          }
      ],
    };

void main() {
  test('首次登记 seed 基线后，只下载 hash 变化的文件并推进版本', () async {
    final seedFile = _bytes('old');
    final newFile = _bytes('new content');
    final fileRequests = <String>[];

    final client = MockClient((req) async {
      if (req.url.path.endsWith('manifest.json')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(_manifest('2026.11.11', {_heroPath: newFile}))),
          200,
        );
      }
      if (req.url.path.endsWith(_heroPath)) {
        fileRequests.add(req.url.path);
        return http.Response.bytes(newFile, 200);
      }
      return http.Response('missing', 404);
    });

    final sink = InMemoryUpdateSink();
    final seed = DataManifest.fromJson(
        _manifest('2026.11.10', {_heroPath: seedFile}));
    final service =
        GitUpdateService(baseUrls: const [_base], sink: sink, client: client);

    final result = await service.checkAndApply(seed: seed);

    expect(result.status, UpdateStatus.updated);
    expect(result.version, '2026.11.11');
    expect(result.changedPaths, [_heroPath]);
    expect(fileRequests.length, 1, reason: 'seed 已登记 hash，不该重下全量');
    expect(utf8.decode(sink.files[_heroPath]!), 'new content');
    expect(await sink.appliedVersion(), '2026.11.11');
  });

  test('版本相同直接 upToDate，不请求任何数据文件', () async {
    final data = _bytes('same');
    var fileRequests = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('manifest.json')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(_manifest('2026.11.10', {_heroPath: data}))),
          200,
        );
      }
      fileRequests++;
      return http.Response('unused', 200);
    });

    final sink = InMemoryUpdateSink();
    final seed = DataManifest.fromJson(
        _manifest('2026.11.10', {_heroPath: data}));
    final service =
        GitUpdateService(baseUrls: const [_base], sink: sink, client: client);

    final result = await service.checkAndApply(seed: seed);

    expect(result.status, UpdateStatus.upToDate);
    expect(fileRequests, 0);
  });

  test('文件 sha256 对不上时回滚，版本与已存数据都不变', () async {
    final seedFile = _bytes('old');
    final client = MockClient((req) async {
      if (req.url.path.endsWith('manifest.json')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(
              _manifest('2026.11.11', {_heroPath: _bytes('expected')}))),
          200,
        );
      }
      if (req.url.path.endsWith(_heroPath)) {
        return http.Response.bytes(_bytes('tampered'), 200);
      }
      return http.Response('missing', 404);
    });

    final sink = InMemoryUpdateSink();
    final seed = DataManifest.fromJson(
        _manifest('2026.11.10', {_heroPath: seedFile}));
    final service =
        GitUpdateService(baseUrls: const [_base], sink: sink, client: client);

    final result = await service.checkAndApply(seed: seed);

    expect(result.status, UpdateStatus.downloadFailed);
    expect(await sink.appliedVersion(), '2026.11.10',
        reason: '失败不能推进 version，否则下次会跳过这次更新');
    expect(sink.files.isEmpty, true, reason: '回滚后不应留下半新半旧的数据');
  });

  test('dryRun 只报告待更新文件数，不下载', () async {
    final seedFile = _bytes('old');
    var fileRequests = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('manifest.json')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(
              _manifest('2026.11.11', {_heroPath: _bytes('new')}))),
          200,
        );
      }
      fileRequests++;
      return http.Response('unused', 200);
    });

    final sink = InMemoryUpdateSink();
    final seed = DataManifest.fromJson(
        _manifest('2026.11.10', {_heroPath: seedFile}));
    final service =
        GitUpdateService(baseUrls: const [_base], sink: sink, client: client);

    final result = await service.checkAndApply(seed: seed, dryRun: true);

    expect(result.status, UpdateStatus.updateAvailable);
    expect(result.pendingCount, 1);
    expect(fileRequests, 0);
    expect(await sink.appliedVersion(), '2026.11.10');
  });
}
