#!/usr/bin/env python3
import json
from pathlib import Path
import shutil
import subprocess
import sys

source, app = map(Path, sys.argv[1:])
if not (source / 'Resources' / 'engine-set.json').exists():
    raise SystemExit('Missing engines. Run python3 Scripts/bootstrap_engines.py first.')
previous = app / 'Contents/Resources/engine-set.json'
if previous.exists():
    for relative in json.loads(previous.read_text()).get('files', {}):
        path = Path(relative)
        if path.is_absolute() or '..' in path.parts: raise SystemExit('Invalid previous engine manifest')
        target = app / 'Contents' / path
        if target.is_file(): target.unlink()
for folder in ['MacOS', 'Frameworks', 'Resources']:
    if (source / folder).exists():
        shutil.copytree(source / folder, app / 'Contents' / folder, dirs_exist_ok=True)
# Development signing; release.py re-signs all helpers with Developer ID.
for directory in ['Frameworks', 'MacOS']:
    for file in (app / 'Contents' / directory).glob('*'):
        if file.is_file() and file.name != 'Harbor':
            subprocess.run(['codesign', '--force', '--sign', '-', str(file)], check=True, capture_output=True)
print('Embedded engine set ' + json.loads((source / 'Resources' / 'engine-set.json').read_text())['version'])
