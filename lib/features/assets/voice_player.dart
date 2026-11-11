// 语音播放器：只在配置了语音资源根时才真的能播。
// audioplayers 的 UrlSource 同时支持 http(s) 与 Web 相对地址。
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class VoicePlayer extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  String? _playingUrl;
  String? _error;

  String? get playingUrl => _playingUrl;
  String? get error => _error;
  bool get isPlaying => _playingUrl != null;

  Future<void> toggle(String url) async {
    if (_playingUrl == url) {
      await stop();
      return;
    }
    await play(url);
  }

  Future<void> play(String url) async {
    _error = null;
    try {
      await _player.stop();
      await _player.play(UrlSource(url));
      _playingUrl = url;
    } catch (e) {
      _playingUrl = null;
      _error = '播放失败：$e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _playingUrl = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
