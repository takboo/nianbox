#!/usr/bin/env python3
"""Verify staged asset checksums, publish the release, then promote its exact image index."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
tag = os.environ['GITHUB_REF_NAME']
image = os.environ['NIANBOX_RELEASE_IMAGE']
digest = os.environ['NIANBOX_RELEASE_DIGEST']
assert re.fullmatch(r'\d+\.\d+\.\d+', version) and tag == 'v' + version
assert re.fullmatch(r'sha256:[0-9a-f]{64}', digest)
assert image == 'ghcr.io/' + os.environ['GITHUB_REPOSITORY'].lower()

def gh_json(*arguments):
    return json.loads(subprocess.check_output(['gh', *arguments], text=True))

release = gh_json('release', 'view', tag, '--json', 'isDraft,targetCommitish,url')
assert release['targetCommitish'] == os.environ['GITHUB_SHA']
latest = subprocess.run(['gh', 'api', f'repos/{os.environ["GITHUB_REPOSITORY"]}/releases/latest'], text=True, capture_output=True)
if latest.returncode == 0:
    previous = json.loads(latest.stdout)['tag_name']
    match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', previous)
    if match and tuple(map(int, match.groups())) > tuple(map(int, version.split('.'))):
        raise RuntimeError('Refusing to move stable backwards to an older release')
elif '404' not in latest.stderr:
    raise RuntimeError(latest.stderr)
with tempfile.TemporaryDirectory(prefix='nianbox-release-') as directory:
    folder = Path(directory)
    subprocess.run(['gh', 'release', 'download', tag, '--dir', str(folder), '--pattern', 'SHA256SUMS',
        '--pattern', f'NianBox-{version}-universal.dmg'], check=True)
    checksum, filename = (folder / 'SHA256SUMS').read_text().strip().split()
    assert filename == f'NianBox-{version}-universal.dmg' and re.fullmatch('[0-9a-f]{64}', checksum)
    assert hashlib.sha256((folder / filename).read_bytes()).hexdigest() == checksum
    notes = folder / 'notes.md'
    notes.write_text((root / f'docs/releases/{tag}.md').read_text() +
        f'\n\nServer image: `{image}:{version}`\n\nPinned multi-platform image: `{image}@{digest}`\n\nDMG SHA-256: `{checksum}`\n')
    subprocess.run(['gh', 'release', 'edit', tag, '--draft=false', '--latest', '--notes-file', str(notes)], check=True)
subprocess.run(['docker', 'buildx', 'imagetools', 'create', '--tag', image + ':stable',
    '--tag', image + ':v' + version, image + '@' + digest], check=True)
for name in ['stable', version, 'v' + version]:
    descriptor = json.loads(subprocess.check_output(['docker', 'buildx', 'imagetools', 'inspect',
        image + ':' + name, '--format', '{{json .Manifest}}'], text=True))
    assert descriptor['digest'] == digest, (name, descriptor['digest'], digest)
print(json.dumps({'release': release['url'], 'tag': tag, 'stableDigest': digest, 'dmgSHA256': checksum}, indent=2))
