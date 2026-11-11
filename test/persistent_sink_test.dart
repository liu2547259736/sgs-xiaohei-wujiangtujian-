// 生产 UpdateSink（native 文件实现）的真实落盘事务测试。
// 注入临时目录，不依赖 path_provider 平台通道，跑的是真的 File IO。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/core/sync/update_sink_io.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sgs_sink_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  FileUpdateSink make() =>
      FileUpdateSink(rootProvider: () async => tmp);

  test('commit 后版本/hash/文件都落盘，换实例模拟重启仍可读回', () async {
    final sink = make();
    expect(await sink.appliedVersion(), isNull);

    await sink.begin();
    await sink.write('heroes/x.json',
        Uint8List.fromList(utf8.encode('{"generals":[]}')));
    await sink.commit('2026.11.11', <String, String>{
      'heroes/x.json': 'abc123',
    });

    expect(await sink.appliedVersion(), '2026.11.11');
    expect((await sink.appliedHashes())['heroes/x.json'], 'abc123');
    expect(sink.hasOverride('heroes/x.json'), isTrue);
    expect(utf8.decode((await sink.readOverride('heroes/x.json'))!),
        '{"generals":[]}');

    final reopened = make();
    await reopened.prime();
    expect(await reopened.appliedVersion(), '2026.11.11');
    expect(reopened.hasOverride('heroes/x.json'), isTrue);
    expect(utf8.decode((await reopened.readOverride('heroes/x.json'))!),
        '{"generals":[]}');
  });

  test('rollback 不推进版本，也不在正式目录留下半截文件', () async {
    final sink = make();
    await sink.begin();
    await sink.write('heroes/a.json', Uint8List.fromList(<int>[1, 2, 3]));
    await sink.rollback();

    expect(sink.hasOverride('heroes/a.json'), isFalse);
    expect(await sink.appliedVersion(), isNull);
    expect(
      File('${tmp.path}${Platform.pathSeparator}sgs_data'
              '${Platform.pathSeparator}heroes${Platform.pathSeparator}a.json')
          .existsSync(),
      isFalse,
    );
  });

  test('路径穿越被拒绝', () async {
    final sink = make();
    await sink.begin();
    await expectLater(
      sink.write('../evil.json', Uint8List(0)),
      throwsArgumentError,
    );
  });

  test('只登记 seed 基线（空 staging）也能安全 commit', () async {
    final sink = make();
    await sink.begin();
    await sink.commit('seed-v1', <String, String>{'a': 'h'});
    expect(await sink.appliedVersion(), 'seed-v1');
    expect(sink.hasOverride('a'), isFalse);
  });
}
