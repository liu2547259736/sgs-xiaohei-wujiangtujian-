// 本地账号服务：与主程序 localAuth.js 的摘要格式 / 备份格式互通测试。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sgs_heroes/features/account/local_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<LocalAuthService> fresh() async {
    final s = LocalAuthService();
    await s.init();
    return s;
  }

  test('注册 → 登录 → 会话持久化（模拟重启）', () async {
    final a = await fresh();
    final r = await a.register('zhangliao', 'abc123', nickname: '张文远');
    expect(r.ok, isTrue);
    expect(a.currentUser!.displayName, '张文远');
    expect((await a.register('zhangliao', 'xxxx')).ok, isFalse);

    await a.logout();
    expect(a.currentUser, isNull);
    expect((await a.login('zhangliao', 'wrong')).ok, isFalse);
    expect((await a.login('ZHANGLIAO', 'abc123')).ok, isTrue,
        reason: '用户名大小写不敏感，与主程序一致');

    final b = await fresh();
    expect(b.users.length, 1);
    // 主程序把会话存在 sgs_current_session，刷新后保持登录；本端行为一致。
    expect(b.currentUser, isNotNull, reason: '会话持久化，重启后仍保持登录');
    expect(b.currentUser!.username, 'zhangliao');
    expect((await b.login('zhangliao', 'wrong')).ok, isFalse,
        reason: '重启后密码校验依然生效');
  });

  test('密码摘要复刻主程序 salted FNV-1a，可直接验证主程序的备份', () {
    expect(LocalAuthService.verify('test', 'l1s:abc123:7218e6b5'), isTrue);
    expect(LocalAuthService.verify('hunter2', 'l1s:x9k2mz:0f293698'), isTrue);
    expect(LocalAuthService.verify('wrong', 'l1s:abc123:7218e6b5'), isFalse);
    expect(LocalAuthService.verify('test', 'plaintext'), isFalse);

    final h = LocalAuthService.hash('abc123');
    expect(h.startsWith('l1s:'), isTrue);
    expect(h.split(':').length, 3);
    expect(LocalAuthService.verify('abc123', h), isTrue);
    expect(h.contains('abc123'), isFalse, reason: '密码不明文落盘');
  });

  test('scopeKey 按账号隔离，切换账号后收藏不串号', () async {
    final a = await fresh();
    await a.register('userA', 'passA');
    await a.saveList('sgs_favorites', <String>['a1', 'a2']);
    expect(a.scopeKey('sgs_favorites'), contains('@'));

    await a.register('userB', 'passB');
    expect(a.loadList('sgs_favorites'), isEmpty);
    await a.saveList('sgs_favorites', <String>['b1']);

    await a.selectUser(a.users.first.id);
    expect(a.loadList('sgs_favorites'), <String>['a1', 'a2']);
    await a.selectUser(a.users.last.id);
    expect(a.loadList('sgs_favorites'), <String>['b1']);

    await a.logout();
    expect(a.loadList('sgs_favorites'), isEmpty, reason: '游客态用原键');
  });

  test('导出备份可被重新导入，账号与收藏都保留', () async {
    final a = await fresh();
    await a.register('caocao', 'pass1', nickname: '孟德');
    await a.saveList('sgs_favorites', <String>['sgsol/std_caocao']);
    final text = a.exportData();
    final doc = jsonDecode(text) as Map<String, dynamic>;
    expect(doc['app'], 'sgs-heroes');
    expect(doc['type'], 'local-auth-backup');
    expect((doc['users'] as List).length, 1);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final b = await fresh();
    final r = await b.importData(text);
    expect(r.ok, isTrue);
    expect(r.added, 1);
    expect((await b.login('caocao', 'pass1')).ok, isTrue);
    expect(b.loadList('sgs_favorites'), <String>['sgsol/std_caocao']);
  });

  test('能直接导入主程序格式的备份（含 l1s 摘要与 userData）', () async {
    final backup = jsonEncode(<String, dynamic>{
      'app': 'sgs-heroes',
      'type': 'local-auth-backup',
      'version': 1,
      'users': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'legacy_user_1',
          'username': 'legacy',
          // 主程序 hash('test') 的值，salt = abc123
          'password': 'l1s:abc123:7218e6b5',
          'nickname': '老账号',
          'createdAt': '2026-09-24 10:00:00',
          'updatedAt': '2026-09-24 10:00:00',
          'userData': <String, dynamic>{
            'favorites': <String>['sgsol/std_guanyu'],
            'history': <String>[],
            'notes': <String, dynamic>{},
            'settings': <String, dynamic>{},
          },
        }
      ],
    });

    final a = await fresh();
    final r = await a.importData(backup);
    expect(r.ok, isTrue);
    expect((await a.login('legacy', 'test')).ok, isTrue,
        reason: '主程序导出的摘要必须能在本端登录');
    expect(a.loadList('sgs_favorites'), <String>['sgsol/std_guanyu']);
  });
}
