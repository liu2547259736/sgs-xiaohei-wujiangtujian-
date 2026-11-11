// 数据仓库读取层：只认 seed 里的 JSON，不碰网络。
//
// 设计要点：
//  1. 首屏只读 3 个文件（seed.json / heroes/index.json / search_index.json，约 2 MB），
//     全量卡片立刻能渲染；完整详情按版本懒加载分片，切到哪个版本才读哪个。
//  2. 分片清单从 seed.json 的 files[] 推导，不写死「11 个分片 / 每片 500 将」，
//     以后本体增删武将、改分片大小，App 一行都不用改。
//  3. 排序沿用主程序 ordKey() 的口径：g.ord 升序，缺省 1e9 排末尾。
import 'dart:convert';

import '../core/sync/data_file_source.dart';
import '../core/sync/update_protocol.dart';
import 'models.dart';

class AtlasData {
  const AtlasData({
    required this.seed,
    required this.versions,
    required this.heroes,
    required this.shardsByVersion,
  });

  final DataManifest seed;
  final List<VersionInfo> versions;
  final List<HeroSummary> heroes;
  final Map<String, List<String>> shardsByVersion;

  String get version => seed.version;
  int get heroCount => seed.counts['heroes'] ?? heroes.length;
  int get skinCount => seed.counts['skins'] ?? 0;

  List<String> levelsOf(String version) {
    final set = <String>{};
    for (final h in heroes) {
      if (h.version == version && h.level.isNotEmpty) set.add(h.level);
    }
    final list = set.toList()..sort();
    return list;
  }

  VersionInfo? versionOf(String id) {
    for (final v in versions) {
      if (v.id == id) return v;
    }
    return null;
  }
}

class _SearchMeta {
  const _SearchMeta(this.py, this.gender, this.title, this.skills);
  final String py;
  final String gender;
  final String title;
  final List<String> skills;
}

class HeroRepository {
  HeroRepository({this.source = const BundleOnlySource()});

  final DataFileSource source;
  AtlasData? _data;
  final Map<String, Map<String, HeroDetail>> _details =
      <String, Map<String, HeroDetail>>{};

  bool get isLoaded => _data != null;
  AtlasData get data => _data!;

  /// 更新落盘后调用：丢掉内存缓存重新读，让新分片 / 新头像立即生效。
  Future<AtlasData> reload() async {
    _data = null;
    _details.clear();
    return load();
  }

  /// 更新落盘后，远端 manifest 会覆盖随包的 seed.json 描述符，
  /// 让版本号、counts 和分片清单都跟着新版本走。
  Future<String> _seedDescriptor() async {
    if (source.hasOverride('manifest.json')) {
      try {
        return await readDataString(source, 'manifest.json');
      } catch (_) {}
    }
    return readDataString(source, 'seed.json');
  }

  Future<AtlasData> load() async {
    if (_data != null) return _data!;

    final results = await Future.wait<String>(<Future<String>>[
      _seedDescriptor(),
      readDataString(source, 'heroes/index.json'),
      readDataString(source, 'meta/search_index.json'),
    ]);

    final seed = DataManifest.fromJson(
        jsonDecode(results[0]) as Map<String, dynamic>);
    final index =
        (jsonDecode(results[1]) as Map<String, dynamic>)['data'] as Map;
    final search = jsonDecode(results[2]) as Map<String, dynamic>;

    // search_index.json 补拼音 / 技能名 / 性别 / 称号（主索引里没有）。
    final meta = <String, _SearchMeta>{};
    for (final raw in (search['items'] as List? ?? const <dynamic>[])) {
      final j = Map<String, dynamic>.from(raw as Map);
      final g = strOf(j['g']);
      meta['${strOf(j['v'])}|${strOf(j['id'])}'] = _SearchMeta(
        strOf(j['py']),
        g == 'm' ? 'male' : (g == 'f' ? 'female' : ''),
        strOf(j['t']),
        strListOf(j['sk']),
      );
    }

    final versions = mapListOf(index['versions'])
        .map(VersionInfo.fromJson)
        .toList(growable: false);

    final heroes = mapListOf(index['heroes']).map((j) {
      final h = HeroSummary.fromIndex(j);
      final m = meta[h.key];
      return m == null
          ? h
          : h.withSearchMeta(
              py: m.py,
              gender: m.gender,
              title: m.title,
              skillNames: m.skills,
            );
    }).toList();
    heroes.sort((a, b) {
      final c = a.ord.compareTo(b.ord);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

    // 分片清单来自 seed.json，数据驱动。
    final shards = <String, List<String>>{};
    for (final f in seed.files) {
      final p = f.path;
      if (!p.startsWith('heroes/') || p == 'heroes/index.json') continue;
      final name = p.substring('heroes/'.length);
      final dash = name.indexOf('-');
      if (dash <= 0) continue;
      final ver = name.substring(0, dash);
      shards.putIfAbsent(ver, () => <String>[]).add(p);
    }
    for (final list in shards.values) {
      list.sort();
    }

    return _data = AtlasData(
      seed: seed,
      versions: versions,
      heroes: List<HeroSummary>.unmodifiable(heroes),
      shardsByVersion: shards,
    );
  }

  /// 懒加载某版本的完整武将详情。已加载过则直接返回缓存。
  Future<Map<String, HeroDetail>> loadDetails(String version) async {
    final cached = _details[version];
    if (cached != null) return cached;
    final out = <String, HeroDetail>{};
    for (final path in data.shardsByVersion[version] ?? const <String>[]) {
      final raw = await readDataString(source, path);
      final j = (jsonDecode(raw) as Map<String, dynamic>)['data'] as Map;
      for (final item in (j['generals'] as List? ?? const <dynamic>[])) {
        final d = HeroDetail.fromJson(
            Map<String, dynamic>.from(item as Map), version);
        out[d.id] = d;
      }
    }
    return _details[version] = out;
  }

  HeroDetail? cachedDetail(String version, String id) =>
      _details[version]?[id];

  static bool isSubseq(String needle, String haystack) {
    if (needle.isEmpty) return true;
    var i = 0;
    for (final code in haystack.codeUnits) {
      if (code == needle.codeUnitAt(i)) i++;
      if (i == needle.length) return true;
    }
    return false;
  }

  /// 本地实时筛选。全部在内存里跑，全量数据无需额外索引或 isolate。
  List<HeroSummary> query({
    required String version,
    String kingdom = 'all',
    String pack = 'all',
    String level = 'all',
    String gender = 'all',
    String text = '',
  }) {
    final q = text.trim().toLowerCase();
    return data.heroes.where((h) {
      if (h.version != version) return false;
      if (kingdom != 'all' && h.kingdom != kingdom) return false;
      if (pack != 'all' && h.pack != pack) return false;
      if (level != 'all' && h.level != level) return false;
      if (gender != 'all' && h.gender != gender) return false;
      if (q.isEmpty) return true;
      if (h.searchKey.contains(q)) return true;
      return h.py.isNotEmpty && isSubseq(q, h.py);
    }).toList(growable: false);
  }
}
