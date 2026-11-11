// 集成测试：让 Repository 真读随包 seed，验证数据契约端到端可用。
// 这里不 mock 任何 JSON —— 目的就是尽早发现「分片格式 / 路径 / 字段」对不上。
import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/data/hero_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HeroRepository repo;

  setUpAll(() async {
    repo = HeroRepository();
    await repo.load();
  });

  test('随包 seed 能加载 6 版本 / 全量武将 / 分片详情', () async {
    final data = repo.data;

    expect(data.version, isNotEmpty);
    expect(data.versions.length, 6);
    // 不写死总数：主程序每次加将后重新同步 seed，这里只保证索引与条目一致，
    // 且不少于当前基线 3745，避免数据回退时测试仍然通过。
    expect(data.heroes.length, data.heroCount);
    expect(data.heroCount, greaterThanOrEqualTo(3745));
    expect(data.shardsByVersion.length, 6);
    expect(data.shardsByVersion['sgsol']?.length, 2);

    final ol = await repo.loadDetails('sgsol');
    expect(ol.length, 701);
    final guanyu = ol['std_guanyu'];
    expect(guanyu, isNotNull);
    expect(guanyu!.skills.first.name, '武圣');
    expect(guanyu.quotes['阵亡'], isNotEmpty);
    expect(guanyu.skins, isNotEmpty);
    expect(guanyu.hpText, '4');
  });

  test('筛选、中文搜索、拼音缩写搜索都命中关羽', () {
    final base = repo.query(version: 'sgsol');
    expect(base.length, 701);

    final byName = repo.query(version: 'sgsol', text: '关羽');
    expect(byName.any((h) => h.id == 'std_guanyu'), isTrue);

    final byPy = repo.query(version: 'sgsol', text: 'gy');
    expect(byPy.any((h) => h.id == 'std_guanyu'), isTrue);

    final bySkill = repo.query(version: 'sgsol', text: '武圣');
    expect(bySkill.any((h) => h.id == 'std_guanyu'), isTrue);

    final shu = repo.query(version: 'sgsol', kingdom: 'shu');
    expect(shu.every((h) => h.kingdom == 'shu'), isTrue);
    expect(shu.length, lessThan(base.length));

    final std = repo.query(version: 'sgsol', pack: 'std');
    expect(std.every((h) => h.pack == 'std'), isTrue);

    expect(repo.query(version: 'sgsol', text: '绝不存在的武将'), isEmpty);
    expect(repo.query(version: 'other').isEmpty, isTrue);
  });
}
