// 随包资源路径解析。
//
// seed 目录结构与 data-repo 完全一致（tools/seed_assets.py 保证），
// 所以武将数据里的相对路径 'images/sgsol/av/std_guanyu.webp'
// 直接拼上 seedRoot 就能用，不需要别名表或手工映射。
//
// 第一版只把 av / icons 打进包；il 主视觉 117 MB 不进包，
// 详情用 av 放大 + 势力渐变兜底，等 CDN 接通后在这里加一行远程即可。
class SeedAsset {
  const SeedAsset._();

  static const String root = 'assets/seed';
  static const String seedDescriptor = '$root/seed.json';
  static const String heroIndex = '$root/heroes/index.json';
  static const String searchIndex = '$root/meta/search_index.json';

  static String of(String relPath) {
    if (relPath.isEmpty) return '';
    return relPath.startsWith('$root/') ? relPath : '$root/$relPath';
  }

  /// 该相对路径是否随包存在。避免对未打包的 il / sk 发起必然 404 的加载。
  static bool isBundled(String relPath) =>
      relPath.contains('/av/') || relPath.contains('/icons/');

  /// 详情大图：优先 il 的远程地址（未配置时返回 null），调用方降级用 av。
  static String? remoteIllustration(String relPath) => null;
}
