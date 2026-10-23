import argparse
import json
import os
from .store import Store

parser = argparse.ArgumentParser(description='NianBox Server data operations')
parser.add_argument('operation', choices=['backup', 'export'])
parser.add_argument('destination')
args = parser.parse_args()
store = Store(os.environ.get('NIANBOX_DB', '/data/nianbox.sqlite'))
if args.operation == 'backup':
    store.backup(args.destination)
else:
    with open(args.destination, 'x', encoding='utf-8') as output:
        json.dump(store.export(), output, ensure_ascii=False, indent=2)
