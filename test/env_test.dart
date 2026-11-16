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

    test('数据源必须含独立服务商，不能全是 jsDelivr', () {
      if (!Env.hasRemote) return; // 未配置时跳过
      final urls = Env.dataBaseUrls('2026.11.10-2');
      // jsDelivr 的 gcore / testingcf / fastly / cdn 共用同一个 GitHub 回源。
      // 2026-11-17 实测 data/sgsol/characters.json（2.9MB）在四个域名上全部
      // 超时（0 字节 / 45s），加 query 破缓存也无效，换成 gh-proxy 才拉下来。
      // 如果这里退化成「全是 jsDelivr」，单个卡死文件会让整批更新回滚。
      expect(
        urls.any((u) => !u.contains('jsdelivr.net')),
        isTrue,
        reason: '必须至少有一个非 jsDelivr 的独立回退源',
      );
      expect(
        urls.any((u) => u.contains('gh-proxy.com')),
        isTrue,
        reason: 'gh-proxy 是实测能绕过 jsDelivr 卡死的独立源',
      );
      // 独立源要排在靠前位置：排在 4 个 jsDelivr 之后等于每个卡死文件
      // 先白等 3 分钟。
      final firstIndependent = urls.indexWhere((u) => !u.contains('jsdelivr.net'));
      expect(firstIndependent, lessThanOrEqualTo(2),
          reason: '独立回退源不能排得太靠后');
    });
  });
}
