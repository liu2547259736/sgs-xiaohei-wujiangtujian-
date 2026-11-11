// 2v2 龙虎斗 · 数据模型。
// 字段语义沿用主程序 battle.js：name=规则键、label=中文牌名、hand/equips/judges
// 分别对应手牌 / 装备区 / 判定区。纯 Dart，不引 Flutter / dart:io，便于单测。

/// 牌的类别，对应主程序 kind 的 'basic' / 'scroll' / 'equip'。
enum CardKind { basic, scroll, equip }

/// 一张具体的牌（由 buildDeck() 从 deck_data.dart 展开生成）。
class Card {
  const Card({
    required this.uid,
    required this.name,
    required this.label,
    required this.suit,
    required this.point,
    required this.kind,
    this.sub,
    this.element,
    this.slot,
    this.range = 0,
  });

  /// 唯一编号（c0..c159），用于同 seed 洗牌复现比对。
  final String uid;

  /// 规则键，如 sha / shan / tao / jiu / wuxie / liannu。
  final String name;

  /// 中文牌名，如 杀 / 闪 / 桃 / 诸葛连弩。
  final String label;

  /// 花色 ♠ ♥ ♦ ♣。
  final String suit;

  /// 点数 1..13（A=1、J=11、Q=12、K=13）。
  final int point;

  final CardKind kind;

  /// 子类：'n' / 'delay' / 'weapon' / 'armor' / 'horseP' / 'horseM'。
  final String? sub;

  /// 元素：'fire' / 'thunder'。
  final String? element;

  /// 装备槽位：'weapon' / 'armor' / 'horseP' / 'horseM'。
  final String? slot;

  /// 武器射程（非武器为 0）。
  final int range;

  bool get isRed => suit == '♥' || suit == '♦';
  bool get isBlack => suit == '♠' || suit == '♣';
  bool get isEquip => kind == CardKind.equip;

  String get pointLabel {
    switch (point) {
      case 1:
        return 'A';
      case 11:
        return 'J';
      case 12:
        return 'Q';
      case 13:
        return 'K';
      default:
        return point.toString();
    }
  }

  String get corner => '$suit$pointLabel';

  @override
  String toString() => '$label $corner';
}

// ---------------------------------------------------------------------------
// 队伍 / 座位
// ---------------------------------------------------------------------------

enum BattleTeam { dragon, tiger }

extension BattleTeamX on BattleTeam {
  String get label => this == BattleTeam.dragon ? '龙' : '虎';
  String get fullLabel => this == BattleTeam.dragon ? '龙方' : '虎方';
  BattleTeam get opposite =>
      this == BattleTeam.dragon ? BattleTeam.tiger : BattleTeam.dragon;
}

enum SeatRole { lord, vanguard }

extension SeatRoleX on SeatRole {
  String get label => this == SeatRole.lord ? '主将' : '先锋';
}

/// 一个座位的静态配置。
class Seat {
  const Seat({
    required this.index,
    required this.team,
    required this.role,
    required this.isHuman,
  });

  /// 0..3，同时是出牌顺序。
  final int index;
  final BattleTeam team;
  final SeatRole role;
  final bool isHuman;

  String get label => '${team.label}·${role.label}';
}

/// 2v2 固定座位表，沿用主程序 startGame：
/// 0 我(龙·主将) → 1 敌(虎·主将) → 2 队友(龙·先锋) → 3 敌(虎·先锋)。
const List<Seat> kSeats = <Seat>[
  Seat(index: 0, team: BattleTeam.dragon, role: SeatRole.lord, isHuman: true),
  Seat(index: 1, team: BattleTeam.tiger, role: SeatRole.lord, isHuman: false),
  Seat(index: 2, team: BattleTeam.dragon, role: SeatRole.vanguard, isHuman: false),
  Seat(index: 3, team: BattleTeam.tiger, role: SeatRole.vanguard, isHuman: false),
];

