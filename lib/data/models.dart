// 数据模型 + 字段归一化。
//
// 源数据 7 个版本有 6 类已知不一致（hp int|float、ord int|float、wr int|str、
// g 为 null、skn 整版缺失、ni/na 占位标记）。全部在这一层吃掉，UI 只见干净模型。
// 字段名维持 1~3 字母缩写，绝不重命名 —— v2/*.py 整套生成脚本依赖它们。
//
// 本文件只用 Dart 核心库，不引 Flutter / dart:io，六端都能编译、便于单测。

// ---------- 安全读取 ----------

double numOf(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

String strOf(dynamic v) => v == null ? '' : (v is String ? v : v.toString());

bool flagOf(dynamic v) =>
    v == true || v == 1 || (v is String && v.isNotEmpty && v != '0');

List<String> strListOf(dynamic v) {
  if (v is List) {
    return v.map(strOf).where((s) => s.isNotEmpty).toList(growable: false);
  }
  if (v is String && v.isNotEmpty) return <String>[v];
  return const <String>[];
}

List<Map<String, dynamic>> mapListOf(dynamic v) {
  if (v is! List) return const <Map<String, dynamic>>[];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

/// q 的 value 可能是 String，也可能是 `List<String>`。
Map<String, String> quoteMapOf(dynamic v) {
  if (v is! Map) return const <String, String>{};
  return v.map((k, value) => MapEntry(
        strOf(k),
        value is List ? value.map(strOf).join(' / ') : strOf(value),
      ));
}

// ---------- 势力（配色沿用主程序 app.js 的 KC，保证视觉一致） ----------

const Map<String, int> kKingdomArgb = <String, int>{
  'wei': 0xFF3D599B,
  'shu': 0xFFAD362D,
  'wu': 0xFF42752B,
  'qun': 0xFF88857E,
  'jin': 0xFF6D4F9D,
  'god': 0xFFA4803B,
};

const Map<String, String> kKingdomLabel = <String, String>{
  'all': '全部',
  'wei': '魏',
  'shu': '蜀',
  'wu': '吴',
  'qun': '群',
  'jin': '晋',
  'god': '神',
};

const List<String> kKingdomOrder = <String>[
  'all', 'wei', 'shu', 'wu', 'qun', 'jin', 'god',
];

// ---------- 版本 / 包 ----------

class PackInfo {
  const PackInfo({
    required this.id,
    required this.label,
    required this.count,
    this.children = const <PackInfo>[],
  });

  final String id;
  final String label;
  final int count;
  final List<PackInfo> children;

  factory PackInfo.fromJson(Map<String, dynamic> j) => PackInfo(
        id: strOf(j['id']),
        label: strOf(j['label']),
        count: numOf(j['count']).toInt(),
        children: mapListOf(j['children'])
            .map(PackInfo.fromJson)
            .toList(growable: false),
      );
}

class VersionInfo {
  const VersionInfo({
    required this.id,
    required this.short,
    required this.label,
    required this.source,
    required this.count,
    this.packs = const <PackInfo>[],
  });

  final String id;
  final String short;
  final String label;
  final String source;
  final int count;
  final List<PackInfo> packs;

  factory VersionInfo.fromJson(Map<String, dynamic> j) => VersionInfo(
        id: strOf(j['id']),
        short: strOf(j['short']),
        label: strOf(j['label']),
        source: strOf(j['source']),
        count: numOf(j['count']).toInt(),
        packs: mapListOf(j['packs'])
            .map(PackInfo.fromJson)
            .toList(growable: false),
      );
}

// ---------- 列表用的轻量武将（来自 heroes/index.json + search_index.json） ----------

class HeroSummary {
  const HeroSummary({
    required this.version,
    required this.id,
    required this.name,
    required this.kingdom,
    required this.hp,
    required this.level,
    required this.pack,
    required this.ord,
    required this.img,
    required this.avatar,
    this.py = '',
    this.gender = '',
    this.title = '',
    this.skillNames = const <String>[],
  });

  final String version;
  final String id;
  final String name;
  final String kingdom;
  final double hp;
  final String level;
  final String pack;
  final double ord;
  final String img;
  final String avatar;
  final String py;
  final String gender;
  final String title;
  final List<String> skillNames;

  String get key => '$version|$id';

  /// 姓名 + 拼音 + 技能名 + 称号，供本地实时搜索用。
  String get searchKey =>
      '$name $title $py ${skillNames.join(' ')}'.toLowerCase();

  String get hpText =>
      hp == hp.roundToDouble() ? hp.toInt().toString() : hp.toString();

  factory HeroSummary.fromIndex(Map<String, dynamic> j) => HeroSummary(
        version: strOf(j['v']),
        id: strOf(j['id']),
        name: strOf(j['n']),
        kingdom: strOf(j['k']),
        hp: numOf(j['hp']),
        level: strOf(j['lv']),
        pack: strOf(j['p']),
        ord: numOf(j['ord'], 1e9),
        img: strOf(j['img']),
        avatar: strOf(j['av']),
      );

  HeroSummary withSearchMeta({
    String? py,
    String? gender,
    String? title,
    List<String>? skillNames,
  }) =>
      HeroSummary(
        version: version,
        id: id,
        name: name,
        kingdom: kingdom,
        hp: hp,
        level: level,
        pack: pack,
        ord: ord,
        img: img,
        avatar: avatar,
        py: py ?? this.py,
        gender: gender ?? this.gender,
        title: title ?? this.title,
        skillNames: skillNames ?? this.skillNames,
      );
}

// ---------- 详情 ----------

class Skill {
  const Skill({
    required this.name,
    required this.type,
    required this.description,
    this.oneSentence = '',
  });

  final String name;
  final String type;
  final String description;
  final String oneSentence;

  factory Skill.fromJson(Map<String, dynamic> j) => Skill(
        name: strOf(j['name']),
        type: strOf(j['type']),
        description: strOf(j['description']),
        oneSentence: strOf(j['oneSentenceDesc']),
      );
}

class SkinInfo {
  const SkinInfo({required this.name, required this.painter, required this.img});

  final String name;
  final String painter;
  final String img;

  factory SkinInfo.fromJson(Map<String, dynamic> j) => SkinInfo(
        name: strOf(j['n']),
        painter: strOf(j['painter']),
        img: strOf(j['img']),
      );
}

class HeroDetail {
  const HeroDetail({
    required this.version,
    required this.id,
    required this.name,
    required this.title,
    required this.kingdom,
    required this.gender,
    required this.pack,
    required this.hp,
    required this.hp0,
    required this.ord,
    required this.img,
    required this.avatar,
    required this.level,
    required this.group,
    required this.bio,
    required this.footnote,
    required this.quoteSource,
    required this.subPack,
    required this.skills,
    required this.tags,
    required this.otherTags,
    required this.quotes,
    required this.voiceLines,
    required this.achievements,
    required this.skins,
    required this.skinPaths,
    required this.noImage,
    required this.noAvatar,
  });

  final String version;
  final String id;
  final String name;
  final String title;
  final String kingdom;
  final String gender;
  final String pack;
  final double hp;
  final double hp0;
  final double ord;
  final String img;
  final String avatar;
  final String level;
  final String group;
  final String bio;
  final String footnote;
  final String quoteSource;
  final String subPack;
  final List<Skill> skills;
  final List<String> tags;
  final List<String> otherTags;
  final Map<String, String> quotes;
  final List<String> voiceLines;
  final List<String> achievements;
  final List<SkinInfo> skins;
  final List<String> skinPaths;
  final bool noImage;
  final bool noAvatar;

  String get hpText =>
      hp == hp.roundToDouble() ? hp.toInt().toString() : hp.toString();

  factory HeroDetail.fromJson(Map<String, dynamic> j, String version) {
    final tg = j['tg'] is Map
        ? Map<String, dynamic>.from(j['tg'] as Map)
        : const <String, dynamic>{};
    final roles = strListOf(tg['roles']);
    final lines = <String>[];
    for (final group in mapListOf(j['olv'])) {
      for (final item in mapListOf(group['items'])) {
        final kind = strOf(item['k']);
        for (final line in strListOf(item['lines'])) {
          if (lines.length < 16) lines.add('$kind：$line');
        }
      }
    }
    final skinPaths = strListOf(j['sk']);
    final skins = mapListOf(j['skn'])
        .map(SkinInfo.fromJson)
        .toList(growable: false);
    return HeroDetail(
      version: version,
      id: strOf(j['id']),
      name: strOf(j['n']),
      title: strOf(j['t']),
      kingdom: strOf(j['k']),
      gender: strOf(j['g']),
      pack: strOf(j['p']),
      hp: numOf(j['hp']),
      hp0: numOf(j['hp0']),
      ord: numOf(j['ord'], 1e9),
      img: strOf(j['img']),
      avatar: strOf(j['av']),
      level: strOf(j['lv']),
      group: strOf(j['gr']),
      bio: strOf(j['bio']),
      footnote: strOf(j['ft']),
      quoteSource: strOf(j['qs']),
      subPack: strOf(j['sp']),
      skills: mapListOf(j['s']).map(Skill.fromJson).toList(growable: false),
      tags: roles,
      otherTags: strListOf(j['ot']),
      quotes: quoteMapOf(j['q']),
      voiceLines: lines,
      achievements: strListOf(j['gw']),
      skins: skins,
      skinPaths: skinPaths,
      noImage: flagOf(j['ni']),
      noAvatar: flagOf(j['na']),
    );
  }
}
