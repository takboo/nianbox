#!/usr/bin/env python3
"""Build/verify a drag-to-Applications DMG without driving Finder or the desktop."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import dmgbuild
from ds_store import DSStore

ROOT = Path(__file__).resolve().parent.parent

def run(*command):
    try:
        return subprocess.check_output([str(x) for x in command], stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(error.stderr.decode(errors='replace').strip()) from error

def mount(image, point, readonly=False):
    command = ['hdiutil', 'attach', '-nobrowse', '-noautoopen', '-mountpoint', str(point), '-plist']
    if readonly:
        command.append('-readonly')
    run(*command, image)

def inspect(mounted, version):
    app = mounted / 'NianBox.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'org.nianbox.NianBox'
    assert info['CFBundleShortVersionString'] == version
    assert os.readlink(mounted / 'Applications') == '/Applications'
    assert (mounted / '.background.tiff').is_file()
    assert (mounted / 'READ ME.txt').is_file()
    run('codesign', '--verify', '--strict', '--deep', app)
    architectures = run('lipo', '-archs', app / 'Contents/MacOS/NianBox').decode().split()
    assert set(architectures) == {'arm64', 'x86_64'}, architectures
    entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', app))
    assert entitlements == {'com.apple.security.app-sandbox': True,
                           'com.apple.security.network.client': True,
                           'com.apple.security.files.user-selected.read-write': True}
    with DSStore.open(str(mounted / '.DS_Store'), 'r') as store:
        assert store['.']['vSrn'] == (b'long', 1)
        assert store['.']['icvp']['backgroundType'] == 2
        assert store['.']['icvp']['iconSize'] == 96.0
        assert store['.']['bwsp']['WindowBounds'] == '{{160, 160}, {700, 460}}'
        assert store['NianBox.app']['Iloc'] == (180, 235)
        assert store['Applications']['Iloc'] == (520, 235)
    return {'version': version, 'architectures': architectures, 'bundleID': info['CFBundleIdentifier'],
            'signing': 'ad-hoc; not notarized', 'layout': 'headless DS_Store + Applications link'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text().strip()
    with tempfile.TemporaryDirectory(prefix='nianbox-dmg-') as directory:
        workspace = Path(directory)
        point = workspace / 'mounted'
        if args.verify:
            run('hdiutil', 'verify', args.verify)
            mount(args.verify.resolve(), point, readonly=True)
            try:
                result = inspect(point, version)
            finally:
                run('hdiutil', 'detach', point)
            result['sha256'] = hashlib.sha256(args.verify.read_bytes()).hexdigest()
            print(json.dumps(result, indent=2))
            return
        if not args.app or not args.output:
            parser.error('Pass --app and --output, or --verify')
        app = args.app.resolve()
        output = args.output.resolve()
        if output.exists():
            parser.error('Refusing to overwrite an existing DMG')
        output.parent.mkdir(parents=True, exist_ok=True)
        staging = workspace / 'staging'
        staging.mkdir()
        for scale in (1, 2):
            background = staging / ('background.png' if scale == 1 else 'background@2x.png')
            run('swift', '-module-cache-path', workspace / 'swift-cache', ROOT / 'Scripts/render_dmg_background.swift',
                background, scale)
        (staging / 'READ ME.txt').write_text(
            '念匣 · NianBox\n\n1. 将 NianBox 拖到 Applications。\n2. 从应用程序打开 NianBox。\n'
            '3. 从菜单栏进入设置；点击 Quick capture shortcut 可录制快捷键。\n'
            '首次打开若被 macOS 拦截，请在系统设置 → 隐私与安全性中查看“仍要打开”。\n'
            '这是未公证的个人开源构建，不需要关闭系统安全保护。\n\n'
            'Drag NianBox to Applications, then launch it from Applications.\n'
            'This personal build is ad-hoc signed and is not notarized. If macOS blocks the first launch,\n'
            'review System Settings → Privacy & Security → Open Anyway. Keep Gatekeeper enabled.\n\n'
            'https://github.com/takboo/nianbox\n', encoding='utf-8')
        shutil.copyfile(ROOT / 'LICENSE', staging / 'LICENSE.txt')
        candidate = workspace / 'final.dmg'
        # dmgbuild writes complete Finder view settings and a multi-resolution TIFF,
        # without AppleScript, Finder automation, Accessibility or host input.
        dmgbuild.build_dmg(str(candidate), 'NianBox', settings={
            'format': 'UDZO', 'compression_level': 9, 'filesystem': 'HFS+',
            'files': [str(app), str(staging / 'READ ME.txt'), str(staging / 'LICENSE.txt')],
            'symlinks': {'Applications': '/Applications'},
            'background': str(staging / 'background.png'),
            'window_rect': ((160, 160), (700, 460)),
            'icon_size': 96, 'text_size': 14,
            'default_view': 'icon-view', 'include_icon_view_settings': True,
            'include_list_view_settings': False,
            'icon_locations': {'NianBox.app': (180, 235), 'Applications': (520, 235),
                               'READ ME.txt': (750, 600), 'LICENSE.txt': (850, 600)},
        })
        mount(candidate, point, readonly=True)
        try:
            inspect(point, version)
        finally:
            run('hdiutil', 'detach', point)
        # Exclusively create the destination; a retry cannot replace another release artifact.
        with candidate.open('rb') as source, output.open('xb') as target:
            shutil.copyfileobj(source, target)
        print(output)

if __name__ == '__main__':
    main()
