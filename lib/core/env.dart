// 数据仓库地址配置。填一行 githubRepo，六端的「检查更新」即可工作。
//
// 注意：这里更新的是数据 / 图片 / 配置，不是 Dart 代码。
// Flutter 是 AOT 编译，代码变更必须重新打包发版。
class Env {
  const Env._();

  /// GitHub 的 `<user>/<repo>`，例如 'asuna/sgs-data'。
  /// 留空 = 未配置远端，App 只用随包 seed 数据，且不发任何网络请求。
  static const String githubRepo = '';

  static const String tagPrefix = 'data-v';

  static bool get hasRemote => githubRepo.isNotEmpty;

  /// 三个数据源按顺序自动回退。tag 是 immutable，命中后天然永久缓存。
  static List<String> dataBaseUrls(String version) {
    if (!hasRemote) return const <String>[];
    final tag = '$tagPrefix$version';
    return <String>[
      'https://cdn.jsdelivr.net/gh/$githubRepo@$tag',
      'https://fastly.jsdelivr.net/gh/$githubRepo@$tag',
      'https://raw.githubusercontent.com/$githubRepo/$tag',
    ];
  }

  static const String notConfigured = '尚未配置数据仓库地址（Env.githubRepo）';
}
