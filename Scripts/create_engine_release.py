#!/usr/bin/env python3
"""Create a signed engine manifest from a previously signed and notarized app.

The app must be packaged in public mode first. This script creates artifacts only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--url', required=True)
parser.add_argument('--sequence', type=int, required=True)
parser.add_argument('--key-file', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True, exist_ok=True)
manifest = json.loads((args.app / 'Contents/Resources/engine-set.json').read_text())
if not manifest.get('releaseReady') or not args.url.startswith('https://'):
    raise SystemExit('A release-ready engine set and HTTPS artifact URL are required.')
subprocess.run(['spctl', '--assess', '--type', 'execute', str(args.app)], check=True)
staging = args.output / 'engine-content'
if staging.exists(): raise SystemExit('Use a new output directory.')
for folder in ['MacOS', 'Frameworks', 'Resources']:
    shutil.copytree(args.app / 'Contents' / folder, staging / folder)
(staging / 'MacOS/Harbor').unlink()
for extra in ['Harbor.debug.dylib', 'EngineChannel.json']:
    for folder in ['MacOS', 'Resources']:
        path = staging / folder / extra
        if path.exists(): path.unlink()
archive = args.output / 'engines.zip'
subprocess.run(['ditto', '-c', '-k', str(staging), str(archive)], check=True)
payload = {'version': manifest['version'], 'sequence': args.sequence, 'architecture': manifest['architecture'], 'minimumAppBuild': 1,
           'url': args.url, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'size': archive.stat().st_size}
payload_file = args.output / 'payload.json'
payload_file.write_text(json.dumps(payload, sort_keys=True, separators=(',', ':')))
subprocess.run(['swift', str(root / 'Scripts/sign_manifest.swift'), str(payload_file), str(args.key_file), str(args.output / 'manifest.json')], check=True)
shutil.rmtree(staging)
print('Created engines.zip and manifest.json; nothing has been published.')
