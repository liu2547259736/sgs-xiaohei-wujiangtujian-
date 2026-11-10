// 字段归一化测试：源数据 7 个版本的 6 类不一致必须在 Repository 层被吃掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/data/hero_repository.dart';
import 'package:sgs_heroes/data/models.dart';

void main() {
  group('字段归一化', () {
    test('hp / ord 接受 int、float、字符串与缺字段', () {
      expect(numOf(4), 4);
      expect(numOf(4.5), 4.5);
      expect(numOf('3'), 3);
      expect(numOf(null), 0);
      expect(numOf('x', 1e9), 1e9);
    });

    test('g 为 null 时降级成空串', () {
      expect(strOf(null), '');
      expect(strOf('male'), 'male');
    });

    test('q 的 value 可能是 String 也可能是 List<String>', () {
      final m = quoteMapOf(<String, dynamic>{
        '阵亡': <String>['什么？此地名叫麦城', '可惜'],
        '武圣': '看尔乃插标卖首',
      });
      expect(m['阵亡'], '什么？此地名叫麦城 / 可惜');
      expect(m['武圣'], '看尔乃插标卖首');
    });

    test('ni / na 占位标记多种写法都能识别', () {
      expect(flagOf(1), isTrue);
      expect(flagOf(true), isTrue);
      expect(flagOf('3.0.22'), isTrue);
      expect(flagOf(null), isFalse);
      expect(flagOf(0), isFalse);
      expect(flagOf('0'), isFalse);
    });

    test('skn 整版缺失 / g 为 null 时详情解析不炸', () {
      final d = HeroDetail.fromJson(<String, dynamic>{
        'id': 'x',
        'n': '测试',
        'hp': 4.5,
        'g': null,
        'skn': null,
        'sk': <String>[],
        'q': <String, dynamic>{},
      }, 'sgs');
      expect(d.skins, isEmpty);
      expect(d.skinPaths, isEmpty);
      expect(d.gender, '');
      expect(d.hpText, '4.5');
      expect(d.noImage, isFalse);
    });

    test('真实结构的技能 / 皮肤 / 台词能解析', () {
      final d = HeroDetail.fromJson(<String, dynamic>{
        'id': 'std_guanyu',
        'n': '关羽',
        't': '美髯公',
        'k': 'shu',
        'hp': 4,
        's': <Map<String, dynamic>>[
          {
            'name': '武圣',
            'type': 'active',
            'description': '你可以将一张红色牌当【杀】使用。',
            'oneSentenceDesc': ''
          }
        ],
        'sk': <String>['images/sgsol/sk/a.webp'],
        'skn': <Map<String, dynamic>>[
          {'n': '义薄云天', 'painter': '', 'img': 'images/sgsol/sk/a.webp'}
        ],
        'q': <String, dynamic>{'阵亡': '什么？此地名叫麦城。'},
        'olv': <Map<String, dynamic>>[
          {
            'grp': '经典形象',
            'items': <Map<String, dynamic>>[
              {
                'k': '武圣',
                'lines': <String>['关羽在此', '看尔乃插标卖首']
              }
            ]
          }
        ],
      }, 'sgsol');
      expect(d.skills.single.name, '武圣');
      expect(d.skins.single.name, '义薄云天');
      expect(d.skinPaths.length, 1);
      expect(d.quotes['阵亡'], '什么？此地名叫麦城。');
      expect(d.voiceLines.length, 2);
      expect(d.hpText, '4');
    });
  });

  group('本地搜索', () {
    test('拼音缩写子序列匹配（主程序 isSubseq 口径）', () {
      expect(HeroRepository.isSubseq('gy', 'guanyu'), isTrue);
      expect(HeroRepository.isSubseq('gy', 'GUANYU'), isFalse);
      expect(HeroRepository.isSubseq('zz', 'guanyu'), isFalse);
      expect(HeroRepository.isSubseq('', 'guanyu'), isTrue);
    });

    test('HeroSummary.searchKey 覆盖姓名 / 称号 / 拼音 / 技能', () {
      const h = HeroSummary(
        version: 'sgsol',
        id: 'std_guanyu',
        name: '关羽',
        kingdom: 'shu',
        hp: 4,
        level: '普通',
        pack: 'std',
        ord: 0,
        img: '',
        avatar: '',
        py: 'guanyu',
        title: '美髯公',
        skillNames: <String>['武圣'],
      );
      expect(h.searchKey.contains('关羽'), isTrue);
      expect(h.searchKey.contains('guanyu'), isTrue);
      expect(h.searchKey.contains('武圣'), isTrue);
      expect(h.key, 'sgsol|std_guanyu');
    });
  });
}
