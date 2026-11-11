// 由 gen_deck.py 从主程序 battle.js 精确解析生成，请勿手改。
// 来源: sgs-heroes-app/battle.js  DEFS / WEAPONS / ARMORS / HORSES (第 28~111 行)
// 生成命令: python lib/features/battle/gen_deck.py
// engine.buildDeck() 会把 points 数组展开成恰好 160 张军争牌。

// 点数符号 -> 点数 (A=1, J=11, Q=12, K=13)
int pointOf(String sym) {
  switch (sym) {
    case 'A':
      return 1;
    case 'J':
      return 11;
    case 'Q':
      return 12;
    case 'K':
      return 13;
    default:
      return int.tryParse(sym) ?? 0;
  }
}

/// DEFS 里的一条紧凑定义：点数数组 points 会被展开成多张牌。
class CardDef {
  const CardDef({
    required this.name,
    required this.label,
    required this.suit,
    required this.points,
    required this.kindCode,
    this.sub,
    this.element,
  });

  final String name; // 规则键（如 sha / shan / wuxie）
  final String label; // 中文牌名
  final String suit; // ♠ ♥ ♦ ♣
  final List<String> points; // 点数符号数组，逐张展开
  final String kindCode; // 'b'=基本牌, 's'=锦囊牌
  final String? sub; // 子类: 'n' / 'delay' / null
  final String? element; // 元素: 'fire' / 'thunder' / null
}

/// WEAPONS / ARMORS / HORSES 里的一条装备定义（单张）。
class EquipDef {
  const EquipDef({
    required this.name,
    required this.label,
    required this.suit,
    required this.point,
    required this.sub,
    required this.slot,
    required this.range,
  });

  final String name; // 规则键
  final String label; // 中文牌名
  final String suit; // ♠ ♥ ♦ ♣
  final String point; // 点数符号
  final String sub; // 子类: weapon / armor / horseP / horseM
  final String slot; // 槽位: weapon / armor / horseP / horseM
  final int range; // 武器射程（非武器为 0）
}


