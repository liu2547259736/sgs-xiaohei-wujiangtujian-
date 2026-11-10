// 全局状态：版本 / 筛选 / 搜索 / 主题 / 收藏 / 更新状态。
//
// 只用 Flutter 自带的 ChangeNotifier，不引状态管理框架，六端零差异。
// 收藏目前是会话内内存态；接 shared_preferences 持久化放在后面，不影响 UI 契约。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/env.dart';
import '../core/sync/git_update_service.dart';
import '../core/sync/in_memory_update_sink.dart';
import '../core/sync/update_protocol.dart';
import 'hero_repository.dart';
import 'models.dart';

enum AtlasStatus { loading, ready, error }

class AtlasController extends ChangeNotifier {
  AtlasController({HeroRepository? repository})
      : _repo = repository ?? HeroRepository();

  final HeroRepository _repo;
  final InMemoryUpdateSink _sink = InMemoryUpdateSink();

  AtlasStatus status = AtlasStatus.loading;
  String? errorMessage;

  String selectedVersion = '';
  String kingdom = 'all';
  String pack = 'all';
  String level = 'all';
  String gender = 'all';
  String search = '';
  ThemeMode themeMode = ThemeMode.system;

  final Set<String> favorites = <String>{};
  UpdateResult? updateResult;
  bool checkingUpdate = false;

  List<HeroSummary>? _visible;

  AtlasData get data => _repo.data;
  List<VersionInfo> get versions => _repo.data.versions;
  String get dataVersion => _repo.data.version;
  int get heroCount => _repo.data.heroCount;
  int get skinCount => _repo.data.skinCount;

  List<PackInfo> get currentPacks =>
      _repo.data.versionOf(selectedVersion)?.packs ?? const <PackInfo>[];
  List<String> get currentLevels => _repo.data.levelsOf(selectedVersion);

  List<HeroSummary> get visibleHeroes => _visible ??= _repo.query(
        version: selectedVersion,
        kingdom: kingdom,
        pack: pack,
        level: level,
        gender: gender,
        text: search,
      );

  Future<void> init() async {
    try {
      await _repo.load();
      selectedVersion =
          _repo.data.versions.isEmpty ? '' : _repo.data.versions.first.id;
      _visible = null;
      status = AtlasStatus.ready;
    } catch (e) {
      errorMessage = '$e';
      status = AtlasStatus.error;
    }
    notifyListeners();
    if (status == AtlasStatus.ready) {
      // 后台预载当前版本详情，打开抽屉时不会再有等待。
      await _repo.loadDetails(selectedVersion);
    }
  }

  void _invalidate() {
    _visible = null;
    notifyListeners();
  }

  void selectVersion(String v) {
    if (v == selectedVersion) return;
    selectedVersion = v;
    pack = 'all'; // 一级包是版本私有的，切版本必须重置
    level = 'all';
    _invalidate();
    _repo.loadDetails(v);
  }

  void setKingdom(String v) {
    kingdom = v;
    _invalidate();
  }

  void setPack(String v) {
    pack = v;
    _invalidate();
  }

  void setLevel(String v) {
    level = v;
    _invalidate();
  }

  void setGender(String v) {
    gender = v;
    _invalidate();
  }

  void setSearch(String v) {
    if (v == search) return;
    search = v;
    _invalidate();
  }

  void clearFilters() {
    kingdom = 'all';
    pack = 'all';
    level = 'all';
    gender = 'all';
    search = '';
    _invalidate();
  }

  bool get hasFilters =>
      kingdom != 'all' ||
      pack != 'all' ||
      level != 'all' ||
      gender != 'all' ||
      search.isNotEmpty;

  void toggleTheme() {
    themeMode = switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    notifyListeners();
  }

  bool isFavorite(String key) => favorites.contains(key);

  void toggleFavorite(String key) {
    if (!favorites.remove(key)) favorites.add(key);
    notifyListeners();
  }

  Future<HeroDetail> detailOf(HeroSummary h) async {
    final map = await _repo.loadDetails(h.version);
    final d = map[h.id];
    if (d != null) return d;
    // 极端情况：分片与索引不同步，用索引字段兜一个最小详情，绝不白屏。
    return HeroDetail(
      version: h.version,
      id: h.id,
      name: h.name,
      title: h.title,
      kingdom: h.kingdom,
      gender: h.gender,
      pack: h.pack,
      hp: h.hp,
      hp0: h.hp,
      ord: h.ord,
      img: h.img,
      avatar: h.avatar,
      level: h.level,
      group: '',
      bio: '',
      footnote: '',
      quoteSource: '',
      subPack: '',
      skills: const <Skill>[],
      tags: const <String>[],
      otherTags: const <String>[],
      quotes: const <String, String>{},
      voiceLines: const <String>[],
      achievements: const <String>[],
      skins: const <SkinInfo>[],
      skinPaths: const <String>[],
      noImage: false,
      noAvatar: false,
    );
  }

  /// 接上 GitUpdateService：拉远端 manifest → 比 version → 报告待更新文件数。
  /// 第一版固定 dryRun（只检查不落盘）：持久化 sink 与图片策略还没接，
  /// 真下载下来也没有地方用。填了 Env.githubRepo 后这一条即刻生效。
  Future<void> checkUpdate() async {
    if (status != AtlasStatus.ready) return;
    if (!Env.hasRemote) {
      updateResult = UpdateResult(
        status: UpdateStatus.offline,
        version: dataVersion,
        message: Env.notConfigured,
      );
      notifyListeners();
      return;
    }
    checkingUpdate = true;
    notifyListeners();
    final service = GitUpdateService(
      baseUrls: Env.dataBaseUrls(dataVersion),
      sink: _sink,
      requestTimeout: const Duration(seconds: 8),
    );
    try {
      updateResult = await service.checkAndApply(seed: data.seed, dryRun: true);
    } catch (e) {
      updateResult = UpdateResult(
        status: UpdateStatus.invalidManifest,
        version: dataVersion,
        message: '$e',
      );
    } finally {
      service.dispose();
      checkingUpdate = false;
      notifyListeners();
    }
  }

  String get updateSummary {
    final r = updateResult;
    if (r == null) return '数据 $dataVersion';
    if (r.status == UpdateStatus.offline &&
        r.message == Env.notConfigured) {
      return '离线数据 $dataVersion';
    }
    return r.display;
  }
}
