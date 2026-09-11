#!/usr/bin/env python3
import json
from pathlib import Path
import shutil
import subprocess
import sys

source, app = map(Path, sys.argv[1:])
if not (source / 'Resources' / 'engine-set.json').exists():
    raise SystemExit('Missing engines. Run python3 Scripts/bootstrap_engines.py first.')
for folder in ['MacOS', 'Frameworks', 'Resources']:
    if (source / folder).exists():
        shutil.copytree(source / folder, app / 'Contents' / folder, dirs_exist_ok=True)
# Development signing; release.py re-signs all helpers with Developer ID.
for directory in ['Frameworks', 'MacOS']:
    for file in (app / 'Contents' / directory).glob('*'):
        if file.is_file() and file.name != 'Harbor':
            subprocess.run(['codesign', '--force', '--sign', '-', str(file)], check=True, capture_output=True)
print('Embedded engine set ' + json.loads((source / 'Resources' / 'engine-set.json').read_text())['version'])
