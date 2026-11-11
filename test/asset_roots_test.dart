// 资源根配置：未配置不发无效请求，配置后按主程序路径规则拼接。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sgs_heroes/features/assets/asset_roots.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<AssetRoots> fresh() async {
    final r = AssetRoots();
    await r.init();
    return r;
  }

  test('未配置时皮肤 / 语音 URL 一律为 null', () async {
    final r = await fresh();
    expect(r.hasSkinSource, isFalse);
    expect(r.hasVoiceSource, isFalse);
    expect(r.skinUrl('images/gjf/sk/104.webp'), isNull);
    expect(r.voiceUrl('sgsol', '1001'), isNull);
  });

  test('配置后按主程序规则拼接，且末尾斜杠不重复', () async {
    final r = await fresh();
    await r.setSkinBase('https://cdn.example.com/sgs/');
    await r.setVoiceBase('https://cdn.example.com/sgs');
    expect(r.skinUrl('images/gjf/sk/104.webp'),
        'https://cdn.example.com/sgs/images/gjf/sk/104.webp');
    expect(r.voiceUrl('sgsol', '1001'),
        'https://cdn.example.com/sgs/images/sgsol/voice/1001.ogg');
    expect(r.voiceUrl('msgs', 'abc'),
        'https://cdn.example.com/sgs/images/msgs/voice/abc.mp3');
  });

  test('只有 sgsol / msgs 有官方语音包，其它版本不生成 URL', () async {
    final r = await fresh();
    await r.setVoiceBase('https://cdn.example.com/');
    expect(r.voiceUrl('gjf', 'x'), isNull);
    expect(r.voiceUrl('sgs', 'x'), isNull);
    expect(r.voiceUrl('sgsol', ''), isNull);
  });

  test('配置持久化，重启后仍生效', () async {
    final a = await fresh();
    await a.setSkinBase('https://assets.example.com/');
    final b = await fresh();
    expect(b.skinBase, 'https://assets.example.com/');
    expect(b.skinUrl('images/sgs/sk/1.webp'),
        'https://assets.example.com/images/sgs/sk/1.webp');
  });
}
