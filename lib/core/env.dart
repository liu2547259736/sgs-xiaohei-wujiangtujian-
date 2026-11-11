// 数据仓库地址配置。填一行 githubRepo，六端的「检查更新」即可工作。
//
// 注意：这里更新的是数据 / 图片 / 配置，不是 Dart 代码。
// Flutter 是 AOT 编译，代码变更必须重新打包发版。
class Env {
  const Env._();

  /// GitHub 的 `<user>/<repo>`，例如 'asuna/sgs-data'。
  /// 留空 = 未配置远端，App 只用随包 seed 数据，且不发任何网络请求。
  static const String githubRepo = 'liu2547259736/sgs-data';

  static const String tagPrefix = 'data-v';

  /// 数据仓库的默认分支，只用来「发现最新版本」。
  /// 不能把文件下载也固定到本地版本对应的 tag 上 —— tag 是 immutable，
  /// 那样永远只能拉到自己这一版，检查更新形同虚设。
  static const String defaultBranch = 'master';

  static bool get hasRemote => githubRepo.isNotEmpty;

  /// 版本发现源：指向浮动分支的 manifest.json，返回最新版本字符串。
  static List<String> manifestUrls() {
    if (!hasRemote) return const <String>[];
    return <String>[
      'https://fastly.jsdelivr.net/gh/$githubRepo@$defaultBranch',
      'https://gcore.jsdelivr.net/gh/$githubRepo@$defaultBranch',
      'https://testingcf.jsdelivr.net/gh/$githubRepo@$defaultBranch',
      'https://cdn.jsdelivr.net/gh/$githubRepo@$defaultBranch',
      'https://raw.githubusercontent.com/$githubRepo/$defaultBranch',
    ];
  }

  /// 数据源按顺序自动回退。tag 是 immutable，命中后天然永久缓存。
  ///
  /// 顺序依据 2026-11-11 国内实测（DNS 把 jsDelivr 系域名解析到 192.168.31.1）：
  /// fastly / gcore / testingcf 能直连取到内容；cdn.jsdelivr.net 与
  /// raw.githubusercontent.com 在本机 TLS 握手失败，仅作其它网络环境的兜底。
  /// 放在前面的源失败会拖慢首启，所以把实测可用的排在最前。
  static List<String> dataBaseUrls(String version) {
    if (!hasRemote) return const <String>[];
    final tag = '$tagPrefix$version';
    return <String>[
      'https://fastly.jsdelivr.net/gh/$githubRepo@$tag',
      'https://gcore.jsdelivr.net/gh/$githubRepo@$tag',
      'https://testingcf.jsdelivr.net/gh/$githubRepo@$tag',
      'https://cdn.jsdelivr.net/gh/$githubRepo@$tag',
      'https://raw.githubusercontent.com/$githubRepo/$tag',
    ];
  }

  static const String notConfigured = '尚未配置数据仓库地址（Env.githubRepo）';
}
