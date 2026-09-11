#!/usr/bin/env python3
"""Report upstream yt-dlp releases for CI review; never installs or publishes code."""
import json
from pathlib import Path
import subprocess

pinned = '2026.07.04'
data = subprocess.check_output(['curl', '--fail', '--silent', '--show-error', '--location', 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'], text=True)
release = json.loads(data)
report = {'component': 'yt-dlp', 'pinned': pinned, 'latest': release['tag_name'], 'reviewNeeded': release['tag_name'] != pinned,
          'releaseURL': release['html_url'], 'action': 'Review upstream changes, update dependency locks, and run the full platform matrix before signing an engine set.'}
output = Path('build/upstream-status.json')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
