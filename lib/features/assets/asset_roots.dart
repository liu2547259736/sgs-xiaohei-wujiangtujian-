// 皮肤大图 / 语音资源的「资源根」配置。
//
// 设计约束：皮肤 12901 张（706 MB）、语音 26556 个（1621 MB）按既定规则
// **不进 git、不随包、不在 CDN 数据仓库里**。所以 Flutter 端不能凭空显示它们，
// 这里给用户一个可配置的资源根：填了就能真加载/真播放，没填就明确标注
// 「资源未托管」，不写假图、不放哑按钮。
//
// 资源根可以是任意 http(s) 前缀（对象存储 / 自建静态站 / 本机起的静态服务），
// 路径按主程序规则原样拼接，方便直接把主程序的 images/ 目录挂上去：
//   皮肤：<base>/images/<ver>/sk/104.webp
//   语音：<base>/images/<ver>/voice/<clipId>.ogg|mp3
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kSkinBaseKey = 'sgs_asset_skin_base';
const String kVoiceBaseKey = 'sgs_asset_voice_base';

class AssetRoots extends ChangeNotifier {
  AssetRoots({SharedPreferences? prefs}) {
    _prefs = prefs;
  }

  SharedPreferences? _prefs;
  String _skinBase = '';
  String _voiceBase = '';
  bool _ready = false;

  bool get isReady => _ready;
  String get skinBase => _skinBase;
  String get voiceBase => _voiceBase;
  bool get hasSkinSource => _skinBase.isNotEmpty;
  bool get hasVoiceSource => _voiceBase.isNotEmpty;

  Future<void> init() async {
    if (_ready) return;
    final p = _prefs ??= await SharedPreferences.getInstance();
    _skinBase = p.getString(kSkinBaseKey) ?? '';
    _voiceBase = p.getString(kVoiceBaseKey) ?? '';
    _ready = true;
    notifyListeners();
  }

  Future<void> setSkinBase(String value) async {
    _skinBase = value.trim();
    await _prefs!.setString(kSkinBaseKey, _skinBase);
    notifyListeners();
  }

  Future<void> setVoiceBase(String value) async {
    _voiceBase = value.trim();
    await _prefs!.setString(kVoiceBaseKey, _voiceBase);
    notifyListeners();
  }

  static String _join(String base, String rel) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final r = rel.startsWith('/') ? rel.substring(1) : rel;
    return '$b/$r';
  }

  /// 皮肤图完整 URL；未配置时返回 null，调用方应显示占位与说明。
  String? skinUrl(String relPath) {
    if (!hasSkinSource || relPath.isEmpty) return null;
    return _join(_skinBase, relPath);
  }

  /// 主程序规则：sgsol 语音是 .ogg，msgs 是 .mp3，其它版本没有官方语音包。
  String? voiceUrl(String version, String clipId) {
    if (!hasVoiceSource || clipId.isEmpty) return null;
    final ext = switch (version) {
      'sgsol' => 'ogg',
      'msgs' => 'mp3',
      _ => null,
    };
    if (ext == null) return null;
    return _join(_voiceBase, 'images/$version/voice/$clipId.$ext');
  }
}
