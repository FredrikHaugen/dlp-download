#!/usr/bin/env python3
"""Build LGPL FFmpeg + LAME for macOS 14, without Homebrew runtime libraries."""
from pathlib import Path
import os
import shutil
import subprocess
import tarfile
from bootstrap_engines import CACHE, VENDOR, ENGINE, fetch, run

def unpack(archive, folder):
    if folder.exists(): return
    with tarfile.open(archive) as contents:
        contents.extractall(VENDOR, filter='data')

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    sdk = run('xcrun', '--sdk', 'macosx', '--show-sdk-path').strip()
    prefix = VENDOR / 'portable-prefix'
    common = '-O2 -mmacosx-version-min=14.0 -isysroot ' + sdk
    env = dict(os.environ, SDKROOT=sdk, MACOSX_DEPLOYMENT_TARGET='14.0', CC=run('xcrun','-f','clang').strip(), CXX=run('xcrun','-f','clang++').strip(), CFLAGS=common + ' -Wno-implicit-function-declaration', CXXFLAGS=common, LDFLAGS='-mmacosx-version-min=14.0 -isysroot ' + sdk, PKG_CONFIG_PATH=str(prefix / 'lib/pkgconfig'))
    lame_archive = fetch('https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz', 'lame-3.100.tar.gz')
    lame = VENDOR / 'lame-3.100'
    unpack(lame_archive, lame)
    if not (prefix / 'lib/libmp3lame.a').exists():
        with (CACHE / 'lame-build.log').open('w') as log:
            subprocess.run(['./configure', '--prefix=' + str(prefix), '--disable-shared', '--enable-static', '--disable-frontend', '--disable-decoder'], cwd=lame, env=env, stdout=log, stderr=log, check=True)
            subprocess.run(['make', '-j4', 'install'], cwd=lame, env=env, stdout=log, stderr=log, check=True)
    ffmpeg_archive = fetch('https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz', 'ffmpeg-8.1.2.tar.xz')
    ffmpeg = VENDOR / 'ffmpeg-8.1.2'
    unpack(ffmpeg_archive, ffmpeg)
    if not (ffmpeg / 'ffmpeg').exists():
        with (CACHE / 'ffmpeg-build.log').open('w') as log:
            subprocess.run(['./configure', '--prefix=' + str(prefix), '--cc=' + env['CC'], '--cxx=' + env['CXX'], '--sysroot=' + sdk,
                '--extra-cflags=' + common + ' -I' + str(prefix / 'include'), '--extra-ldflags=' + env['LDFLAGS'] + ' -L' + str(prefix / 'lib'),
                '--disable-autodetect', '--disable-shared', '--enable-static', '--disable-doc', '--disable-debug', '--disable-ffplay', '--disable-x86asm',
                '--enable-libmp3lame', '--enable-videotoolbox', '--enable-audiotoolbox', '--enable-securetransport'], cwd=ffmpeg, env=env, stdout=log, stderr=log, check=True)
            subprocess.run(['make', '-j8'], cwd=ffmpeg, env=env, stdout=log, stderr=log, check=True)
    # This directory contains only generated vendored dependencies.
    frameworks = ENGINE / 'Frameworks'
    if frameworks.exists(): shutil.rmtree(frameworks)
    frameworks.mkdir()
    for name in ['ffmpeg', 'ffprobe']:
        target = ENGINE / 'MacOS' / name
        shutil.copy2(ffmpeg / name, target)
        target.chmod(0o755)
        subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
        print(run(str(target), '-version').splitlines()[0])
    notices = ENGINE / 'Resources/ThirdParty'
    notices.mkdir(parents=True, exist_ok=True)
    for path in [ffmpeg / 'COPYING.LGPLv2.1', lame / 'COPYING']:
        shutil.copy2(path, notices / (path.parent.name + '-' + path.name))
    sources = ENGINE / 'Resources/Sources'
    sources.mkdir(parents=True, exist_ok=True)
    for archive in [ffmpeg_archive, lame_archive, CACHE / 'aria2-1.37.0.tar.xz']:
        shutil.copy2(archive, sources / archive.name)
    print('Portable FFmpeg and LAME built for macOS 14.')

if __name__ == '__main__': main()