// ---------------------------------------------------------------------------
// 武将
// ---------------------------------------------------------------------------

/// 选将用的轻量武将，从 seed 的 sgsol-00x.json 的 general 解析。
class BattleHero {
  const BattleHero({
    required this.name,
    this.id = '',
    this.title = '',
    this.kingdom = 'qun',
    this.gender = '',
    this.pack = '',
    this.hp = 4,
    this.avatar = '',
    this.skills = const <String>[],
    this.skillDescs = const <String, String>{},
    this.quotes = const <String, String>{},
  });

  final String name;
  final String id;
  final String title;
  final String kingdom;
  final String gender;
  final String pack;
  final double hp;
  final String avatar;

  /// 技能名列表（来自 general.s[].name）。
  final List<String> skills;

  /// 技能名 -> 说明文本（来自 general.s[].description）。
  final Map<String, String> skillDescs;

  /// 台词（来自 general.q，值可能是字符串或字符串数组）。
  final Map<String, String> quotes;

  /// 主程序 heroHp：clamp 到 2..6。
  int get maxHp {
    final v = hp.round();
    return v < 2 ? 2 : (v > 6 ? 6 : v);
  }

  factory BattleHero.fromJson(Map<String, dynamic> j) {
    final skills = <String>[];
    final descs = <String, String>{};
    final rawSkills = j['s'];
    if (rawSkills is List) {
      for (final s in rawSkills) {
        if (s is Map) {
          final n = (s['name'] ?? '').toString();
          if (n.isEmpty) continue;
          skills.add(n);
          descs[n] = (s['description'] ?? s['oneSentenceDesc'] ?? '').toString();
        }
      }
    }

    final quotes = <String, String>{};
    final q = j['q'];
    if (q is Map) {
      q.forEach((k, v) {
        final val =
            v is List ? v.map((e) => e.toString()).join(' / ') : v.toString();
        quotes[k.toString()] = val;
      });
    }

    double hpv = 4;
    final h = j['hp'];
    if (h is num) {
      hpv = h.toDouble();
    } else if (h is String) {
      hpv = double.tryParse(h) ?? 4;
    }

    return BattleHero(
      name: (j['n'] ?? '').toString(),
      id: (j['id'] ?? '').toString(),
      title: (j['t'] ?? '').toString(),
      kingdom: (j['k'] ?? 'qun').toString(),
      gender: (j['g'] ?? '').toString(),
      pack: (j['p'] ?? '').toString(),
      hp: hpv,
      avatar: (j['av'] ?? '').toString(),
      skills: List<String>.unmodifiable(skills),
      skillDescs: Map<String, String>.unmodifiable(descs),
      quotes: Map<String, String>.unmodifiable(quotes),
    );
  }
}

// ---------------------------------------------------------------------------
// 玩家
// ---------------------------------------------------------------------------

/// 一个座位上的角色（简单可变模型，引擎直接改字段）。
class Player {
  Player({
    required this.seat,
    required this.hero,
    required this.implSkills,
  })  : name = hero.name,
        kingdom = hero.kingdom,
        maxHp = hero.maxHp,
        hp = hero.maxHp;

  final Seat seat;
  final BattleHero hero;

  /// 该武将「真实实现」的技能名（白名单 ∩ kImplementedSkills）。
  /// 引擎只认这里面的技能，其余技能一律不生效，UI 标注「未实装」。
  final List<String> implSkills;

  final String name;
  final String kingdom;
  final int maxHp;
  int hp;

  final List<Card> hand = <Card>[];
  final Map<String, Card?> equips = <String, Card?>{
    'weapon': null,
    'armor': null,
    'horseP': null,
    'horseM': null,
  };
  final List<Card> judges = <Card>[];

  bool alive = true;
  bool flipped = false;
  bool chained = false;

  /// 本回合已出【杀】数（普通角色上限 1，咆哮 / 诸葛连弩 无限）。
  int shaUsed = 0;

  /// 酒：>0 时下一张【杀】伤害 +1，结算后清零。
  int drunk = 0;

