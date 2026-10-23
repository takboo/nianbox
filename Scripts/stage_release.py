#!/usr/bin/env python3
"""Stage verified DMG assets on a draft release; published assets are immutable."""
import json
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
tag = os.environ['GITHUB_REF_NAME']
assert re.fullmatch(r'\d+\.\d+\.\d+', version) and tag == 'v' + version
revision = os.environ['GITHUB_SHA']
assert subprocess.check_output(['git', 'rev-parse', tag + '^{commit}'], text=True).strip() == revision
assets = root / '.local/release' / tag
dmg = assets / f'NianBox-{version}-universal.dmg'
assert dmg.is_file() and (assets / 'SHA256SUMS').is_file()
subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd=assets, check=True)
existing = subprocess.run(['gh', 'release', 'view', tag, '--json', 'isDraft,targetCommitish'], text=True, capture_output=True)
if existing.returncode == 0:
    release = json.loads(existing.stdout)
    assert release['targetCommitish'] == revision
    if not release['isDraft']:
        print('Release already published; preserving its existing assets.')
        raise SystemExit(0)
else:
    if 'release not found' not in existing.stderr.lower():
        raise RuntimeError(existing.stderr)
    subprocess.run(['gh', 'release', 'create', tag, '--verify-tag', '--draft', '--target', revision,
        '--title', f'NianBox {version}', '--notes-file', str(root / f'docs/releases/{tag}.md')], check=True)
subprocess.run(['gh', 'release', 'upload', tag, str(dmg), str(assets / 'SHA256SUMS'), '--clobber'], check=True)
