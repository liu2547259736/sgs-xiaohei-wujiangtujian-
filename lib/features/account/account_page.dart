// 本地账号页：注册 / 登录 / 会话 / 账号列表 / 导入导出 / 清空。
// 收藏、查阅历史等按 scopeKey 做账号隔离，切换账号后图鉴会立即刷新收藏。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/atlas_controller.dart';
import '../common/app_scopes.dart';
import 'local_auth.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, this.controller});

  final AtlasController? controller;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pwd = TextEditingController();
  final TextEditingController _nick = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pwd.dispose();
    _nick.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _afterAuth() async {
    await widget.controller?.onAccountChanged();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final theme = Theme.of(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('本地账号')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          Text(
            '账号与业务数据只存在本机，不上传、不联网。密码用 salted FNV-1a 摘要'
            '（与主程序同格式，不是加密，仅避免明文落盘），备份可与主程序互相导入。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (user != null)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(user.displayName),
                subtitle: Text('@${user.username} · ${auth.loadList('sgs_favorites').length} 个收藏'),
                trailing: TextButton(
                  onPressed: () async {
                    await auth.logout();
                    await _afterAuth();
                    _msg('已退出登录');
                  },
                  child: const Text('退出'),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: '账号', isDense: true, border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _pwd,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: '密码', isDense: true, border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nick,
                      decoration: const InputDecoration(
                          labelText: '昵称（注册时可选）',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final r = await auth.login(_name.text, _pwd.text);
                              setState(() => _error = r.ok ? null : r.error);
                              if (r.ok) {
                                await _afterAuth();
                                _msg('登录成功');
                              }
                            },
                            child: const Text('登录'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final r = await auth.register(
                                  _name.text, _pwd.text, nickname: _nick.text);
                              setState(() => _error = r.ok ? null : r.error);
                              if (r.ok) {
                                await _afterAuth();
                                _msg('注册并登录成功');
                              }
                            },
                            child: const Text('注册'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text('账号列表 (${auth.users.length})',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          if (auth.users.isEmpty)
            Text('还没有账号。游客态数据保存在不带 @userId 的键里。',
                style: theme.textTheme.bodySmall)
          else
            for (final u in auth.users)
              Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(u.id == user?.id
                      ? Icons.check_circle
                      : Icons.person_outline),
                  title: Text(u.displayName),
                  subtitle: Text('@${u.username} · 创建于 ${u.createdAt}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (u.id != user?.id)
                        TextButton(
                          onPressed: () async {
                            await auth.selectUser(u.id);
                            await _afterAuth();
                            _msg('已切换到 ${u.displayName}');
                          },
                          child: const Text('切换'),
                        ),
                      IconButton(
                        tooltip: '删除账号',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _confirmDelete(auth, u),
                      ),
                    ],
                  ),
                ),
              ),
          const Divider(height: 28),
          Text('备份与恢复', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _export(auth),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('导出备份'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _import(auth),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('导入备份'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _confirmClear(auth),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('清空所有账号与本地数据'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(LocalAuthService auth, LocalUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除账号？'),
        content: Text('将删除 ${u.displayName} 及其隔离的收藏 / 历史，不可恢复。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await auth.removeUser(u.id);
      await _afterAuth();
      _msg('账号已删除');
    }
  }

  Future<void> _confirmClear(LocalAuthService auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空全部本地数据？'),
        content: const Text('所有账号、收藏、历史、设置都会被删除，不可恢复。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认清空')),
        ],
      ),
    );
    if (ok == true) {
      await auth.clearAll();
      await _afterAuth();
      _msg('已清空');
    }
  }

  void _export(LocalAuthService auth) {
    final text = auth.exportData();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('导出备份'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) _msg('备份 JSON 已复制到剪贴板');
            },
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制'),
          ),
        ],
      ),
    );
  }

  void _import(LocalAuthService auth) {
    final ctrl = TextEditingController();
    var mode = 'merge';
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('导入备份'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('粘贴主程序或本端导出的 JSON 备份：'),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(value: 'merge', label: Text('合并')),
                    ButtonSegment<String>(value: 'replace', label: Text('替换')),
                  ],
                  selected: <String>{mode},
                  onSelectionChanged: (v) => setSt(() => mode = v.first),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                // 先同步关掉输入框，避免 await 之后再跨异步间隙使用 BuildContext。
                Navigator.pop(context);
                final r = await auth.importData(ctrl.text, mode: mode);
                if (r.ok) {
                  await _afterAuth();
                  _msg('导入完成：新增 ${r.added} / 更新 ${r.updated} / 共 ${r.total}');
                } else {
                  _msg(r.error ?? '导入失败');
                }
              },
              child: const Text('导入'),
            ),
          ],
        ),
      ),
    );
  }
}
