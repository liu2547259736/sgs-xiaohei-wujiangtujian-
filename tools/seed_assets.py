#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 data-repo 生成 app/assets/seed —— App 首屏离线可用的最小数据子集。

用法：
    python tools/seed_assets.py

目录结构与 data-repo 完全一致（images/<ver>/av/... 等相对路径原样保留），
这样以后 GitUpdateService 从 CDN 下载的文件路径能直接对齐，不需要二次映射。

随包白名单：
    heroes/*.json              索引 + 11 个分片（约 12 MB）
    meta/search_index.json     拼音 / 技能名 / 性别，跨版本搜索用
    images/<ver>/av/*          头像 3915 张（约 12 MB）
    images/<ver>/icons/**      包图标 321 张（约 0.7 MB）

有意排除：
    images/<ver>/il/*          117 MB 主视觉，Web 包体不适合；详情先用 av 放大
    skins/*                    皮肤图未托管，第一版只用武将内嵌的 skn 名称
    其它 meta/*                卡牌 / 资讯 / 史料，属已砍功能

额外产出 seed.json：随包文件的 version / counts / files[]（sha256 + bytes），
格式与 manifest.json 协议兼容，App 直接当 seed 基线登记，不会把 148 MB 重下一遍。

语义：镜像同步 —— 源里删掉的文件，seed 里也会清掉。绝不修改 data-repo。
"""
import hashlib
import json
import os
import re
import shutil
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.normpath(os.path.join(APP, '..', 'data-repo'))
SEED = os.path.join(APP, 'assets', 'seed')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def rel(path, base):
    return os.path.relpath(path, base).replace('\\', '/')


def collect():
    """返回 [(data-repo 相对路径, 源文件绝对路径)]。"""
    out = []

    # 1. heroes/ 全量（索引 + 分片）
    d = os.path.join(REPO, 'heroes')
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if os.path.isfile(p) and name.endswith('.json'):
            out.append(('heroes/' + name, p))

    # 2. 搜索索引
    p = os.path.join(REPO, 'meta', 'search_index.json')
    if os.path.isfile(p):
        out.append(('meta/search_index.json', p))

    # 3. 头像 av/ 与包图标 icons/（icons 下还有二级子目录，必须递归）
    images = os.path.join(REPO, 'images')
    for ver in sorted(os.listdir(images)):
        vdir = os.path.join(images, ver)
        if not os.path.isdir(vdir):
            continue
        for kind in ('av', 'icons'):
            kdir = os.path.join(vdir, kind)
            if not os.path.isdir(kdir):
                continue
            for root, _dirs, files in os.walk(kdir):
                for name in sorted(files):
                    p = os.path.join(root, name)
                    out.append((rel(p, REPO), p))
    return out


PUBSPEC = os.path.join(APP, 'pubspec.yaml')
BEGIN = '    # >>> seed-assets:begin >>>'
END = '    # <<< seed-assets:end <<<'


def patch_pubspec(paths):
    """Flutter 的 assets 目录声明只包直接子文件，不递归。

    实测：只写 `- assets/seed/` 时，构建产物里只有 seed.json，
    images/<ver>/av/ 下 3915 张头像一张都没进包。
    这里把所有「含文件的子目录」逐条列出，由脚本维护，避免手写漏目录。
    """
    dirs = set()
    for item in list(paths) + ['seed.json']:
        parts = item.split('/')[:-1]
        dirs.add('assets/seed/' + ('/'.join(parts) + '/' if parts else ''))
    block = BEGIN + '\n' + '\n'.join(
        '    - %s' % d for d in sorted(dirs)) + '\n' + END
    src = open(PUBSPEC, encoding='utf-8').read()
    new, hits = re.subn(
        re.escape(BEGIN) + r'.*?' + re.escape(END),
        lambda _: block, src, count=1, flags=re.S)
    if hits != 1:
        raise RuntimeError('pubspec.yaml 里找不到 seed-assets 标记块')
    if new != src:
        open(PUBSPEC, 'w', encoding='utf-8', newline='\n').write(new)
    print('pubspec  : %d 个 asset 目录已登记' % len(dirs))
    return len(dirs)


def main():
    if not os.path.isdir(REPO):
        sys.exit('找不到 data-repo: ' + REPO)
    os.makedirs(SEED, exist_ok=True)

    items = collect()
    kept = set()
    total = 0
    records = []

    for rpath, src in items:
        dst = os.path.join(SEED, *rpath.split('/'))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.isfile(dst) or os.path.getsize(dst) != os.path.getsize(src):
            shutil.copy2(src, dst)
        size = os.path.getsize(dst)
        total += size
        kept.add(rpath)
        records.append({'path': rpath, 'sha256': sha256(dst), 'bytes': size})

    # 镜像清理：清掉已不在白名单里的旧 seed 文件（不碰 seed.json 自身）
    stale = 0
    for root, dirs, files in os.walk(SEED):
        dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
        for name in files:
            p = os.path.join(root, name)
            r = rel(p, SEED)
            if r in kept or r == 'seed.json':
                continue
            os.remove(p)
            stale += 1
    for root, dirs, _files in os.walk(SEED, topdown=False):
        if root == SEED:
            break
        if not os.listdir(root):
            os.rmdir(root)

    # seed.json —— 与 DataManifest 协议兼容的随包基线
    manifest = json.load(open(os.path.join(REPO, 'manifest.json'), encoding='utf-8'))
    seed = {
        'schema': 1,
        'version': manifest['version'],
        'updated_at': manifest['updated_at'],
        'counts': manifest['counts'],
        'seed_files': len(records),
        'seed_bytes': total,
        'files': records,
    }
    with open(os.path.join(SEED, 'seed.json'), 'w', encoding='utf-8') as f:
        json.dump(seed, f, ensure_ascii=False, separators=(',', ':'))

    print('data-repo : %s' % REPO)
    print('seed      : %s' % SEED)
    print('随包文件  : %d 个 / %.2f MB' % (len(records), total / 1024 / 1024))
    print('数据版本  : %s' % seed['version'])
    print('全库统计  : %s' % json.dumps(seed['counts'], ensure_ascii=False))
    print('镜像清理  : %d 个残留文件' % stale)
    patch_pubspec([r for r, _ in items])
    print('seed.json : %.2f KB' % (os.path.getsize(os.path.join(SEED, 'seed.json')) / 1024))


if __name__ == '__main__':
    main()
