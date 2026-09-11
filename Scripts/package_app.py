#!/usr/bin/env python3
"""Package locally. Public mode requires configured signing and notarization.

Never publishes or uploads a release. Notarization is the only public-mode upload.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--development', action='store_true')
parser.add_argument('--app', type=Path, default=root / 'build/xcode/Build/Products/Release/Harbor.app')
parser.add_argument('--output', type=Path, default=root / 'artifacts')
args = parser.parse_args()

def run(*command):
    subprocess.run(list(map(str, command)), check=True)

def main():
    source = args.app.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    app = args.output / 'Harbor.app'
    if app.exists(): shutil.rmtree(app)
    shutil.copytree(source, app, symlinks=True)
    contents = app / 'Contents'
    manifest = json.loads((contents / 'Resources/engine-set.json').read_text())
    arch = manifest['architecture']
    if arch != platform.machine(): raise SystemExit('Build and validate the package on its target architecture.')
    for directory in ['MacOS', 'Frameworks']:
        for binary in (contents / directory).glob('*'):
            if not binary.is_file() or binary.name.endswith('.dylib') is False and directory == 'Frameworks': continue
            load = subprocess.check_output(['otool', '-l', str(binary)], text=True)
            for minimum in re.findall(r'^\s+minos ([\d.]+)', load, re.MULTILINE):
                if tuple(map(int, minimum.split('.')[:2])) > (14, 0): raise SystemExit(binary.name + ' requires macOS ' + minimum)
            deps = subprocess.check_output(['otool', '-L', str(binary)], text=True)
            if '/opt/homebrew/' in deps or '/usr/local/' in deps: raise SystemExit('Nonportable dependency in ' + binary.name)
    identity = '-' if args.development else os.environ.get('HARBOR_SIGNING_IDENTITY')
    if not identity: raise SystemExit('Set HARBOR_SIGNING_IDENTITY to your Developer ID Application identity.')
    if not args.development:
        channel = json.loads((contents / 'Resources/EngineChannel.json').read_text())
        if not channel['teamID'] or not channel['publicKey'] or not channel['manifestURL'].startswith('https://'):
            raise SystemExit('Configure the signed engine update channel before public release.')
        if not manifest.get('releaseReady'):
            raise SystemExit('The dependency source/license audit is not marked complete in the engine-set manifest.')
        if not os.environ.get('HARBOR_NOTARY_PROFILE'):
            raise SystemExit('Set HARBOR_NOTARY_PROFILE to a notarytool Keychain profile.')
    for directory in ['Frameworks', 'MacOS']:
        for binary in (contents / directory).glob('*'):
            if binary.is_file() and binary.name != 'Harbor':
                options = ['codesign', '--force', '--sign', identity]
                if not args.development:
                    options += ['--timestamp', '--options', 'runtime']
                    if binary.name in ['yt-dlp', 'deno']:
                        entitlement = args.output / (binary.name + '.entitlements')
                        values = {'com.apple.security.cs.allow-jit': True} if binary.name == 'deno' else {'com.apple.security.cs.disable-library-validation': True}
                        entitlement.write_bytes(plistlib.dumps(values))
                        options += ['--entitlements', str(entitlement)]
                run(*options, binary)
    options = ['codesign', '--force', '--sign', identity]
    if not args.development: options += ['--timestamp', '--options', 'runtime']
    run(*options, app)
    run('codesign', '--verify', '--deep', '--strict', app)
    if not args.development:
        archive = args.output / 'Harbor-notarization.zip'
        run('ditto', '-c', '-k', '--keepParent', app, archive)
        run('xcrun', 'notarytool', 'submit', archive, '--keychain-profile', os.environ['HARBOR_NOTARY_PROFILE'], '--wait')
        run('xcrun', 'stapler', 'staple', app)
        run('spctl', '--assess', '--type', 'execute', '--verbose', app)
    dmg = args.output / ('Harbor-' + arch + ('-development' if args.development else '') + '.dmg')
    staging = args.output / 'dmg-content'
    if staging.exists(): shutil.rmtree(staging)
    staging.mkdir()
    shutil.copytree(app, staging / 'Harbor.app', symlinks=True)
    (staging / 'Applications').symlink_to('/Applications')
    run('hdiutil', 'create', '-volname', 'Harbor', '-srcfolder', staging, '-ov', '-format', 'UDZO', dmg)
    shutil.rmtree(staging)
    if not args.development:
        run('codesign', '--sign', identity, '--timestamp', dmg)
        run('xcrun', 'notarytool', 'submit', dmg, '--keychain-profile', os.environ['HARBOR_NOTARY_PROFILE'], '--wait')
        run('xcrun', 'stapler', 'staple', dmg)
    print('Packaged ' + str(dmg))

if __name__ == '__main__': main()
