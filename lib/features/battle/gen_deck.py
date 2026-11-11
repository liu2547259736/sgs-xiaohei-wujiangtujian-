#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 deck_data.dart —— 从主程序 battle.js 精确解析军争牌堆定义。

来源: sgs-heroes-app/battle.js 第 28~111 行的
      DEFS / WEAPONS / ARMORS / HORSES 四个 JS 数组字面量。
生成命令(在任意工作目录均可, 路径基于本脚本位置解析):
    python  lib/features/battle/gen_deck.py
    python3 lib/features/battle/gen_deck.py
    python  lib/features/battle/gen_deck.py "H:/AI/sgs-heroes/sgs-heroes-app/battle.js"  # 手动指定源
输出: 与本脚本同目录的 deck_data.dart。

说明: 四个数组都是纯字面量(字符串 / 整数 / 嵌套数组), 用方括号配平扫描截取后
      交给 ast.literal_eval 解析, 不做任何手写映射, 保证与主程序逐字一致。
      engine.buildDeck() 会把 points 点数数组展开成恰好 160 张。
"""
import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = os.path.normpath(os.path.join(
    HERE, '..', '..', '..', '..', '..', 'sgs-heroes-app', 'battle.js'))
OUT = os.path.join(HERE, 'deck_data.dart')


def extract_array(text, varname):
    """截取 `var NAME = [ ... ];` 中方括号配平的完整数组字面量。"""
    m = re.search(r'\bvar\s+' + re.escape(varname) + r'\s*=\s*', text)
    if not m:
        raise RuntimeError('未找到数组 var %s' % varname)
    i = m.end()
    if i >= len(text) or text[i] != '[':
        raise RuntimeError('%s 不是数组字面量' % varname)
    depth = 0
    j = i
    in_str = False
    quote = ''
    while j < len(text):
        ch = text[j]
        if in_str:
            if ch == '\\':
                j += 2
                continue
            if ch == quote:
                in_str = False
        else:
            if ch in "'\"":
                in_str = True
                quote = ch
            elif ch == '[':
                depth += 1
            elif ch == ']':
                depth -= 1
                if depth == 0:
                    return text[i:j + 1]
        j += 1
    raise RuntimeError('%s 方括号未配平' % varname)


def q(s):
    """转成 Dart 单引号字符串字面量。"""
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'") + "'"


def opt(v):
    return 'null' if v is None else q(v)


HEADER = '''// 由 gen_deck.py 从主程序 battle.js 精确解析生成，请勿手改。
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

'''


def gen_defs(defs):
    lines = ['const List<CardDef> kDefs = <CardDef>[']
    for d in defs:
        label, name, suit, points, kind = d[0], d[1], d[2], d[3], d[4]
        # 主程序: var sub = d[5] || (d[1] === 'sha' ? 'n' : null);
        sub = d[5] if len(d) > 5 else None
        if not sub:
            sub = 'n' if name == 'sha' else None
        element = d[6] if len(d) > 6 else None
        pts = ', '.join(q(p) for p in points)
        lines.append(
            '  CardDef(name: %s, label: %s, suit: %s, points: <String>[%s], '
            'kindCode: %s, sub: %s, element: %s),' %
            (q(name), q(label), q(suit), pts, q(kind), opt(sub), opt(element)))
    lines.append('];')
    return '\n'.join(lines)


def gen_equips(var_name, items, kind):
    lines = ['const List<EquipDef> %s = <EquipDef>[' % var_name]
    for it in items:
        label, key, suit, point = it[0], it[1], it[2], it[3]
        if kind == 'weapon':
            sub, slot, rng = 'weapon', 'weapon', it[4]
        elif kind == 'armor':
            sub, slot, rng = 'armor', 'armor', 0
        else:  # horse
            sub = slot = it[4]
            rng = 0
        lines.append(
            '  EquipDef(name: %s, label: %s, suit: %s, point: %s, '
            'sub: %s, slot: %s, range: %d),' %
            (q(key), q(label), q(suit), q(point), q(sub), q(slot), rng))
    lines.append('];')
    return '\n'.join(lines)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    with open(src, 'r', encoding='utf-8') as f:
        text = f.read()

    defs = ast.literal_eval(extract_array(text, 'DEFS'))
    weapons = ast.literal_eval(extract_array(text, 'WEAPONS'))
    armors = ast.literal_eval(extract_array(text, 'ARMORS'))
    horses = ast.literal_eval(extract_array(text, 'HORSES'))

    def_count = sum(len(d[3]) for d in defs)
    total = def_count + len(weapons) + len(armors) + len(horses)
    assert total == 160, '展开后应为 160 张，实际 %d' % total

    out = [
        HEADER,
        gen_defs(defs), '\n',
        gen_equips('kWeapons', weapons, 'weapon'), '\n',
        gen_equips('kArmors', armors, 'armor'), '\n',
        gen_equips('kHorses', horses, 'horse'), '\n',
        "// 展开校验: DEFS %d + WEAPONS %d + ARMORS %d + HORSES %d = %d 张\n" %
        (def_count, len(weapons), len(armors), len(horses), total),
    ]
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))

    print('来源: %s' % src)
    print('输出: %s' % OUT)
    print('展开校验: DEFS=%d + WEAPONS=%d + ARMORS=%d + HORSES=%d = %d 张 OK' %
          (def_count, len(weapons), len(armors), len(horses), total))


if __name__ == '__main__':
    main()
