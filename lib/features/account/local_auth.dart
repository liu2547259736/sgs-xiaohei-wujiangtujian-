// 本地账号服务 —— 从主程序 services/localAuth.js 迁移。
//
// 存储键与主程序保持一致（sgs_local_users / sgs_current_session），密码摘要
// 复刻它的 salted FNV-1a（l1s:<salt>:<hex>），因此**主程序导出的备份能直接
// 导入并照常登录**，本端导出的备份也能被主程序读。
//
// 这是单机「不明文落盘」的摘要，不是加密，只适用于本地场景。
// 数据隔离沿用 scopeKey：游客用原键，登录态用 <base>@<userId>。
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kUsersKey = 'sgs_local_users';
const String kSessionKey = 'sgs_current_session';
const String kScopeSep = '@';

class LocalUser {
  const LocalUser({
    required this.id,
    required this.username,
    required this.password,
    required this.nickname,
    required this.avatar,
    required this.createdAt,
    required this.updatedAt,
    this.userData = const <String, dynamic>{},
  });

  final String id;
  final String username;
  final String password;
  final String nickname;
  final String avatar;
  final String createdAt;
  final String updatedAt;
  final Map<String, dynamic> userData;

  String get displayName =>
      nickname.trim().isEmpty ? username : nickname.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'password': password,
        'nickname': nickname,
        'avatar': avatar,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'userData': userData,
      };

  factory LocalUser.fromJson(Map<String, dynamic> j) => LocalUser(
        id: _s(j['id']),
        username: _s(j['username']),
        password: _s(j['password']),
        nickname: _s(j['nickname']),
        avatar: _s(j['avatar']).isEmpty ? 'avatar_default.webp' : _s(j['avatar']),
        createdAt: _s(j['createdAt']),
        updatedAt: _s(j['updatedAt']),
        userData: j['userData'] is Map
            ? Map<String, dynamic>.from(j['userData'] as Map)
            : <String, dynamic>{},
      );

  LocalUser copyWith({
    String? nickname,
    String? avatar,
    String? password,
    String? updatedAt,
    Map<String, dynamic>? userData,
  }) =>
      LocalUser(
        id: id,
        username: username,
        password: password ?? this.password,
        nickname: nickname ?? this.nickname,
        avatar: avatar ?? this.avatar,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        userData: userData ?? this.userData,
      );

  static String _s(dynamic v) => v == null ? '' : v.toString();
}

class AuthResult {
  const AuthResult({required this.ok, this.user, this.error, this.added = 0,
    this.updated = 0, this.total = 0});

  final bool ok;
  final LocalUser? user;
  final String? error;
  final int added;
  final int updated;
  final int total;
}

class LocalAuthService extends ChangeNotifier {
  LocalAuthService({SharedPreferences? prefs}) {
    _prefs = prefs;
  }

  SharedPreferences? _prefs;
  List<LocalUser> _users = <LocalUser>[];
  String? _sessionId;
  bool _ready = false;

