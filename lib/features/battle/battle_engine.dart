// 2v2 龙虎斗 · 纯 Dart 战斗引擎。
// 不引 dart:io、不引 Flutter，便于单测。迁移自主程序 battle.js 的核心规则。
import 'dart:math';

import 'battle_models.dart';
import 'deck_data.dart';

/// 军争牌堆固定张数。
const int kDeckSize = 160;

// ---------------------------------------------------------------------------
// 27 位经典武将技能白名单（沿用主程序 HERO_IMPL，顺序即选将排序口径）
// ---------------------------------------------------------------------------
const Map<String, List<String>> kHeroImpl = <String, List<String>>{
  '张飞': <String>['咆哮'],
  '关羽': <String>['武圣'],
  '赵云': <String>['龙胆'],
  '马超': <String>['铁骑'],
  '甘宁': <String>['奇袭'],
  '吕蒙': <String>['克己'],
  '黄忠': <String>['烈弓'],
  '周瑜': <String>['英姿'],
  '陆逊': <String>['谦逊', '连营'],
  '孙权': <String>['制衡'],
  '孙尚香': <String>['枭姬'],
  '大乔': <String>['国色', '流离'],
  '吕布': <String>['无双'],
  '貂蝉': <String>['离间', '闭月'],
  '华佗': <String>['急救', '青囊'],
  '曹操': <String>['奸雄'],
  '司马懿': <String>['反馈', '鬼才'],
  '夏侯惇': <String>['刚烈'],
  '张辽': <String>['突袭'],
  '许褚': <String>['裸衣'],
  '郭嘉': <String>['天妒', '遗计'],
  '甄姬': <String>['洛神', '倾国'],
  '刘备': <String>['仁德'],
  '诸葛亮': <String>['空城'],
  '黄盖': <String>['苦肉'],
  '曹仁': <String>['据守'],
  '孟获': <String>['巨象'],
};

/// 白名单武将名单（选将排序用）。
List<String> get kAllyNames => kHeroImpl.keys.toList(growable: false);

/// 真实实现并生效的 8 个技能。其余技能一律「未实装」，引擎不会触发。
const Set<String> kImplementedSkills = <String>{
  '咆哮', // 出杀无次数限制
  '武圣', // 红色牌当【杀】
  '龙胆', // 【杀】【闪】互换
  '英姿', // 摸 3 张、本回合手牌上限 -1
  '空城', // 无手牌时不能成为【杀】/【决斗】目标
  '无双', // 【杀】需两张【闪】，决斗需两张【杀】
  '奸雄', // 受到伤害后获得造成伤害的牌
  '仁德', // 给队友 2 张牌并回复 1 点体力
};

/// 27 位武将全部技能的中文说明文本（含未实装技能）。
const Map<String, String> kSkillDescriptions = <String, String>{
  '咆哮': '出牌阶段使用【杀】没有次数限制。（已实装）',
  '武圣': '可以将一张红色牌当【杀】使用或打出。（已实装）',
  '龙胆': '可以将【杀】当【闪】、【闪】当【杀】使用或打出。（已实装）',
  '英姿': '摸牌阶段多摸一张（摸 3 张），本回合手牌上限 -1。（已实装）',
  '空城': '无手牌时不能成为【杀】或【决斗】的目标。（已实装）',
  '无双': '使用【杀】时目标需两张【闪】；决斗中对方需两张【杀】。（已实装）',
  '奸雄': '受到伤害后获得造成伤害的牌。（已实装）',
  '仁德': '出牌阶段将 2 张手牌交给队友并回复 1 点体力。（已实装）',
  '铁骑': '使用【杀】可判定，非红桃则目标不可闪避。（未实装）',
  '奇袭': '可以将黑色牌当【过河拆桥】使用。（未实装）',
  '克己': '本回合未使用【杀】则跳过弃牌阶段。（未实装）',
  '烈弓': '满足条件时【杀】必中。（未实装）',
  '谦逊': '不能成为【顺手牵羊】和【乐不思蜀】的目标。（未实装）',
  '连营': '失去最后手牌时摸一张。（未实装）',
  '制衡': '弃任意手牌并摸等量牌。（未实装）',
  '枭姬': '失去装备时摸两张牌。（未实装）',
  '国色': '可以将方块牌当【乐不思蜀】使用。（未实装）',
  '流离': '成为【杀】目标时可转移给他人。（未实装）',
  '离间': '弃一张牌令两名敌方武将决斗。（未实装）',
  '闭月': '结束阶段摸一张牌。（未实装）',
  '急救': '濒死时可将红色牌当【桃】使用。（未实装）',
  '青囊': '弃一张手牌令一名角色回复 1 点体力。（未实装）',
  '反馈': '受到伤害后获得伤害来源一张牌。（未实装）',
  '鬼才': '可用手牌改判。（未实装）',
  '刚烈': '受到伤害后判定，红色令来源弃牌或受伤。（未实装）',
  '突袭': '摸牌阶段可改为获得两名敌人各一张手牌。（未实装）',
  '裸衣': '摸牌阶段少摸一张，本回合【杀】与决斗伤害 +1。（未实装）',
  '天妒': '获得判定牌。（未实装）',
  '遗计': '受到伤害后摸两张牌。（未实装）',
  '洛神': '回合开始可反复判定，黑色则获得判定牌。（未实装）',
  '倾国': '可将黑色装备牌当【闪】使用。（未实装）',
  '苦肉': '失去 1 点体力，摸两张牌。（未实装）',
  '据守': '结束阶段翻面并摸一张牌。（未实装）',
  '巨象': '免疫【南蛮入侵】。（未实装）',
};

