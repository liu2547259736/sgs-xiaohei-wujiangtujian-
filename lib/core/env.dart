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

  /// 皮肤图独立仓：12901 张 webp / 706.6 MB，按原 URL 路径平铺，
  /// 不放进数据仓库（会把 sgs-data 顶到 954 MB，逼近 1 GB 上限）。
  ///
  /// 原页面按 `images/<ver>/sk/<name>.webp` 相对路径请求皮肤，
  /// ShellServer 会把这类请求 302 到这里，由 WebView 直接向 CDN 取图并自行缓存，
  /// **不把 706 MB 下载到设备覆盖层**。带 `?iv=N` 破缓存参数时原样透传。
  static const String skinRepo = 'liu2547259736/sgs-skins';
  static const String skinBranch = 'main';
  /// 默认走 gcore.jsdelivr.net：cdn.jsdelivr.net 在国内直连 TLS 握手失败
  /// （2026-11-12、11-16 两次实测 HTTP 000，挂代理才 200），
  /// gcore / testingcf 可直连。数据仓的多源列表里仍保留 cdn 作兜底，
  /// 但皮肤是 <img> 单源直取、没有回退机会，所以这里必须可直连。
  static const String skinCdnBase =
      'https://gcore.jsdelivr.net/gh/$skinRepo@$skinBranch/';

  static bool get hasRemote => githubRepo.isNotEmpty;

  /// 版本发现源：指向浮动分支的 manifest.json，返回最新版本字符串。
  ///
  /// 实测各 CDN 边缘节点对 @master 的缓存进度可能差一整天（2026-11-12
  /// 有一个源仍返回前一天的版本）。GitUpdateService 会遍历全部源并取
  /// version 最大的那份，所以这里的顺序只影响请求先后，不决定采用哪个版本。
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
  /// 顺序依据 2026-11-12 实测：fastly 对约 3MB 以上的文件
  /// （fonts/sgs-juan.woff2 3.4MB）返回 403「Package size exceeded 50 MB」，
  /// gcore / testingcf / cdn / raw 则全部 200。版本发现仍走 fastly
  /// （1.1MB manifest 实测秒回），这里只调整文件下载的优先级，
  /// 免得每个大文件都先白跑一次 403。任一源失败会自动回退到下一个。
  static List<String> dataBaseUrls(String version) {
    if (!hasRemote) return const <String>[];
    final tag = '$tagPrefix$version';
    return <String>[
      'https://gcore.jsdelivr.net/gh/$githubRepo@$tag',
      'https://testingcf.jsdelivr.net/gh/$githubRepo@$tag',
      'https://fastly.jsdelivr.net/gh/$githubRepo@$tag',
      'https://cdn.jsdelivr.net/gh/$githubRepo@$tag',
      'https://raw.githubusercontent.com/$githubRepo/$tag',
    ];
  }

  static const String notConfigured = '尚未配置数据仓库地址（Env.githubRepo）';
}
