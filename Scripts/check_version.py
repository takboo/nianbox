#!/usr/bin/env python3
import ast
from pathlib import Path
import re
import tomllib
root=Path(__file__).resolve().parent.parent
version=(root/'VERSION').read_text().strip()
assert re.fullmatch(r'\d+\.\d+\.\d+',version)
assert tomllib.loads((root/'Server/pyproject.toml').read_text())['project']['version']==version
module=ast.parse((root/'Server/nianbox/__init__.py').read_text())
assert any(isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='__version__' for t in n.targets)
           and ast.literal_eval(n.value)==version for n in module.body)
assert (root/f'docs/releases/v{version}.md').is_file()
print('PASS: app, server and release version',version)