const List<CardDef> kDefs = <CardDef>[
  CardDef(name: 'sha', label: '杀', suit: '♣', points: <String>['2', '3', '4', '5', '6', '7', '8', '8', '9', '9', '10', '10', 'J', 'J'], kindCode: 'b', sub: 'n', element: null),
  CardDef(name: 'sha', label: '杀', suit: '♠', points: <String>['7', '8', '8', '9', '9', '10', '10'], kindCode: 'b', sub: 'n', element: null),
  CardDef(name: 'sha', label: '杀', suit: '♥', points: <String>['10', '10', 'J'], kindCode: 'b', sub: 'n', element: null),
  CardDef(name: 'sha', label: '杀', suit: '♦', points: <String>['6', '7', '8', '9', '10', 'K'], kindCode: 'b', sub: 'n', element: null),
  CardDef(name: 'sha', label: '火杀', suit: '♥', points: <String>['4', '7', '10'], kindCode: 'b', sub: 'n', element: 'fire'),
  CardDef(name: 'sha', label: '火杀', suit: '♦', points: <String>['4', '5'], kindCode: 'b', sub: 'n', element: 'fire'),
  CardDef(name: 'sha', label: '雷杀', suit: '♠', points: <String>['4', '5', '6', '7', '8'], kindCode: 'b', sub: 'n', element: 'thunder'),
  CardDef(name: 'sha', label: '雷杀', suit: '♣', points: <String>['5', '6', '7', '8'], kindCode: 'b', sub: 'n', element: 'thunder'),
  CardDef(name: 'shan', label: '闪', suit: '♦', points: <String>['2', '2', '3', '4', '5', '6', '6', '7', '7', '8', '8', '9', '10', '10', 'J', 'J', 'J'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'shan', label: '闪', suit: '♥', points: <String>['2', '2', '8', '9', 'J', 'Q', 'K'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'tao', label: '桃', suit: '♦', points: <String>['2', '3', 'Q'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'tao', label: '桃', suit: '♥', points: <String>['3', '4', '5', '6', '6', '7', '8', '9', 'Q'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'jiu', label: '酒', suit: '♠', points: <String>['3', '9'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'jiu', label: '酒', suit: '♣', points: <String>['3', '9'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'jiu', label: '酒', suit: '♦', points: <String>['9'], kindCode: 'b', sub: null, element: null),
  CardDef(name: 'nanzheng', label: '南蛮入侵', suit: '♠', points: <String>['7', 'K'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'nanzheng', label: '南蛮入侵', suit: '♣', points: <String>['7'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wanjian', label: '万箭齐发', suit: '♥', points: <String>['A'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'taoyuan', label: '桃园结义', suit: '♥', points: <String>['A'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wugu', label: '五谷丰登', suit: '♥', points: <String>['3', '4'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wuxie', label: '无懈可击', suit: '♠', points: <String>['J', 'K'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wuxie', label: '无懈可击', suit: '♣', points: <String>['Q', 'K'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wuxie', label: '无懈可击', suit: '♦', points: <String>['Q'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wuxie', label: '无懈可击', suit: '♥', points: <String>['A', 'K'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'shunshou', label: '顺手牵羊', suit: '♠', points: <String>['3', '4', 'J'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'shunshou', label: '顺手牵羊', suit: '♦', points: <String>['3', '4'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'guohe', label: '过河拆桥', suit: '♠', points: <String>['3', '4', 'Q'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'guohe', label: '过河拆桥', suit: '♣', points: <String>['3', '4'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'guohe', label: '过河拆桥', suit: '♥', points: <String>['Q'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'jiedao', label: '借刀杀人', suit: '♣', points: <String>['Q', 'K'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'wuzhong', label: '无中生有', suit: '♥', points: <String>['7', '8', '9', 'J'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'tieso', label: '铁索连环', suit: '♠', points: <String>['J', 'Q'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'tieso', label: '铁索连环', suit: '♣', points: <String>['10', 'J', 'Q', 'K'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'huogong', label: '火攻', suit: '♥', points: <String>['2', '3'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'huogong', label: '火攻', suit: '♦', points: <String>['Q'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'juedou', label: '决斗', suit: '♠', points: <String>['A'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'juedou', label: '决斗', suit: '♣', points: <String>['A'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'juedou', label: '决斗', suit: '♦', points: <String>['A'], kindCode: 's', sub: null, element: null),
  CardDef(name: 'lebu', label: '乐不思蜀', suit: '♠', points: <String>['6'], kindCode: 's', sub: 'delay', element: null),
  CardDef(name: 'lebu', label: '乐不思蜀', suit: '♣', points: <String>['6'], kindCode: 's', sub: 'delay', element: null),
  CardDef(name: 'lebu', label: '乐不思蜀', suit: '♥', points: <String>['6'], kindCode: 's', sub: 'delay', element: null),
  CardDef(name: 'bingliang', label: '兵粮寸断', suit: '♠', points: <String>['10'], kindCode: 's', sub: 'delay', element: null),
  CardDef(name: 'bingliang', label: '兵粮寸断', suit: '♣', points: <String>['4'], kindCode: 's', sub: 'delay', element: null),
  CardDef(name: 'shandian', label: '闪电', suit: '♠', points: <String>['A'], kindCode: 's', sub: 'delay', element: null),
  CardDef(name: 'shandian', label: '闪电', suit: '♥', points: <String>['Q'], kindCode: 's', sub: 'delay', element: null),
];


const List<EquipDef> kWeapons = <EquipDef>[
  EquipDef(name: 'liannu', label: '诸葛连弩', suit: '♣', point: 'A', sub: 'weapon', slot: 'weapon', range: 1),
  EquipDef(name: 'liannu', label: '诸葛连弩', suit: '♦', point: 'A', sub: 'weapon', slot: 'weapon', range: 1),
  EquipDef(name: 'cixiong', label: '雌雄双股剑', suit: '♠', point: '2', sub: 'weapon', slot: 'weapon', range: 2),
  EquipDef(name: 'qinggang', label: '青釭剑', suit: '♠', point: '6', sub: 'weapon', slot: 'weapon', range: 2),
  EquipDef(name: 'qinglong', label: '青龙偃月刀', suit: '♠', point: '5', sub: 'weapon', slot: 'weapon', range: 3),
  EquipDef(name: 'zhangba', label: '丈八蛇矛', suit: '♠', point: 'Q', sub: 'weapon', slot: 'weapon', range: 3),
  EquipDef(name: 'guanshi', label: '贯石斧', suit: '♦', point: '5', sub: 'weapon', slot: 'weapon', range: 3),
  EquipDef(name: 'fangtian', label: '方天画戟', suit: '♦', point: 'Q', sub: 'weapon', slot: 'weapon', range: 4),
  EquipDef(name: 'qilin', label: '麒麟弓', suit: '♥', point: '5', sub: 'weapon', slot: 'weapon', range: 5),
  EquipDef(name: 'guding', label: '古锭刀', suit: '♠', point: 'A', sub: 'weapon', slot: 'weapon', range: 2),
  EquipDef(name: 'zhuque', label: '朱雀羽扇', suit: '♦', point: 'A', sub: 'weapon', slot: 'weapon', range: 4),
  EquipDef(name: 'hanbing', label: '寒冰剑', suit: '♠', point: '2', sub: 'weapon', slot: 'weapon', range: 2),
];


const List<EquipDef> kArmors = <EquipDef>[
  EquipDef(name: 'bagua', label: '八卦阵', suit: '♠', point: '2', sub: 'armor', slot: 'armor', range: 0),
  EquipDef(name: 'bagua', label: '八卦阵', suit: '♣', point: '2', sub: 'armor', slot: 'armor', range: 0),
  EquipDef(name: 'tengjia', label: '藤甲', suit: '♠', point: '2', sub: 'armor', slot: 'armor', range: 0),
  EquipDef(name: 'tengjia', label: '藤甲', suit: '♣', point: '2', sub: 'armor', slot: 'armor', range: 0),
  EquipDef(name: 'renwang', label: '仁王盾', suit: '♣', point: '2', sub: 'armor', slot: 'armor', range: 0),
  EquipDef(name: 'baiyin', label: '白银狮子', suit: '♣', point: 'A', sub: 'armor', slot: 'armor', range: 0),
];


const List<EquipDef> kHorses = <EquipDef>[
  EquipDef(name: 'jueying', label: '绝影', suit: '♠', point: '5', sub: 'horseP', slot: 'horseP', range: 0),
  EquipDef(name: 'dilu', label: '的卢', suit: '♣', point: '5', sub: 'horseP', slot: 'horseP', range: 0),
  EquipDef(name: 'hualiu', label: '骅骝', suit: '♦', point: 'K', sub: 'horseP', slot: 'horseP', range: 0),
  EquipDef(name: 'zhaohuang', label: '爪黄飞电', suit: '♥', point: 'K', sub: 'horseP', slot: 'horseP', range: 0),
  EquipDef(name: 'dawan', label: '大宛', suit: '♠', point: 'K', sub: 'horseM', slot: 'horseM', range: 0),
  EquipDef(name: 'chitu', label: '赤兔', suit: '♥', point: '5', sub: 'horseM', slot: 'horseM', range: 0),
  EquipDef(name: 'zixin', label: '紫骍', suit: '♦', point: 'K', sub: 'horseM', slot: 'horseM', range: 0),
];


// 展开校验: DEFS 135 + WEAPONS 12 + ARMORS 6 + HORSES 7 = 160 张
