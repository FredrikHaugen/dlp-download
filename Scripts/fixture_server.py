#!/usr/bin/env python3
"""Deterministic local-only download fixtures. Prints its ephemeral port on stdout."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import time

parser = argparse.ArgumentParser()
parser.add_argument('--media', type=Path, required=True)
args = parser.parse_args()
media = args.media.read_bytes()
payload = bytes(range(256)) * 32768

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_HEAD(self):
        self.respond(False)
    def do_GET(self):
        self.respond(True)
    def respond(self, body):
        route = self.path.split('?')[0]
        if route == '/redirect':
            self.send_response(302); self.send_header('Location', '/file'); self.end_headers(); return
        if route == '/not-found':
            self.send_error(404); return
        if route == '/head-denied' and not body:
            self.send_error(405); return
        if route == '/playlist':
            data = b'<html><head><title>Harbor playlist fixture</title></head><body><video controls src="/sample.mp4?item=one"></video><video controls src="/sample.mp4?item=two"></video></body></html>'
            kind = 'text/html'
        elif route in ['/page', '/misleading.mp4', '/live']:
            data = b'<html><head><title>Harbor test film</title></head><body><video controls src="/sample.mp4"></video></body></html>'
            kind = 'text/html'
        elif route == '/sample.mp4':
            data = media; kind = 'video/mp4'
        elif route == '/torrent':
            data = b'fixture'; kind = 'application/x-bittorrent'
        else:
            data = payload; kind = 'application/octet-stream'
        start, end = 0, len(data)-1
        range_header = self.headers.get('Range') if route != '/no-range' else None
        if range_header and range_header.startswith('bytes='):
            value = range_header[6:].split(',')[0].split('-')
            start = int(value[0]); end = int(value[1]) if value[1] else end
            end = min(end, len(data)-1)
            if start >= len(data):
                self.send_response(416); self.end_headers(); return
        self.send_response(206 if range_header else 200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(end-start+1))
        self.send_header('ETag', '"harbor-fixture-v1"')
        if route != '/no-range': self.send_header('Accept-Ranges', 'bytes')
        if kind == 'application/octet-stream': self.send_header('Content-Disposition', 'attachment; filename="Harbor fixture.bin"')
        if range_header: self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
        self.end_headers()
        if body:
            try:
                for offset in range(start, end+1, 65536):
                    self.wfile.write(data[offset:min(end+1, offset+65536)])
                    if route == '/slow': time.sleep(0.03)
            except (BrokenPipeError, ConnectionResetError): pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
