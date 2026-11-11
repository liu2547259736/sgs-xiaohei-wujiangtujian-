#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在 Windows 上跑 flutter test 的包装器（CI 的 ubuntu runner 不需要它）。

本机会撞到两个 flutter_tools 的 Windows 特性，都不是测试代码的问题：

1. refreshPluginsList() 只要看到 windows/ 或 linux/ 目录就为平台插件创建
   符号链接；未开开发者模式时抛 "Building with plugins requires symlink
   support"。flutter test 跑在 flutter_tester（纯 Dart VM）上，不需要它们。
2. pubspec 的 shell-assets 声明了 8953 个 / 219MB 的随包原页面资源，
   flutter test 会把这些资源全打进测试 asset bundle，构建慢到不可用。
   测试本身只依赖 assets/seed（34MB），不需要原页面资源。

做法：测试期间临时移走桌面目录、从 pubspec 摘掉 shell-assets 区块，
跑完无条件恢复。不改系统设置、不需要管理员权限、不丢任何工程文件。
即使上次被强杀留下改名目录，下次运行也会先自动恢复。

用法（在 app/ 目录下）：
    python tools/run_tests.py                    # 全量测试
    python tools/run_tests.py test/models_test.dart
"""
import io
import os
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
FLUTTER = os.environ.get('FLUTTER_BAT', r'F:\flutter\bin\flutter.bat')
SUFFIX = '.__test_disabled__'
PLATFORM_DIRS = ('windows', 'linux')
PUBSPEC = APP / 'pubspec.yaml'
BEGIN = '    # >>> shell-assets:begin >>>'
END = '    # <<< shell-assets:end <<<'
TIMEOUT_SECONDS = 600


def write(path, text):
    with io.open(str(path), 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def recover():
    """自愈：把上次异常退出留下的改名目录恢复回去。"""
    for name in PLATFORM_DIRS:
        src = APP / name
        dst = APP / (name + SUFFIX)
        if dst.is_dir() and not src.exists():
            dst.rename(src)
            print('自动恢复上次残留目录: %s' % name, flush=True)
        elif dst.exists() and src.exists():
            raise SystemExit(
                '同时存在 %s 与 %s，请人工确认后清理' % (src.name, dst.name))


def main():
    recover()
    moved = []
    original_pubspec = None
    for name in PLATFORM_DIRS:
        src = APP / name
        dst = APP / (name + SUFFIX)
        if src.is_dir():
            src.rename(dst)
            moved.append((src, dst))

    env = os.environ.copy()
    # 本地回环被系统代理劫持会让 flutter_tester 的 WebSocket 握手失败。
    for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env[key] = ''
    env['NO_PROXY'] = 'localhost,127.0.0.1,::1'
    env['no_proxy'] = env['NO_PROXY']

    args = list(sys.argv[1:])
    # 串行跑：shared_preferences 的 mock 状态在多 suite 并发时偶发串扰，
    # 曾让 local_auth 的账号隔离用例随机失败。测试本身只跑 2 秒，串行不亏。
    if not any(a == '-j' or a.startswith('--concurrency') for a in args):
        args.insert(0, '--concurrency=1')
    cmd = [FLUTTER, 'test', '--no-pub'] + args
    print('$ ' + ' '.join(cmd), flush=True)
    code = 1
    try:
        pubspec_text = PUBSPEC.read_text(encoding='utf-8')
        if BEGIN in pubspec_text and END in pubspec_text:
            original_pubspec = pubspec_text
            i = pubspec_text.index(BEGIN)
            j = pubspec_text.index(END, i) + len(END)
            if j < len(pubspec_text) and pubspec_text[j] == '\n':
                j += 1
            write(PUBSPEC, pubspec_text[:i] + pubspec_text[j:])
            print('临时摘除 shell-assets（测试不需要 219MB 原页面资源）',
                  flush=True)

        result = subprocess.run(cmd, cwd=str(APP), env=env,
                                timeout=TIMEOUT_SECONDS)
        code = result.returncode
    except subprocess.TimeoutExpired:
        print('flutter test 超时（%d 秒）' % TIMEOUT_SECONDS, file=sys.stderr)
    except OSError as e:
        print('启动 flutter 失败: %s' % e, file=sys.stderr)
    finally:
        # 最重要的一步：无论成功、失败还是超时，工程状态必须原样还回去。
        if original_pubspec is not None:
            write(PUBSPEC, original_pubspec)
            print('pubspec.yaml 已恢复', flush=True)
        for src, dst in reversed(moved):
            if dst.is_dir() and not src.exists():
                dst.rename(src)
        print('桌面工程目录已恢复', flush=True)
    return code


if __name__ == '__main__':
    sys.exit(main())
