import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/core/env.dart';

void main() {
  group('Env 数据源', () {
    test('未配置 githubRepo 时不产生任何数据源（App 不发网络请求）', () {
      if (Env.hasRemote) return; // 已配置远端时由下一条用例覆盖
      expect(Env.dataBaseUrls('2026.11.10-2'), isEmpty);
      expect(Env.notConfigured, isNotEmpty);
    });

    test('数据源首个为实测稳定的 gcore，且 tag 拼接正确', () {
      if (!Env.hasRemote) return; // 未配置时跳过
      final urls = Env.dataBaseUrls('2026.11.10-2');
      expect(urls, isNotEmpty);
      // fastly 对 >3MB 文件会 403，文件下载改由 gcore 打头。
      expect(urls.first, startsWith('https://gcore.jsdelivr.net/gh/'));
      expect(urls.first, contains(Env.githubRepo));
      expect(urls.first, contains('@data-v2026.11.10-2'));
      // 备用源必须覆盖国内可用的三个镜像 + 两个兜底
      expect(urls.length, greaterThanOrEqualTo(5));
    });
  });
}
