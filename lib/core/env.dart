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
      // jsDelivr 四域名共用同一个 GitHub 回源，一起挂时仍需要一个独立兜底。
      'https://gh-proxy.com/https://raw.githubusercontent.com/$githubRepo/$defaultBranch',
    ];
  }

  /// 数据源按顺序自动回退。tag 是 immutable，命中后天然永久缓存。
  ///
  /// **必须包含真正独立的服务商**：jsDelivr 的 gcore / testingcf / fastly /
  /// cdn 四个域名共用同一个 GitHub 回源。2026-11-17 实测
  /// `data/sgsol/characters.json`（2.9MB）在这四个域名上全部超时
  /// （0 字节 / 45s），加 query 破缓存也无效；同一文件经 gh-proxy.com
  /// 3~6 秒即可拉全，内容与 GitHub API 记录的 3054580 字节一致。
  /// 只靠 jsDelivr 会让一个卡死的文件拖垮整批更新（整批回滚），
  /// 所以 jsDelivr 只留最快的两个，中间插独立加速代理做真回退。
  ///
  /// 2026-11-12 的另一条依据：fastly 对约 3MB 以上的文件返回 403
  /// 「Package size exceeded 50 MB」，所以它排在后面。
  static List<String> dataBaseUrls(String version) {
    if (!hasRemote) return const <String>[];
    final tag = '$tagPrefix$version';
    final raw = 'https://raw.githubusercontent.com/$githubRepo/$tag';
    return <String>[
      'https://gcore.jsdelivr.net/gh/$githubRepo@$tag',
      'https://gh-proxy.com/$raw',
      'https://testingcf.jsdelivr.net/gh/$githubRepo@$tag',
      'https://ghproxy.net/$raw',
      'https://fastly.jsdelivr.net/gh/$githubRepo@$tag',
      raw,
    ];
  }

  /// 壳内本地 server 的首选端口，必须固定。
  ///
  /// 原页面的账号（`services/localAuth.js`）、收藏、历史、主题偏好全部存在
  /// localStorage，而 localStorage 以 **origin（scheme://host:port）** 为键。
  /// 端口一变就等于换了个站点：注册过的账号、收藏、会话全部读不到，用户看到
  /// 的就是「登录没保存 / 重启后又要重新注册」。所以这里钉死一个高位端口，
  /// 只在被占用时才顺延（见 ShellServer._bind）。
  static const int shellPort = 47821;

  /// 账号服务器地址（自己部署的那个零依赖 Python 后端）。
  ///
  /// 留空 = App 里关闭云端账号，只用本机账号（与升级前完全一致）。
  ///
  /// 为什么必须显式写：页面的自动判断是「同源有 /api 就用」，而 App 的 origin 是
  /// `http://127.0.0.1:<端口>`，命不中这条规则 —— 所以壳会把这里的值注入成
  /// `window.SGS_API_BASE` 再交给页面。
  ///
  /// 想不改包就换地址：在应用支持目录放一个 `sgs_api_base.txt`（一行，
  /// `http://192.168.1.20:8080`），优先级高于这里，见 ShellServer._resolveApiBase。
  ///
  /// 现在填的是「家里局域网 + 本机回环」两个候选，按顺序试，谁能应答就用谁：
  /// 手机在家 WiFi → 命中第一个；桌面端本机跑后端 → 命中第二个；
  /// 两个都不通 → 自动降级成本机账号（离线照样能用）。
  static const String backendBase =
      'http://192.168.31.216:8080,http://127.0.0.1:8080';

  static const String notConfigured = '尚未配置数据仓库地址（Env.githubRepo）';
}
