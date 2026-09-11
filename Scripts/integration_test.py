#!/usr/bin/env python3
"""Run real engines against only local, generated media and HTTP fixtures."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
serve_only = '--serve' in sys.argv
ui_only = '--ui-only' in sys.argv
ui_tests = '--ui' in sys.argv or ui_only
engine_args = [a for a in sys.argv[1:] if a not in ['--serve', '--ui', '--ui-only']]
engine = Path(engine_args[0]).resolve() if engine_args else root / 'Vendor/EngineSet'
fixtures = root / 'build/fixtures'
fixtures.mkdir(parents=True, exist_ok=True)
media = fixtures / 'sample.mp4'
subprocess.run([str(engine / 'MacOS/ffmpeg'), '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'color=c=0x1d6674:s=640x360:r=24', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '2', '-c:v', 'h264_videotoolbox', '-b:v', '500k', '-c:a', 'aac', '-movflags', '+faststart', str(media)], check=True)
server = subprocess.Popen([sys.executable, str(root / 'Scripts/fixture_server.py'), '--media', str(media)], stdout=subprocess.PIPE, text=True)
try:
    port = server.stdout.readline().strip()
    if not port.isdigit(): raise SystemExit('Fixture server did not start')
    print('Fixture server port: ' + port, flush=True)
    if serve_only:
        server.wait()
        raise SystemExit(0)
    env = dict(os.environ, HARBOR_FIXTURE_URL='http://127.0.0.1:' + port, HARBOR_ENGINE_ROOT=str(engine))
    result = subprocess.CompletedProcess([], 0) if ui_only else subprocess.run(['swift', 'test', '--scratch-path', 'build/swift-package'], cwd=root, env=env)
    if result.returncode == 0 and ui_tests:
        (root / 'build/ui-fixture-url').write_text('http://127.0.0.1:' + port)
        result = subprocess.run(['xcodebuild', '-project', 'Harbor.xcodeproj', '-scheme', 'Harbor', '-destination', 'platform=macOS', '-derivedDataPath', 'build/xcode', '-only-testing:HarborUITests', 'test'], cwd=root, env=env)
    raise SystemExit(result.returncode)
finally:
    server.terminate(); server.wait(timeout=10)