bool isWhitelistedHero(String name) => kHeroImpl.containsKey(name);

List<String> whitelistSkillsOf(String name) =>
    kHeroImpl[name] ?? const <String>[];

bool isSkillImplemented(String skill) => kImplementedSkills.contains(skill);

String skillDescription(String skill) =>
    kSkillDescriptions[skill] ?? '（该技能暂无说明，未实装）';

/// 武将技能中真实生效的那部分（白名单 ∩ kImplementedSkills）。
List<String> implementedSkillsOf(BattleHero hero) {
  final white = kHeroImpl[hero.name];
  if (white == null) return const <String>[];
  return hero.skills
      .where((s) => white.contains(s) && kImplementedSkills.contains(s))
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// 牌堆
// ---------------------------------------------------------------------------

Card _equipCard(EquipDef e, int i) => Card(
      uid: 'c$i',
      name: e.name,
      label: e.label,
      suit: e.suit,
      point: pointOf(e.point),
      kind: CardKind.equip,
      sub: e.sub,
      slot: e.slot,
      range: e.range,
    );

/// 把 deck_data.dart 的紧凑定义展开成恰好 160 张军争牌，并断言数量。
List<Card> buildDeck() {
  final cards = <Card>[];
  var i = 0;
  for (final d in kDefs) {
    final kind = d.kindCode == 'b' ? CardKind.basic : CardKind.scroll;
    for (final sym in d.points) {
      cards.add(Card(
        uid: 'c${i++}',
        name: d.name,
        label: d.label,
        suit: d.suit,
        point: pointOf(sym),
        kind: kind,
        sub: d.sub,
        element: d.element,
      ));
    }
  }
  for (final e in kWeapons) {
    cards.add(_equipCard(e, i++));
  }
  for (final e in kArmors) {
    cards.add(_equipCard(e, i++));
  }
  for (final e in kHorses) {
    cards.add(_equipCard(e, i++));
  }
  assert(cards.length == kDeckSize, '军争牌堆应为 $kDeckSize 张');
  if (cards.length != kDeckSize) {
    throw StateError('军争牌堆应为 $kDeckSize 张，实际 ${cards.length} 张');
  }
  return cards;
}

// ---------------------------------------------------------------------------
// 响应决策策略：被动响应（闪 / 杀 / 桃 / 无懈）可注入，便于测试复现与替换。
// 默认实现是一套可解释的自动规则，不依赖随机。
// ---------------------------------------------------------------------------
class BattlePolicy {
  const BattlePolicy();

  /// 防守者要打出的【闪】（真实手牌，含龙胆转化）。空列表 = 不闪硬吃。
  List<Card> dodgeCards(BattleEngine e, Player defender, int needed) {
    final cands = e.dodgeCandidates(defender);
    if (cands.length < needed) return const <Card>[];
    return cands.sublist(0, needed);
  }

  /// 响应【杀】（决斗 / 南蛮，含武圣 / 龙胆转化）。空列表 = 不出。
  List<Card> shaCards(BattleEngine e, Player responder, int needed) {
    final cands = e.shaCandidates(responder);
    if (cands.length < needed) return const <Card>[];
    return cands.sublist(0, needed);
  }

  /// 濒死求桃：返回要打出的【桃】真实牌，null = 不救。
  Card? peachCard(BattleEngine e, Player saver, Player dying) {
    for (final c in saver.hand) {
      if (c.name == 'tao') return c;
    }
    return null;
  }

  /// 是否用【无懈可击】。默认只在自己被针对时自救（基础响应，未做完整响应链）。
  bool useWuxie(
          BattleEngine e, Player holder, List<Player> targets, String trick) =>
      targets.contains(holder);
}

// ---------------------------------------------------------------------------
// 引擎
// ---------------------------------------------------------------------------
class BattleEngine {
  BattleEngine({Random? random, int? seed, BattlePolicy? policy})
      : random = random ?? (seed != null ? Random(seed) : Random()),
        policy = policy ?? const BattlePolicy();

  /// 可注入，用于同 seed 洗牌复现。
  final Random random;

  /// 可替换的响应策略。
  BattlePolicy policy;

  late BattleState _state;
  BattleState get state => _state;

  /// 当前正在结算的真实牌（供伤害 / 奸雄取用）。
  Card? _currentCard;
  int _logSeq = 0;

  List<LogEntry> get logs => state.log;

  // ---------------- 日志 ----------------
  void say(String text, [LogKind kind = LogKind.info]) {
    state.log.add(LogEntry(text, kind: kind, seq: _logSeq++));
    if (state.log.length > 300) state.log.removeAt(0);
  }

  void _sayQuote(Player p, String skill) {
    final q = p.hero.quotes[skill];
    if (q == null || q.isEmpty) return;
    final line = q.split(' / ').first.trim();
    if (line.isNotEmpty) say('${p.name}：「$line」', LogKind.quote);
  }

  String _label(Card c) => '【${c.label} $c.corner】';

  // ---------------- 洗牌 / 摸牌 / 弃牌 ----------------
  List<Card> shuffleCards(List<Card> input) {
    final a = List<Card>.from(input);
    for (var i = a.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
    return a;
  }

  Card drawOne() {
    if (state.deck.isEmpty) {
      if (state.pile.isEmpty) {
        throw StateError('牌堆与弃牌堆双空');
      }
      state.deck.addAll(shuffleCards(state.pile));
      state.pile.clear();
      say('🂠 牌堆洗回，重新可用');
    }
    return state.deck.removeLast();
  }

  void draw(Player p, int n) {
    for (var i = 0; i < n; i++) {
      final c = drawOne();
      p.hand.add(c);
      if (p.isHuman) say('你摸到 ${_label(c)}', LogKind.draw);
    }
  }

  void toPile(Iterable<Card> cards) => state.pile.addAll(cards);

  void loseCard(Player p, Card c) {
    p.hand.remove(c);
    toPile(<Card>[c]);
  }

  // ---------------- 距离 / 目标 ----------------
  int _dist(Player a, Player b) {
    final d = (a.index - b.index).abs();
    return d < 4 - d ? d : 4 - d;
  }

  int _distTo(Player a, Player b) {
    var d = _dist(a, b);
    if (a.equips['horseM'] != null) d -= 1;
    if (b.equips['horseP'] != null) d += 1;
    return d < 0 ? 0 : d;
  }

  bool _inRange(Player a, Player b) => _distTo(a, b) <= a.attackRange;

  bool _kongcheng(Player t) => t.hasSkill('空城') && t.hand.isEmpty;

  bool _hasCards(Player t) =>
      t.hand.isNotEmpty ||
      t.judges.isNotEmpty ||
      t.equips.values.any((c) => c != null);

  List<Player> _byHp(List<Player> list) {
    final out = List<Player>.from(list);
    out.sort((a, b) => a.hp.compareTo(b.hp));
    return out;
  }

  /// 某张牌（生效规则键 name）的合法目标，血少优先。
  List<Player> targetable(Player p, String name) {
    final enemies = state.enemiesOf(p);
    switch (name) {
      case 'sha':
        return _byHp(enemies
            .where((t) => _inRange(p, t) && !_kongcheng(t))
            .toList());
      case 'juedou':
        return _byHp(enemies.where((t) => !_kongcheng(t)).toList());
      case 'shunshou':
      case 'guohe':
      case 'lebu':
      case 'bingliang':
        final others = state.players
            .where((t) =>
                t.alive &&
                t != p &&
                _distTo(p, t) <= 1 &&
                _hasCards(t) &&
                !(t.judges.any((c) => c.name == name)))
            .toList();
        others.sort((a, b) {
          final ae = a.team != p.team ? 0 : 1;
          final be = b.team != p.team ? 0 : 1;
          return ae != be ? ae - be : a.hp.compareTo(b.hp);
        });
        return others;
      case 'huogong':
        return _byHp(enemies.where((t) => t.hand.isNotEmpty).toList());
      case 'jiedao':
        return _byHp(
            enemies.where((t) => t.equips['weapon'] != null).toList());
      case 'tieso':
        return state.alivePlayers;
      default:
        return const <Player>[];
    }
  }

  // ---------------- 转化视图 / 可出动作 ----------------
  List<Card> dodgeCandidates(Player p) {
    final out = <Card>[];
    for (final c in p.hand) {
      if (c.name == 'shan') out.add(c);
    }
    if (p.hasSkill('龙胆')) {
      for (final c in p.hand) {
        if (c.name == 'sha') {
          out.add(c);
          break;
        }
      }
    }
    return out;
  }

  List<Card> shaCandidates(Player p) {
    final out = <Card>[];
    void add(Card c) {
      if (!out.contains(c)) out.add(c);
    }

    for (final c in p.hand) {
      if (c.name == 'sha') add(c);
    }
    if (p.hasSkill('武圣')) {
      for (final c in p.hand) {
        if (c.isRed && c.name != 'sha') add(c);
      }
    }
    if (p.hasSkill('龙胆')) {
      for (final c in p.hand) {
        if (c.name == 'shan') add(c);
      }
    }
    return out;
  }

  /// 一张手牌的所有出牌视图（含技能转化），第一个是原生。
  List<CardView> views(Player p, Card c) {
    final list = <CardView>[
      CardView(real: c, name: c.name, label: c.label, element: c.element),
    ];
    // 武圣：红色牌当【杀】
    if (p.hasSkill('武圣') && c.isRed && c.name != 'sha') {
      list.add(CardView(
          real: c, name: 'sha', label: '杀', bySkill: '武圣'));
    }
    // 龙胆：杀闪互换
    if (p.hasSkill('龙胆')) {
      if (c.name == 'sha') {
        list.add(CardView(
            real: c, name: 'shan', label: '闪', bySkill: '龙胆'));
      } else if (c.name == 'shan') {
        list.add(CardView(
            real: c, name: 'sha', label: '杀', bySkill: '龙胆'));
      }
    }
    return list;
  }

  /// 当前玩家在出牌阶段可执行的动作候选。
  List<PlayOption> playOptions(Player p) {
    final out = <PlayOption>[];
    final shaOK = p.hasSkill('咆哮') ||
        p.equips['weapon']?.name == 'liannu' ||
        p.shaUsed < 1;
    for (final c in p.hand) {
      for (final v in views(p, c)) {
        if (!v.isConversion && v.real.isEquip) {
          out.add(PlayOption(
              actor: p, view: v, need: 0, candidates: const <Player>[]));
          continue;
        }
        var ok = false;
        var need = 0;
        List<Player> candidates = const <Player>[];
        switch (v.name) {
          case 'sha':
            candidates = targetable(p, 'sha');
            ok = shaOK && candidates.isNotEmpty;
            need = 1;
            break;
          case 'shan':
          case 'wuxie':
            ok = false; // 响应牌，不在出牌阶段主动打出
            break;
          case 'tao':
            ok = p.hp < p.maxHp;
            break;
          case 'jiu':
            ok = p.drunk < 1;
            break;
          case 'wuzhong':
          case 'taoyuan':
          case 'wugu':
            ok = true;
            break;
          case 'wanjian':
          case 'nanzheng':
            ok = state.alivePlayers.length >= 2;
            break;
          case 'tieso':
          case 'shandian':
            ok = v.name != 'shandian' ||
                !p.judges.any((j) => j.name == 'shandian');
            break;
          default:
            candidates = targetable(p, v.name);
            ok = candidates.isNotEmpty;
            need = 1;
        }
        if (ok) {
          out.add(PlayOption(
              actor: p, view: v, need: need, candidates: candidates));
        }
      }
    }
    return out;
  }

  /// 主动技能（仅有真实实现的技能会出现，其余标注未实装不列出）。
  List<String> activeSkills(Player p) {
    final list = <String>[];
    if (p.hasSkill('仁德') &&
        p.hand.length >= 2 &&
        state.matesOf(p).isNotEmpty) {
      list.add('仁德');
    }
    return list;
  }

  bool useSkill(Player p, String skill) {
    if (state.over || state.phase != BattlePhase.play) return false;
    if (!activeSkills(p).contains(skill)) return false;
    if (skill == '仁德') {
      final mate = state.matesOf(p).first;
      final give = p.hand.sublist(0, 2);
      p.hand.removeRange(0, 2);
      mate.hand.addAll(give);
      p.hp = _clampHp(p.hp + 1, p.maxHp);
      _sayQuote(p, '仁德');
      say('${p.name} 【仁德】：交给 ${mate.name} 2 张手牌，回复 1 点体力',
          LogKind.skill);
      return true;
    }
    return false;
  }

  // ---------------- 开局 ----------------
  /// heroes 按座位顺序给 4 个：0 我(龙主将)、1 敌(虎主将)、2 队友(龙先锋)、3 敌(虎先锋)。
  BattleState newGame(List<BattleHero> heroes) {
    if (heroes.length != 4) {
      throw ArgumentError('2v2 需要恰好 4 名武将');
    }
    final players = <Player>[];
    for (var i = 0; i < 4; i++) {
      players.add(Player(
        seat: kSeats[i],
        hero: heroes[i],
        implSkills: implementedSkillsOf(heroes[i]),
      ));
    }
    _state = BattleState(players: players);
    _logSeq = 0;
    state.deck.addAll(shuffleCards(buildDeck()));
    say('⚔️ 2v2 龙虎斗开局！', LogKind.system);
    say('你是 🐲 龙·${state.me.name}（${state.me.maxHp} 体力），'
        '队友 ${players[2].name}，敌方 ${players[1].name} / ${players[3].name}');
    final impl = state.me.implSkills;
    if (impl.isNotEmpty) {
      final skillText = impl.join('、');
      say('已实装技能：$skillText', LogKind.skill);
    } else {
      say('⚠️ ${state.me.name} 的技能尚未实装，靠牌技应战！');
    }
    for (final p in players) {
      draw(p, 4);
    }
    return state;
  }

  // ---------------- 回合状态机 ----------------
  /// 判定阶段 + 摸牌阶段，进入出牌阶段。返回是否可出牌（false=被乐跳过）。
  bool beginTurn() {
    if (state.over) return false;
    final p = state.currentPlayer;
    state.phase = BattlePhase.judge;
    say('▶ 轮到 ${p.name}（${p.team.label}·${p.role.label}）· 第 ${state.round} 轮',
        LogKind.system);

    // 死斗期：第 12 轮起每回合流失 1 体力，避免回血互耗无限局。
    if (state.round > 12) {
      say('⏳ 死斗期（第 ${state.round} 轮）：${p.name} 流失 1 点体力');
      _damage(null, p, 1, element: 'losshp');
      if (state.over) return false;
    }

    _resolveJudges(p);
    if (state.over) return false;

    state.phase = BattlePhase.draw;
    var n = 2 + (p.hasSkill('英姿') ? 1 : 0);
    p.yingzi = p.hasSkill('英姿');
    if (p.skipDraw) {
      p.skipDraw = false;
      say('${p.name} 跳过摸牌阶段');
    } else {
      draw(p, n);
      if (!p.isHuman) say('${p.name} 摸 $n 张牌');
    }
    if (p.yingzi) {
      _sayQuote(p, '英姿');
      say('${p.name} 【英姿】：摸 3 张，本回合手牌上限 -1', LogKind.skill);
    }

    p.shaUsed = 0;
    p.drunk = 0;
    if (p.skipPlay) {
      p.skipPlay = false;
      say('${p.name} 被【乐不思蜀】困住，跳过出牌阶段');
      state.phase = BattlePhase.play;
      return false;
    }
    state.phase = BattlePhase.play;
    return true;
  }

  void _resolveJudges(Player p) {
    if (p.judges.isEmpty) return;
    final list = List<Card>.from(p.judges);
    p.judges.clear();
    for (final jc in list) {
      final rc = drawOne();
      say('${p.name} 判定（${jc.label}）：${_label(rc)}');
      var moved = false;
      switch (jc.name) {
        case 'lebu':
          if (rc.isRed) {
            say('判定红色，【乐不思蜀】失效');
          } else {
            p.skipPlay = true;
            say('【乐不思蜀】生效：${p.name} 跳过出牌阶段');
          }
          break;
        case 'bingliang':
          if (rc.isBlack) {
            p.skipDraw = true;
            say('【兵粮寸断】生效：跳过摸牌阶段');
          } else {
            say('判定非黑，【兵粮寸断】失效');
          }
          break;
        case 'shandian':
          if (rc.suit == '♠') {
            say('⚡ 闪电劈中 ${p.name}！');
            _damage(null, p, 3, card: jc, element: 'thunder');
          } else {
            final nx = state.players[(p.index + 1) % 4];
            if (nx.alive && nx != p) {
              nx.judges.add(jc);
              moved = true;
              say('闪电移交给下家 ${nx.name}');
            }
          }
          break;
      }
      if (!moved) toPile(<Card>[jc]);
      toPile(<Card>[rc]);
      if (state.over) return;
    }
  }

  /// 弃牌阶段 + 结束阶段 + 推进到下一座位。
  void endTurn() {
    if (state.over) return;
    final p = state.currentPlayer;
    state.phase = BattlePhase.discard;
    var keep = p.hp - (p.yingzi ? 1 : 0);
    if (keep < 0) keep = 0;
    if (p.hand.length > keep) {
      final n = p.hand.length - keep;
      final dropped = p.hand.sublist(p.hand.length - n);
      p.hand.removeRange(p.hand.length - n, p.hand.length);
      toPile(dropped);
      say('${p.name} 弃掉 $n 张手牌');
    }
    p.shaUsed = 0;
    p.drunk = 0;
    p.yingzi = false;
    p.skipPlay = false;
    p.skipDraw = false;
    state.phase = BattlePhase.end;
    _advanceTurn();
  }

  /// 翻面 / 阵亡座位跳过（不做判定摸牌，直接推进）。
  void passTurn() {
    if (state.over) return;
    final p = state.currentPlayer;
    if (!p.alive) {
      say('${p.name} 已阵亡，跳过回合');
    } else if (p.flipped) {
      p.flipped = false;
      say('${p.name} 翻回正面，跳过此回合');
    }
    state.phase = BattlePhase.end;
    _advanceTurn();
  }

  void _advanceTurn() {
    state.turnIdx = (state.turnIdx + 1) % 4;
    if (state.turnIdx == 0) state.round++;
    state.phase = BattlePhase.wait;
    checkWin();
  }

  /// 敌方（AI）完整回合：判定 → 摸牌 → 出牌（可解释规则）→ 弃牌 → 结束。
  void runAiTurn() {
    if (state.over) return;
    final canPlay = beginTurn();
    final p = state.currentPlayer;
    if (!state.over && canPlay && p.alive) {
      var steps = 0;
      while (steps < 8 &&
          !state.over &&
          p.alive &&
          state.phase == BattlePhase.play) {
        if (!_aiOneAction(p)) break;
        steps++;
      }
    }
    if (!state.over) endTurn();
  }

  // ---------------- AI 决策 ----------------
  static const Map<String, int> _aiPriority = <String, int>{
    'wuzhong': 0,
    'tao': 0,
    'jiu': 1,
    'liannu': 1,
    'sha': 2,
    'juedou': 3,
    'guohe': 3,
    'shunshou': 3,
    'lebu': 4,
    'bingliang': 4,
    'wugu': 4,
    'huogong': 5,
    'jiedao': 5,
    'taoyuan': 5,
    'wanjian': 6,
    'nanzheng': 6,
    'tieso': 7,
    'shandian': 9,
  };

  bool _aiOneAction(Player p) {
    final opts = playOptions(p);
    opts.sort((a, b) =>
        (_aiPriority[a.view.name] ?? 7) - (_aiPriority[b.view.name] ?? 7));
    for (final opt in opts) {
      final ts = opt.candidates.take(opt.need).toList();
      if (ts.length < opt.need) continue;
      // 吃桃：低血或手牌充裕才吃；装备 / 无中生有 / 出杀一律执行。
      if (opt.view.name == 'tao' && !(p.hp <= 2 || p.hand.length > 4)) {
        continue;
      }
      _resolvePlay(p, opt.view, ts);
      return true;
    }
    // 主动技能：仁德（手牌多且自己或队友受伤）。
    for (final s in activeSkills(p)) {
      if (s == '仁德' &&
          p.hand.length >= 4 &&
          (p.hp < p.maxHp ||
              state.matesOf(p).any((m) => m.hp < m.maxHp))) {
        return useSkill(p, s);
      }
    }
    return false;
  }

  // ---------------- 人类 / 测试出牌入口 ----------------
  bool play(PlayOption opt, List<Player> targets) {
    if (state.over || state.phase != BattlePhase.play) return false;
    if (targets.length < opt.need) return false;
    if (!opt.actor.hand.contains(opt.card)) return false;
    _resolvePlay(opt.actor, opt.view, targets);
    return true;
  }

  /// 测试 / 简易调用：按生效规则键直接打出一张真实手牌。
  bool playCard(Player actor, Card real, List<Player> targets, {String? asName}) {
    final view = CardView(
      real: real,
      name: asName ?? real.name,
      label: real.label,
      element: asName == null ? real.element : null,
    );
    _resolvePlay(actor, view, targets);
    return true;
  }

  // ---------------- 结算分发 ----------------
  void _resolvePlay(Player p, CardView view, List<Player> targets) {
    _currentCard = view.real;
    p.hand.remove(view.real);
    final tgtText =
        targets.isEmpty ? '全场' : targets.map((t) => t.name).join('、');
    say('${p.name} 使用【${view.label}】${_label(view.real)} → $tgtText');
    if (view.isConversion) {
      _sayQuote(p, view.bySkill!);
      say('${p.name} 【${view.bySkill}】把【${view.real.label}】当【${view.label}】使用',
          LogKind.skill);
    }
    if (view.name == 'sha') p.shaUsed++;
    if (view.name == 'jiu') p.drunk++;

    // 原生装备牌：穿到装备区，不入弃牌堆。
    if (!view.isConversion && view.real.isEquip) {
      _equip(p, view.real);
      return;
    }

    switch (view.name) {
      case 'sha':
        _doSha(p, view, targets.isEmpty ? null : targets.first);
        break;
      case 'tao':
        p.hp = _clampHp(p.hp + 1, p.maxHp);
        say('${p.name} 吃【桃】，体力 ${p.hpText}', LogKind.heal);
        break;
      case 'jiu':
        say('${p.name} 喝【酒】：下一张【杀】伤害 +1');
        break;
      case 'wuzhong':
        draw(p, 2);
        say('${p.name} 【无中生有】：摸 2 张牌');
        break;
      case 'taoyuan':
        for (final q in state.alivePlayers) {
          q.hp = _clampHp(q.hp + 1, q.maxHp);
        }
        say('【桃园结义】：全体回复 1 点体力', LogKind.heal);
        break;
      case 'wugu':
        _doWugu(p);
        break;
      case 'wanjian':
        _doAoe(p, view, '万箭齐发', needShan: true);
        break;
      case 'nanzheng':
        _doAoe(p, view, '南蛮入侵', needShan: false);
        break;
      case 'shunshou':
        if (targets.isNotEmpty) _doSteal(p, targets.first, true);
        break;
      case 'guohe':
        if (targets.isNotEmpty) _doSteal(p, targets.first, false);
        break;
      case 'juedou':
        if (targets.isNotEmpty) _doJuedou(p, targets.first, view);
        break;
      case 'lebu':
      case 'bingliang':
        if (targets.isNotEmpty) {
          targets.first.judges.add(view.real);
          say('${targets.first.name} 被贴上【${view.label}】');
        }
        break;
      case 'shandian':
        p.judges.add(view.real);
        say('${p.name} 头顶挂上【闪电】⚡');
        break;
      case 'tieso':
        for (final t in state.alivePlayers) {
          t.chained = !t.chained;
        }
        say('【铁索连环】：全场连环状态翻转（简化结算，未做属性伤害传导）');
        break;
      case 'huogong':
        if (targets.isNotEmpty) _doHuogong(p, targets.first);
        break;
      case 'jiedao':
        if (targets.isNotEmpty) _doJiedao(p, targets.first);
        break;
      default:
        say('【${view.label}】结算按简化规则处理（该锦囊完整效果未迁移）');
    }

    // 非装备牌入弃牌堆；若被【奸雄】拿走则不再入堆。
    final held = state.players.any((q) => q.hand.contains(view.real));
    if (!held) toPile(<Card>[view.real]);
    checkWin();
  }

  void _equip(Player p, Card c) {
    final slot = c.slot ?? 'weapon';
    final old = p.equips[slot];
    p.equips[slot] = c;
    if (old != null) toPile(<Card>[old]);
    final rangeNote = c.range > 0 ? '（射程 ${c.range}）' : '';
    say('${p.name} 装备了【${c.label}】$rangeNote');
  }

  // ---------------- 杀 / 锦囊结算 ----------------
  void _doSha(Player p, CardView view, Player? t) {
    if (t == null || !t.alive) return;
    say('${p.name} 对 ${t.name} 使用【${view.label}】');

    var armor = t.equips['armor'];
    if (armor != null && p.equips['weapon']?.name == 'qinggang') {
      say('青釭剑：无视 ${t.name} 的【${armor.label}】');
      armor = null;
    }
    if (armor != null && armor.name == 'renwang' && view.real.isBlack) {
      say('${t.name} 【仁王盾】：黑色【杀】无效');
      return;
    }
    if (armor != null && armor.name == 'tengjia' && view.element == null) {
      say('${t.name} 【藤甲】：普通【杀】无效');
      return;
    }

    // 无双：目标需两张【闪】。
    final needed = p.hasSkill('无双') ? 2 : 1;
    if (needed == 2) {
      _sayQuote(p, '无双');
      say('${p.name} 【无双】：${t.name} 需打出 2 张【闪】才能抵消',
          LogKind.skill);
    }
    final dodges = policy.dodgeCards(this, t, needed);
    if (dodges.length >= needed) {
      for (final c in dodges) {
        loseCard(t, c);
        if (c.name != 'shan') {
          say('${t.name} 【龙胆】：以【杀】当【闪】', LogKind.skill);
        }
      }
      say('${t.name} 打出【闪】×$needed，抵消了【杀】');
      return;
    }
    if (dodges.isNotEmpty) {
      say('${t.name} 【闪】不足 $needed 张，放弃闪避');
    }

    var dmg = 1 + (p.drunk > 0 ? 1 : 0);
    if (p.drunk > 0) {
      p.drunk = 0;
      say('酒劲上头：【杀】伤害 +1');
    }
    if (p.equips['weapon']?.name == 'qilin' &&
        (t.equips['horseP'] != null || t.equips['horseM'] != null)) {
      final slot = t.equips['horseP'] != null ? 'horseP' : 'horseM';
      final horse = t.equips[slot];
      t.equips[slot] = null;
      if (horse != null) {
        toPile(<Card>[horse]);
        say('麒麟弓：射落 ${t.name} 的【${horse.label}】');
      }
    }
    _damage(p, t, dmg, card: view.real, element: view.element);
  }

  void _doAoe(
    Player p,
    CardView view,
    String label, {
    required bool needShan,
  }) {
    for (final t in state.alivePlayers) {
      if (t == p || state.over) continue;
      say('【$label】→ ${t.name}');
      if (_askWuxie(p, <Player>[t], label)) continue;
      if (t.equips['armor']?.name == 'tengjia' && view.element == null) {
        say('${t.name} 【藤甲】：普通锦囊无效');
        continue;
      }
      final cards = needShan
          ? policy.dodgeCards(this, t, 1)
          : policy.shaCards(this, t, 1);
      if (cards.isNotEmpty) {
        loseCard(t, cards.first);
        final resp = needShan ? '闪' : '杀';
        say('${t.name} 打出【$resp】响应');
      } else {
        _damage(p, t, 1, card: view.real);
      }
      if (state.over) return;
    }
  }

  void _doWugu(Player p) {
    final cards = <Card>[];
    for (var i = 0; i < state.alivePlayers.length; i++) {
      cards.add(drawOne());
    }
    say('【五谷丰登】亮出 ${cards.length} 张牌');
    for (final q in state.alivePlayers) {
      if (cards.isEmpty) break;
      final c = cards.removeAt(0);
      q.hand.add(c);
      say('${q.name} 拿走 ${_label(c)}');
    }
    toPile(cards);
  }

  void _doSteal(Player p, Player t, bool isShun) {
    final label = isShun ? '顺手牵羊' : '过河拆桥';
    if (t.judges.isNotEmpty) {
      final c = t.judges.removeAt(0);
      toPile(<Card>[c]);
      say('${p.name} 【$label】拆掉 ${t.name} 判定区的【${c.label}】');
      return;
    }
    if (t.hand.isNotEmpty) {
      final c = t.hand.removeLast();
      if (isShun) {
        p.hand.add(c);
        say('${p.name} 【顺手牵羊】拿走 ${t.name} 一张手牌（${c.label}）');
      } else {
        toPile(<Card>[c]);
        say('${p.name} 【过河拆桥】弃掉 ${t.name} 一张手牌（${c.label}）');
      }
      return;
    }
    for (final slot in const <String>['weapon', 'armor', 'horseP', 'horseM']) {
      final c = t.equips[slot];
      if (c != null) {
        t.equips[slot] = null;
        if (isShun) {
          p.hand.add(c);
          say('${p.name} 【顺手牵羊】牵走 ${t.name} 的【${c.label}】');
        } else {
          toPile(<Card>[c]);
          say('${p.name} 【过河拆桥】拆掉 ${t.name} 的【${c.label}】');
        }
        return;
      }
    }
    say('【$label】没有可拆的目标');
  }

  void _doJuedou(Player p, Player t, CardView view) {
    if (!t.alive) return;
    if (_askWuxie(p, <Player>[t], '决斗')) return;
    say('${p.name} 对 ${t.name} 发起【决斗】！');
    var cur = t;
    var other = p;
    while (!state.over) {
      final need = other.hasSkill('无双') ? 2 : 1;
      final shas = policy.shaCards(this, cur, need);
      if (shas.length < need) {
        _damage(other, cur, 1, card: view.real);
        return;
      }
      for (final c in shas) {
        loseCard(cur, c);
      }
      final extra = need == 2 ? ' ×2（无双）' : '';
      say('${cur.name} 打出【杀】$extra');
      final tmp = cur;
      cur = other;
      other = tmp;
    }
  }

  void _doHuogong(Player p, Player t) {
    if (!t.alive || t.hand.isEmpty) {
      say('火攻未生效（对方没有手牌）');
      return;
    }
    final show = t.hand.first;
    say('火攻：${t.name} 亮出 ${_label(show)}，${p.name} 需弃一张同花色牌');
    final same = p.hand.where((c) => c.suit == show.suit).toList();
    if (same.isEmpty) {
      say('${p.name} 没有同花色牌，火攻失败');
      return;
    }
    loseCard(p, same.first);
    _damage(p, t, 1, card: _currentCard, element: 'fire');
  }

  void _doJiedao(Player p, Player t) {
    if (!t.alive || t.equips['weapon'] == null) return;
    final es = state.enemiesOf(t).where((x) => x != p).toList();
    if (es.isEmpty) {
      say('借刀杀人：没有合适的攻击目标');
      return;
    }
    final tgt2 = es.first;
    say('${p.name} 借刀杀人：令 ${t.name} 对 ${tgt2.name} 用【杀】');
    final shas = policy.shaCards(this, t, 1);
    if (shas.isNotEmpty) {
      loseCard(t, shas.first);
      say('${t.name} 打出【杀】');
      final dodges = policy.dodgeCards(this, tgt2, 1);
      if (dodges.isEmpty) {
        _damage(t, tgt2, 1, card: _currentCard);
      } else {
        loseCard(tgt2, dodges.first);
        say('${tgt2.name} 打出【闪】');
      }
    } else {
      final w = t.equips['weapon'];
      t.equips['weapon'] = null;
      if (w != null) {
        p.hand.add(w);
        say('${t.name} 不出杀，${p.name} 收缴了【${w.label}】');
      }
    }
  }

  /// 基础无懈响应：保护目标方（默认策略仅自救）。
  bool _askWuxie(Player user, List<Player> targets, String trick) {
    for (final q in state.alivePlayers) {
      final wuxies = q.hand.where((c) => c.name == 'wuxie').toList();
      if (wuxies.isEmpty) continue;
      final protect =
          targets.contains(q) || targets.any((t) => t.team == q.team);
      if (!protect) continue;
      if (policy.useWuxie(this, q, targets, trick)) {
        loseCard(q, wuxies.first);
        say('${q.name} 打出【无懈可击】，【$trick】被抵消', LogKind.skill);
        return true;
      }
    }
    return false;
  }

  // ---------------- 伤害 / 濒死 / 死亡 / 胜负 ----------------
  int _clampHp(int v, int max) => v > max ? max : (v < 0 ? 0 : v);

  void _damage(
    Player? src,
    Player tgt,
    int n, {
    Card? card,
    String? element,
  }) {
    if (!tgt.alive || state.over) return;
    final cause = card ?? _currentCard;
    var dmg = n;
    if (tgt.equips['armor']?.name == 'tengjia' && element == 'fire') {
      dmg += 1;
      say('${tgt.name} 【藤甲】：火焰伤害 +1');
    }
    tgt.hp -= dmg;
    final mark = element == 'fire'
        ? ' 🔥'
        : element == 'thunder'
            ? ' ⚡'
            : '';
    final srcName = src?.name ?? '?';
    say('$srcName 对 ${tgt.name} 造成 $dmg 点伤害$mark', LogKind.damage);

    if (tgt.hp > 0) {
      // 奸雄：获得造成伤害的牌。
      if (tgt.hasSkill('奸雄') && cause != null) {
        tgt.hand.add(cause);
        state.pile.remove(cause);
        _sayQuote(tgt, '奸雄');
        say('${tgt.name} 【奸雄】：拿走造成伤害的【${cause.label}】',
            LogKind.skill);
      }
      // 白银狮子：受到伤害后回复 1 点体力。
      if (tgt.equips['armor']?.name == 'baiyin') {
        tgt.hp = _clampHp(tgt.hp + 1, tgt.maxHp);
        say('${tgt.name} 【白银狮子】：回复 1 点体力', LogKind.heal);
      }
    }
    if (tgt.hp <= 0) _dying(tgt, src);
    checkWin();
  }

  void _dying(Player tgt, Player? src) {
    say('💀 ${tgt.name} 濒死！求【桃】…');
    final order = <Player>[tgt, ...state.alivePlayers.where((q) => q != tgt)];
    for (final q in order) {
      if (tgt.hp > 0) break;
      if (!q.alive) continue;
      if (q != tgt && q.team != tgt.team) continue; // 只有自己与队友能救
      while (tgt.hp <= 0) {
        final peach = policy.peachCard(this, q, tgt);
        if (peach == null) break;
        loseCard(q, peach);
        tgt.hp += 1;
        say('${q.name} 出【桃】，${tgt.name} 回到 ${tgt.hp} 体力',
            LogKind.heal);
      }
    }
    if (tgt.hp <= 0) _dead(tgt, src);
  }

  void _dead(Player p, Player? killer) {
    p.alive = false;
    p.hp = 0;
    toPile(p.hand);
    p.hand.clear();
    for (final slot in const <String>['weapon', 'armor', 'horseP', 'horseM']) {
      final c = p.equips[slot];
      if (c != null) toPile(<Card>[c]);
      p.equips[slot] = null;
    }
    toPile(p.judges);
    p.judges.clear();
    _sayQuote(p, '阵亡');
    say('☠️ ${p.name} 阵亡', LogKind.death);
    if (killer != null && killer.alive && killer.team != p.team) {
      draw(killer, 3);
      say('${killer.name} 击杀奖励：摸 3 张牌');
    }
    checkWin();
  }

  void checkWin() {
    if (state.over) return;
    final d = state.teamAlive(BattleTeam.dragon);
    final t = state.teamAlive(BattleTeam.tiger);
    if (d == 0 || t == 0) {
      state.over = true;
      state.winner = d > 0 ? BattleTeam.dragon : BattleTeam.tiger;
      state.phase = BattlePhase.over;
      say('🏆 ${state.winner!.fullLabel}胜！对局结束', LogKind.win);
    }
  }
}
