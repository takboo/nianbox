import argparse
import json
import os
from pathlib import Path
from .store import Store

parser = argparse.ArgumentParser(description='NianBox Server data operations')
parser.add_argument('operation', choices=['backup', 'export'])
parser.add_argument('destination')
args = parser.parse_args()
source = os.environ.get('NIANBOX_DB', '/data/nianbox.sqlite')
if not Path(source).is_file():
    parser.error('No existing NianBox database at NIANBOX_DB; refusing to create an empty backup')
store = Store(source)
if args.operation == 'backup':
    store.backup(args.destination)
else:
    fd = os.open(args.destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as output:
        json.dump(store.export(), output, ensure_ascii=False, indent=2)