  bool skipPlay = false;
  bool skipDraw = false;

  /// 英姿：本回合手牌上限 -1（摸 3 弃 1 口径）。
  bool yingzi = false;

  int get index => seat.index;
  BattleTeam get team => seat.team;
  SeatRole get role => seat.role;
  bool get isHuman => seat.isHuman;
  int get attackRange => 1 + (equips['weapon']?.range ?? 0);

  bool hasSkill(String skill) => alive && implSkills.contains(skill);

  List<String> get equipLabels {
    final out = <String>[];
    for (final slot in const <String>['weapon', 'armor', 'horseP', 'horseM']) {
      final c = equips[slot];
      if (c != null) out.add(c.label);
    }
    return out;
  }

  String get hpText => '$hp/$maxHp';
}

// ---------------------------------------------------------------------------
// 出牌视图 / 动作
// ---------------------------------------------------------------------------

/// 一张手牌的「出牌视图」：技能转化后生效的规则键可能与真实牌不同。
class CardView {
  const CardView({
    required this.real,
    required this.name,
    required this.label,
    this.element,
    this.bySkill,
  });

  /// 真实要打出的手牌。
  final Card real;

  /// 生效规则键（sha / guohe / ...）。
  final String name;

  /// 生效中文牌名。
  final String label;

  final String? element;

  /// 转化技能名（null 表示原生打出）。
  final String? bySkill;

  bool get isConversion => bySkill != null;
  bool get isEquip => real.kind == CardKind.equip;
}

/// 一个可出的动作候选（供 UI 渲染按钮、AI 决策）。
class PlayOption {
  const PlayOption({
    required this.actor,
    required this.view,
    required this.need,
    required this.candidates,
  });

  final Player actor;
  final CardView view;

  /// 需要的目标数，0 表示无需选目标。
  final int need;

  /// 合法目标列表。
  final List<Player> candidates;

  Card get card => view.real;
}

// ---------------------------------------------------------------------------
// 回合 / 日志 / 全局状态
// ---------------------------------------------------------------------------

enum BattlePhase { judge, draw, play, discard, end, wait, over }

extension BattlePhaseX on BattlePhase {
  String get label {
    switch (this) {
      case BattlePhase.judge:
        return '判定';
      case BattlePhase.draw:
        return '摸牌';
      case BattlePhase.play:
        return '出牌';
      case BattlePhase.discard:
        return '弃牌';
      case BattlePhase.end:
        return '结束';
      case BattlePhase.wait:
        return '等待';
      case BattlePhase.over:
        return '对局结束';
    }
  }
}

enum LogKind { info, draw, damage, heal, skill, quote, death, system, win }

class LogEntry {
  const LogEntry(this.text, {this.kind = LogKind.info, required this.seq});

  final String text;
  final LogKind kind;
  final int seq;
}

class BattleState {
  BattleState({required this.players});

  /// 按 seat.index 顺序，长度固定 4。
  final List<Player> players;

  /// 摸牌堆（pop 取牌）。
  final List<Card> deck = <Card>[];

  /// 弃牌堆。
  final List<Card> pile = <Card>[];

  final List<LogEntry> log = <LogEntry>[];
  int logSeq = 0;

  int round = 1;
  int turnIdx = 0;
  bool over = false;
  BattleTeam? winner;
  BattlePhase phase = BattlePhase.wait;

  Player get currentPlayer => players[turnIdx];
  Player get me => players[0];

  List<Player> get alivePlayers =>
      players.where((p) => p.alive).toList(growable: false);

  int teamAlive(BattleTeam team) =>
      players.where((p) => p.alive && p.team == team).length;

  List<Player> enemiesOf(Player p) =>
      players.where((q) => q.alive && q.team != p.team).toList(growable: false);

  List<Player> matesOf(Player p) => players
      .where((q) => q.alive && q != p && q.team == p.team)
      .toList(growable: false);
}
