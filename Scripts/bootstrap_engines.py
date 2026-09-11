#!/usr/bin/env python3
"""Fetch pinned official sources and assemble a relocatable, host-architecture engine set.

Requires Xcode command-line tools, curl, make, and installed ffmpeg/deno.
No system installation is performed. Re-run on Intel to build the Intel engine set.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'Vendor'
CACHE = VENDOR / 'cache'
ENGINE = VENDOR / 'EngineSet'
VERSION = '2026.07.04-1'

def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs)

def fetch(url, name):
    target = CACHE / name
    if not target.exists():
        subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--silent', '--show-error', url, '-o', str(target) + '.part'], check=True)
        Path(str(target) + '.part').replace(target)
    return target

def bundle(source, destination, seen):
    source = Path(source).resolve()
    if source in seen:
        return seen[source]
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    destination.chmod(0o755)
    seen[source] = destination
    dependencies = run('otool', '-L', str(source)).splitlines()[1:]
    for line in dependencies:
        dep = line.strip().split(' (')[0]
        if dep.startswith('/opt/homebrew/') or dep.startswith('/usr/local/'):
            if Path(dep).resolve() == source:
                continue
            target = ENGINE / 'Frameworks' / Path(dep).name
            bundle(dep, target, seen)
            relative = os.path.relpath(target, destination.parent)
            subprocess.run(['install_name_tool', '-change', dep, '@loader_path/' + relative, str(destination)], check=True, capture_output=True)
    if destination.suffix == '.dylib':
        subprocess.run(['install_name_tool', '-id', '@rpath/' + destination.name, str(destination)], check=True, capture_output=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(destination)], check=True, capture_output=True)
    return destination

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    (ENGINE / 'MacOS').mkdir(parents=True, exist_ok=True)
    (ENGINE / 'Resources').mkdir(parents=True, exist_ok=True)
    base = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.07.04/'
    sums = fetch(base + 'SHA2-256SUMS', 'yt-dlp-SHA2-256SUMS')
    yt = fetch(base + 'yt-dlp_macos', 'yt-dlp_macos')
    expected = next(line.split()[0] for line in sums.read_text().splitlines() if line.split()[-1].lstrip('*') == 'yt-dlp_macos')
    if hashlib.sha256(yt.read_bytes()).hexdigest() != expected:
        raise SystemExit('yt-dlp checksum mismatch')
    # Checksums fetched over HTTPS are bootstrap provenance, not the app update trust root.
    shutil.copy2(yt, ENGINE / 'MacOS' / 'yt-dlp')
    (ENGINE / 'MacOS' / 'yt-dlp').chmod(0o755)
    source = fetch('https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.xz', 'aria2-1.37.0.tar.xz')
    build = VENDOR / 'aria2-1.37.0'
    if not build.exists():
        with tarfile.open(source) as archive:
            for item in archive.getmembers():
                if item.name.startswith('/') or '..' in Path(item.name).parts:
                    raise SystemExit('Unsafe source archive')
            archive.extractall(VENDOR, filter='data')
    aria = build / 'src' / 'aria2c'
    if not aria.exists():
        sdk = run('xcrun', '--sdk', 'macosx', '--show-sdk-path').strip()
        env = dict(os.environ, SDKROOT=sdk, CC=run('xcrun', '-f', 'clang').strip(), CXX=run('xcrun', '-f', 'clang++').strip(), MACOSX_DEPLOYMENT_TARGET='14.0', CXXFLAGS='-O2 -mmacosx-version-min=14.0 -isysroot ' + sdk, CFLAGS='-O2 -mmacosx-version-min=14.0 -isysroot ' + sdk)
        with (CACHE / 'aria2-build.log').open('w') as log:
            subprocess.run(['./configure', '--with-appletls', '--without-openssl', '--without-gnutls', '--without-libssh2', '--without-libgcrypt', '--without-libnettle', '--without-libxml2', '--without-sqlite3', '--disable-nls'], cwd=build, env=env, stdout=log, stderr=log, check=True)
            subprocess.run(['make', '-j4'], cwd=build, env=env, stdout=log, stderr=log, check=True)
    seen = {}
    for name, source_path in [('aria2c', aria), ('ffmpeg', shutil.which('ffmpeg')), ('ffprobe', shutil.which('ffprobe')), ('deno', shutil.which('deno'))]:
        if source_path is None:
            raise SystemExit('Install ' + name + ' before bootstrapping engines.')
        bundle(source_path, ENGINE / 'MacOS' / name, seen)
    versions = {}
    for name in ['yt-dlp', 'aria2c', 'ffmpeg', 'ffprobe', 'deno']:
        args = ['-version'] if name.startswith('ff') else ['--version']
        versions[name] = run(str(ENGINE / 'MacOS' / name), *args).splitlines()[0]
    manifest = {'version': VERSION, 'architecture': platform.machine(), 'components': versions,
                'files': {str(p.relative_to(ENGINE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in ENGINE.rglob('*') if p.is_file()},
                'releaseReady': False,
                'note': 'Local development engine set. Public release requires license/source audit and Developer ID signing.'}
    (ENGINE / 'Resources' / 'engine-set.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copy2(build / 'COPYING', ENGINE / 'Resources' / 'aria2-COPYING')
    print(json.dumps(versions, indent=2))

if __name__ == '__main__':
    main()
