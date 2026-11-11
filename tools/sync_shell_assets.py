#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把主程序镜像 legacy-web 单向同步成 App 随包页面 assets/shell。

用法：
    python tools/sync_shell_assets.py

为什么不是重写 UI：main.dart.js 是 Flutter 自己的渲染引擎，不认识
index.html / style.css / app.js。要 1:1 保留原界面，唯一可靠做法是把
原页面整个装进 WebView。这里复制的是**同一份文件**，不是仿制品。

产物：
    assets/shell/**          原页面（排除开发脚本、备份、抓取工具）
    assets/shell/files.txt   随包文件清单，供运行时判断资源是否存在
    assets/shell/shell.json  版本与统计，跟随 data-repo 的数据版本
    assets/shell/shell_hashes.json  每个随包文件的 sha256，作增量更新基线

语义：镜像同步 —— 源里删掉的文件这里也会清掉；绝不修改 legacy-web。
pubspec 的 shell-assets 区块由本脚本自动维护（Flutter 的 assets 目录
声明不递归，必须逐目录列出，否则构建产物里会缺文件）。
"""
import hashlib
import json
import os
import re
import shutil
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.normpath(os.path.join(APP, '..', 'legacy-web'))
DST = os.path.join(APP, 'assets', 'shell')
REPO_MANIFEST = os.path.normpath(os.path.join(APP, '..', 'data-repo', 'manifest.json'))
PUBSPEC = os.path.join(APP, 'pubspec.yaml')

# 只排明显的开发/维护文件；页面可能引用的任何资源一律保留。
SKIP_DIRS = {
    '.git', '_backups', '__pycache__', 'node_modules',
    'tools', 'v2', '_shots', 'unreleased',
}
SKIP_NAMES = {'serve.py', '_launch.vbs', '.gitignore', '.DS_Store', 'Thumbs.db'}
SKIP_PREFIX = ('e2e_', 'shot', '_shot')
SKIP_SUFFIX = ('.py', '.pyc', '.bat', '.vbs', '.ps1', '.md', '.log', '.bak', '.cjs', '.mjs')

BEGIN = '    # >>> shell-assets:begin >>>'
END = '    # <<< shell-assets:end <<<'
SEED_END = '    # <<< seed-assets:end <<<'


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for block in iter(lambda: fh.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def rel(path, base):
    return os.path.relpath(path, base).replace('\\', '/')


def keep(name):
    if name in SKIP_NAMES:
        return False
    if name.startswith(SKIP_PREFIX):
        return False
    if name.lower().endswith(SKIP_SUFFIX):
        return False
    return True


def collect():
    out = []
    for root, dirs, files in os.walk(SRC):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if not keep(name):
                continue
            p = os.path.join(root, name)
            out.append((rel(p, SRC), p))
    return out


def patch_pubspec(paths):
    dirs = {'assets/shell/'}
    for item in paths:
        parts = item.split('/')[:-1]
        dirs.add('assets/shell/' + ('/'.join(parts) + '/' if parts else ''))
    block = BEGIN + '\n' + '\n'.join('    - %s' % d for d in sorted(dirs)) + '\n' + END
    src = open(PUBSPEC, encoding='utf-8').read()
    if BEGIN not in src:
        anchor = SEED_END + '\n'
        if anchor not in src:
            raise RuntimeError('pubspec.yaml 里找不到 seed-assets 结束标记')
        src = src.replace(anchor, anchor + '\n' + BEGIN + '\n' + END, 1)
    new, hits = re.subn(
        re.escape(BEGIN) + r'.*?' + re.escape(END),
        lambda _: block, src, count=1, flags=re.S)
    if hits != 1:
        raise RuntimeError('pubspec.yaml 里找不到 shell-assets 标记块')
    if new != src:
        open(PUBSPEC, 'w', encoding='utf-8', newline='\n').write(new)
    print('pubspec  : %d 个 shell asset 目录已登记' % len(dirs))
    return len(dirs)


def main():
    if not os.path.isdir(SRC):
        sys.exit('找不到 legacy-web: ' + SRC)
    os.makedirs(DST, exist_ok=True)

    items = collect()
    kept = set()
    total = 0
    for rpath, src in items:
        dst = os.path.join(DST, *rpath.split('/'))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.isfile(dst) or os.path.getsize(dst) != os.path.getsize(src):
            shutil.copy2(src, dst)
        size = os.path.getsize(dst)
        total += size
        kept.add(rpath)

    # 镜像清理：源里已不存在的文件，随包也删掉（不碰自身产出的两个清单）
    self_files = {'files.txt', 'shell.json', 'shell_hashes.json'}
    stale = 0
    for root, dirs, files in os.walk(DST):
        dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
        for name in files:
            p = os.path.join(root, name)
            r = rel(p, DST)
            if r in kept or r in self_files:
                continue
            os.remove(p)
            stale += 1
    for root, dirs, _files in os.walk(DST, topdown=False):
        if root == DST:
            break
        if not os.listdir(root):
            os.rmdir(root)

    with open(os.path.join(DST, 'files.txt'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(r for r, _ in items) + '\n')

    version = '0'
    if os.path.isfile(REPO_MANIFEST):
        try:
            version = json.load(open(REPO_MANIFEST, encoding='utf-8'))['version']
        except (ValueError, KeyError, OSError):
            pass
    meta = {
        'schema': 1,
        'version': version,
        'entry': 'index.html',
        'files': len(items),
        'bytes': total,
    }
    with open(os.path.join(DST, 'shell.json'), 'w', encoding='utf-8') as f:
        json.dump(meta, f, ensure_ascii=False, separators=(',', ':'))

    # 随包基线：路径就是原页面 URL 路径，也就是 data-repo 相对路径。
    # App 首次启动时把它登记进 UpdateSink，之后只拉 hash 变化的文件。
    hashes = {
        r: sha256_file(os.path.join(DST, *r.split('/')))
        for r, _ in items
    }
    with open(os.path.join(DST, 'shell_hashes.json'), 'w', encoding='utf-8') as f:
        json.dump({'schema': 1, 'version': version, 'hashes': hashes},
                  f, ensure_ascii=False, separators=(',', ':'), sort_keys=True)

    print('legacy-web: %s' % SRC)
    print('shell     : %s' % DST)
    print('随包文件  : %d 个 / %.2f MB' % (len(items), total / 1024 / 1024))
    print('数据版本  : %s' % version)
    print('基线哈希  : %d 条 -> shell_hashes.json' % len(hashes))
    print('镜像清理  : %d 个残留文件' % stale)
    patch_pubspec([r for r, _ in items])


if __name__ == '__main__':
    main()
