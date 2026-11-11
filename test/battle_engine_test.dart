// 2v2 龙虎斗纯 Dart 引擎单元测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/features/battle/battle_engine.dart';
import 'package:sgs_heroes/features/battle/battle_models.dart';

/// 测试用假牌：只关心规则键与花色，不进真实牌堆。
Card _card(String name, {String? label, String suit = '♠'}) => Card(
      uid: 'test_$name',
      name: name,
      label: label ?? name,
      suit: suit,
      point: 1,
      kind: CardKind.basic,
    );

List<BattleHero> _heroes() => <BattleHero>[
      BattleHero(name: '刘备', kingdom: 'shu', hp: 4, skills: <String>['仁德']),
      BattleHero(name: '曹操', kingdom: 'wei', hp: 4, skills: <String>['奸雄']),
      BattleHero(name: '关羽', kingdom: 'shu', hp: 4, skills: <String>['武圣']),
      BattleHero(name: '张飞', kingdom: 'shu', hp: 4, skills: <String>['咆哮']),
    ];

void main() {
  test('buildDeck 展开恰好 160 张军争牌', () {
    final deck = buildDeck();
    expect(deck.length, kDeckSize);
    expect(deck.length, 160);
    // 校验 uid 唯一、花色点数齐全。
    expect(deck.map((c) => c.uid).toSet().length, 160);
    expect(deck.where((c) => c.name == 'sha').length, greaterThan(0));
    expect(deck.where((c) => c.isEquip).length, 25); // 12 武器 + 6 防具 + 7 马
    expect(deck.where((c) => c.suit == '♥').length, greaterThan(0));
  });

  test('同一 seed 洗牌可复现', () {
    final heroes = _heroes();
    final e1 = BattleEngine(seed: 20261111);
    final e2 = BattleEngine(seed: 20261111);
    e1.newGame(heroes);
    e2.newGame(heroes);
    expect(
      e1.state.deck.map((c) => c.uid).toList(),
      e2.state.deck.map((c) => c.uid).toList(),
    );
    expect(
      e1.state.me.hand.map((c) => c.uid).toList(),
      e2.state.me.hand.map((c) => c.uid).toList(),
    );
  });

  test('杀被闪抵消不掉血', () {
    final e = BattleEngine(seed: 1)..newGame(_heroes());
    final me = e.state.me;
    final enemy = e.state.players[1];
    enemy.hand
      ..clear()
      ..add(_card('shan', label: '闪', suit: '♦'));

    final sha = _card('sha', label: '杀');
    me.hand.add(sha);
    e.playCard(me, sha, <Player>[enemy]);

    expect(enemy.hp, enemy.maxHp);
    expect(e.logs.any((l) => l.text.contains('抵消了')), isTrue);
  });

  test('无闪时杀造成 1 点伤害', () {
    final e = BattleEngine(seed: 2)..newGame(_heroes());
    final me = e.state.me;
    final enemy = e.state.players[1];
    enemy.hand.clear();

    final sha = _card('sha', label: '杀');
    me.hand.add(sha);
    e.playCard(me, sha, <Player>[enemy]);

    expect(enemy.hp, enemy.maxHp - 1);
  });

  test('桃回血、酒强化杀伤害 +1', () {
    // 桃：受伤后吃桃回满。
    final e1 = BattleEngine(seed: 3)..newGame(_heroes());
    final me1 = e1.state.me;
    me1.hp = me1.maxHp - 1;
    final tao = _card('tao', label: '桃', suit: '♥');
    me1.hand.add(tao);
    e1.playCard(me1, tao, const <Player>[]);
    expect(me1.hp, me1.maxHp);

    // 酒：喝酒后下一张杀造成 2 点伤害。
    final e2 = BattleEngine(seed: 4)..newGame(_heroes());
    final me2 = e2.state.me;
    final enemy2 = e2.state.players[1];
    enemy2.hand.clear();
    final jiu = _card('jiu', label: '酒');
    final sha = _card('sha', label: '杀');
    me2.hand.addAll(<Card>[jiu, sha]);
    e2.playCard(me2, jiu, const <Player>[]);
    e2.playCard(me2, sha, <Player>[enemy2]);
    expect(enemy2.hp, enemy2.maxHp - 2);
  });

  test('一方全灭判定胜负（龙方胜）', () {
    final e = BattleEngine(seed: 5)..newGame(_heroes());
    final me = e.state.me;
    // 清空所有人手牌，避免濒死求桃把虎方救回，确保纯胜负判定可复现。
    for (final p in e.state.players) {
      p.hand.clear();
    }
    for (final idx in const <int>[1, 3]) {
      final enemy = e.state.players[idx];
      enemy.hand.clear();
      enemy.hp = 1;
      final sha = _card('sha', label: '杀');
      me.hand.add(sha);
      e.playCard(me, sha, <Player>[enemy]);
    }
    expect(e.state.over, isTrue);
    expect(e.state.winner, BattleTeam.dragon);
    expect(e.logs.any((l) => l.text.contains('龙方胜')), isTrue);
  });

  test('白名单 27 人且至少 8 个技能有实现标记', () {
    expect(kHeroImpl.length, 27);
    expect(kImplementedSkills.length, greaterThanOrEqualTo(8));
    // 每个已实装技能都有说明文本且标注「已实装」。
    for (final s in kImplementedSkills) {
      expect(kSkillDescriptions.containsKey(s), isTrue, reason: '$s 缺说明');
      expect(skillDescription(s).contains('已实装'), isTrue);
    }
    // 白名单武将能拿到已实装技能；非白名单拿不到。
    expect(
      implementedSkillsOf(
          BattleHero(name: '张飞', skills: <String>['咆哮'])),
      <String>['咆哮'],
    );
    expect(
      implementedSkillsOf(
          BattleHero(name: '某某', skills: <String>['咆哮'])),
      isEmpty,
    );
    expect(isWhitelistedHero('诸葛亮'), isTrue);
    expect(isSkillImplemented('空城'), isTrue);
    expect(isSkillImplemented('铁骑'), isFalse);
  });

  test('无双：杀需两张闪才能抵消', () {
    final heroes = <BattleHero>[
      BattleHero(name: '吕布', kingdom: 'qun', hp: 4, skills: <String>['无双']),
      BattleHero(name: '曹操', kingdom: 'wei', hp: 4),
      BattleHero(name: '关羽', kingdom: 'shu', hp: 4),
      BattleHero(name: '张飞', kingdom: 'shu', hp: 4),
    ];
    final e = BattleEngine(seed: 6)..newGame(heroes);
    final me = e.state.me;
    final enemy = e.state.players[1];
    expect(me.implSkills, contains('无双'));

    // 只有一张闪 -> 无法抵消，掉血。
    enemy.hand
      ..clear()
      ..add(_card('shan', label: '闪', suit: '♦'));
    final sha1 = _card('sha', label: '杀');
    me.hand.add(sha1);
    e.playCard(me, sha1, <Player>[enemy]);
    expect(enemy.hp, enemy.maxHp - 1);

    // 有两张闪 -> 抵消，不掉血。
    enemy.hp = enemy.maxHp;
    enemy.hand
      ..clear()
      ..add(_card('shan', label: '闪', suit: '♦'))
      ..add(_card('shan', label: '闪', suit: '♥'));
    final sha2 = _card('sha', label: '杀');
    me.hand.add(sha2);
    e.playCard(me, sha2, <Player>[enemy]);
    expect(enemy.hp, enemy.maxHp);
  });
}