  bool get isReady => _ready;
  LocalUser? get currentUser {
    if (_sessionId == null) return null;
    for (final u in _users) {
      if (u.id == _sessionId) return u;
    }
    return null;
  }
  List<LocalUser> get users => List<LocalUser>.unmodifiable(_users);

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  static int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h ^= unit;
      h = (h +
              ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) &
          0xFFFFFFFF;
    }
    return h;
  }

  static String hash(String password) {
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final rnd = Random();
    final salt =
        List<int>.generate(6, (_) => rnd.nextInt(36)).map((i) => chars[i]).join();
    final hex = _fnv('$salt::$password').toRadixString(16).padLeft(8, '0');
    return 'l1s:$salt:$hex';
  }

  static bool verify(String password, String stored) {
    final parts = stored.split(':');
    if (parts.length != 3 || parts[0] != 'l1s') return false;
    final hex = _fnv('${parts[1]}::$password').toRadixString(16).padLeft(8, '0');
    return hex == parts[2].toLowerCase();
  }

  String _now() => DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');

  Future<void> init() async {
    if (_ready) return;
    final p = _prefs ??= await SharedPreferences.getInstance();
    final raw = p.getString(kUsersKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _users = list
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => LocalUser.fromJson(Map<String, dynamic>.from(e)))
            .where((u) => u.username.isNotEmpty)
            .toList();
      } catch (_) {
        _users = <LocalUser>[];
      }
    }
    final session = p.getString(kSessionKey);
    if (session != null) {
      try {
        _sessionId = _s((jsonDecode(session) as Map)['id']);
      } catch (_) {
        _sessionId = session;
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = _prefs!;
    await p.setString(
        kUsersKey, jsonEncode(_users.map((u) => u.toJson()).toList()));
    if (_sessionId == null) {
      await p.remove(kSessionKey);
    } else {
      await p.setString(
          kSessionKey, jsonEncode(<String, String>{'id': _sessionId!}));
    }
    notifyListeners();
  }

  Future<AuthResult> register(String username, String password, {String nickname = ''}) async {
    final name = _s(username);
    if (name.length < 2) return const AuthResult(ok: false, error: '账号至少 2 个字符');
    if (password.length < 4) return const AuthResult(ok: false, error: '密码至少 4 位');
    if (_users.any((u) => u.username.toLowerCase() == name.toLowerCase())) {
      return const AuthResult(ok: false, error: '该账号已存在');
    }
    final now = _now();
    final user = LocalUser(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      username: name,
      password: hash(password),
      nickname: _s(nickname).isEmpty ? name : _s(nickname),
      avatar: 'avatar_default.webp',
      createdAt: now,
      updatedAt: now,
    );
    _users = <LocalUser>[..._users, user];
    _sessionId = user.id;
    await _persist();
    return AuthResult(ok: true, user: user);
  }

  Future<AuthResult> login(String username, String password) async {
    final name = _s(username).toLowerCase();
    for (final u in _users) {
      if (u.username.toLowerCase() == name && verify(password, u.password)) {
        _sessionId = u.id;
        await _persist();
        return AuthResult(ok: true, user: u);
      }
    }
    return const AuthResult(ok: false, error: '账号或密码不正确');
  }

  Future<void> logout() async {
    _sessionId = null;
    await _persist();
  }

  /// 本地单机便利功能：已有账号之间直接切换会话，不重复输密码。
  /// 数据仍按 userId 隔离，不会串号。
  Future<void> selectUser(String id) async {
    if (!_users.any((u) => u.id == id)) return;
    _sessionId = id;
    await _persist();
  }

  Future<AuthResult> updateUser(String id, {String? nickname, String? password}) async {
    final idx = _users.indexWhere((u) => u.id == id);
    if (idx < 0) return const AuthResult(ok: false, error: '账号不存在');
    final u = _users[idx];
    final updated = u.copyWith(
      nickname: nickname == null ? null : _s(nickname),
      password: password == null ? null : hash(password),
      updatedAt: _now(),
    );
    _users = <LocalUser>[..._users]..[idx] = updated;
    await _persist();
    return AuthResult(ok: true, user: updated);
  }

  Future<void> removeUser(String id) async {
    _users = _users.where((u) => u.id != id).toList();
    if (_sessionId == id) _sessionId = null;
    // 连带清掉该账号的隔离命名空间
    for (final key in _prefs!.getKeys().toList()) {
      if (key.contains('$kScopeSep$id')) _prefs!.remove(key);
    }
    await _persist();
  }

  /// 业务数据键：游客用原键，登录态按账号隔离，绝不串号。
  String scopeKey(String base) =>
      _sessionId == null ? base : '$base$kScopeSep$_sessionId';

  List<String> loadList(String base) =>
      _prefs?.getStringList(scopeKey(base)) ?? const <String>[];

  Future<void> saveList(String base, List<String> values) async {
    await _prefs!.setStringList(scopeKey(base), values);
  }

  Map<String, String> loadMap(String base) {
    final raw = _prefs?.getString(scopeKey(base));
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> saveMap(String base, Map<String, String> values) async {
    await _prefs!.setString(scopeKey(base), jsonEncode(values));
  }

  /// 导出：把各账号隔离空间里的收藏 / 历史 / 心得 / 设置一并打包，
  /// 格式与主程序 buildBackup() 对齐，可直接互相导入。
  String exportData() {
    final users = _users.map((u) {
      final id = u.id;
      final pack = <String, dynamic>{
        'favorites': _readScoped('sgs_favorites', id, asList: true),
        'history': _readScoped('sgs_history', id, asList: true),
        'notes': _readScoped('sgs_notes', id, asList: false),
        'settings': _readScoped('sgs_settings', id, asList: false),
      };
      return <String, dynamic>{...u.toJson(), 'userData': pack};
    }).toList();
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'app': 'sgs-heroes',
      'type': 'local-auth-backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': users.length,
      'users': users,
    });
  }

  dynamic _readScoped(String base, String id, {required bool asList}) {
    final key = '$base$kScopeSep$id';
    if (asList) return _prefs?.getStringList(key) ?? <String>[];
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<AuthResult> importData(String text, {String mode = 'merge'}) async {
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      return const AuthResult(ok: false, error: '备份文件不是合法 JSON');
    }
    List<dynamic> incoming;
    if (parsed is List) {
      incoming = parsed;
    } else if (parsed is Map && parsed['users'] is List) {
      incoming = parsed['users'] as List<dynamic>;
    } else {
      return const AuthResult(ok: false, error: '备份里没有账号数据');
    }
    if (incoming.isEmpty) return const AuthResult(ok: false, error: '备份里没有账号数据');

    final list = mode == 'replace' ? <LocalUser>[] : List<LocalUser>.from(_users);
    var added = 0;
    var updated = 0;
    for (final raw in incoming) {
      if (raw is! Map) continue;
      final j = Map<String, dynamic>.from(raw);
      final name = _s(j['username']);
      if (name.isEmpty) continue;
      final idx = list.indexWhere(
          (u) => u.username.toLowerCase() == name.toLowerCase());
      final storedPassword = _s(j['password']).isEmpty
          ? hash('imported_${Random().nextInt(1 << 32)}')
          : _s(j['password']);
      final base = LocalUser.fromJson(j);
      final user = LocalUser(
        id: idx >= 0 ? list[idx].id : (base.id.isEmpty
            ? 'user_${DateTime.now().microsecondsSinceEpoch}_$added'
            : base.id),
        username: name,
        password: idx >= 0 ? list[idx].password : storedPassword,
        nickname: base.nickname.isEmpty ? name : base.nickname,
        avatar: base.avatar,
        createdAt: base.createdAt.isEmpty ? _now() : base.createdAt,
        updatedAt: _now(),
        userData: base.userData,
      );
      if (idx >= 0) {
        list[idx] = user;
        updated++;
      } else {
        list.add(user);
        added++;
      }
      _writeUserData(user.id, base.userData, merge: mode != 'replace');
    }
    _users = list;
    await _persist();
    return AuthResult(
        ok: true, added: added, updated: updated, total: list.length);
  }

  void _writeUserData(String id, Map<String, dynamic> data,
      {required bool merge}) {
    final p = _prefs!;
    final favKey = 'sgs_favorites$kScopeSep$id';
    final hisKey = 'sgs_history$kScopeSep$id';
    final fav = _listOf(data['favorites']);
    final his = _listOf(data['history']);
    p.setStringList(favKey, merge
        ? <String>{...p.getStringList(favKey) ?? const <String>[], ...fav}.toList()
        : fav);
    p.setStringList(hisKey, merge
        ? <String>{...p.getStringList(hisKey) ?? const <String>[], ...his}.toList()
        : his);
    if (data['notes'] is Map) {
      p.setString('sgs_notes$kScopeSep$id', jsonEncode(data['notes']));
    }
    if (data['settings'] is Map) {
      p.setString('sgs_settings$kScopeSep$id', jsonEncode(data['settings']));
    }
  }

  static List<String> _listOf(dynamic v) => v is List
      ? v.map((e) => e.toString()).toList()
      : const <String>[];

  Future<void> clearAll() async {
    final keys = _prefs!.getKeys().toList();
    for (final k in keys) {
      if (k == kUsersKey || k == kSessionKey || k.contains(kScopeSep)) {
        _prefs!.remove(k);
      }
    }
    _users = <LocalUser>[];
    _sessionId = null;
    await _persist();
  }
}
