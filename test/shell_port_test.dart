// 本地 server 的端口必须固定。
//
// 原页面的账号（services/localAuth.js）、收藏、历史、主题都落在 localStorage，
// 而 localStorage 以 origin（scheme://host:port）为键。之前用 bind(..., 0)
// 每次启动换随机端口，等于每次都是新站点 —— 注册完重启就找不到账号。
// 这里锁住「首选端口固定 + 只在被占用时顺延」。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/core/env.dart';
import 'package:sgs_heroes/shell/shell_assets.dart';
import 'package:sgs_heroes/shell/shell_server.dart';

ShellAssets _assets() => ShellAssets.fake(<String, Uint8List>{});

/// 借系统随机分配拿一个当前空闲端口，随后立刻释放。
Future<int> _freePort() async {
  final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close(force: true);
  return port;
}

void main() {
  test('Env.shellPort 是高位固定端口', () {
    expect(Env.shellPort, greaterThan(1024));
    expect(Env.shellPort, lessThan(65535));
  });

  test('start() 绑定首选端口，不再每次随机', () async {
    final preferred = await _freePort();
    final server = ShellServer(assets: _assets(), preferredPort: preferred);
    addTearDown(server.stop);

    expect(await server.start(), preferred);
  });

  test('首选端口被占用时顺延，不静默退回随机端口', () async {
    final preferred = await _freePort();
    final blocker =
        await HttpServer.bind(InternetAddress.loopbackIPv4, preferred);
    addTearDown(() => blocker.close(force: true));

    final server = ShellServer(assets: _assets(), preferredPort: preferred);
    addTearDown(server.stop);

    final port = await server.start();
    expect(port, isNot(preferred));
    expect(port, inInclusiveRange(preferred + 1, preferred + 8));
  });

  test('同一首选端口两次启动得到同一端口（origin 稳定）', () async {
    final preferred = await _freePort();
    final first = ShellServer(assets: _assets(), preferredPort: preferred);
    final p1 = await first.start();
    await first.stop();

    final second = ShellServer(assets: _assets(), preferredPort: preferred);
    final p2 = await second.start();
    addTearDown(second.stop);

    expect(p1, preferred);
    expect(p2, preferred);
  });
}
