// WebView 壳的常量。
//
// 原页面一个字都不改：随包资源路径与 legacy-web 完全同构，
// 本地 server 直接按 URL 路径取同名文件。
const String kShellAssetPrefix = 'assets/shell/';
const String kShellFileList = 'assets/shell/files.txt';
const String kShellMeta = 'assets/shell/shell.json';
const String kShellHashes = 'assets/shell/shell_hashes.json';
const String kShellEntry = 'index.html';

/// GitUpdateService 的覆盖层落盘目录，见 update_sink_io.dart。
/// 路径与随包资源同名时，覆盖层优先命中，CDN 增量更新无需改原页面。
const String kDataDirName = 'sgs_data';

/// 账号服务器地址的本地覆盖文件（应用支持目录，一行 `http://host:port`）。
/// 存在时优先于编译期常量 Env.backendBase —— 换服务器地址不必重新出包。
const String kApiBaseFile = 'sgs_api_base.txt';
