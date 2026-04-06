#!/usr/bin/env python3
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PORT = 8765

class UpdaterHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers(204)

    def do_GET(self):
        if self.path == '/status':
            self._set_headers()
            self.wfile.write(json.dumps({'success': True, 'message': 'Updater is alive'}).encode())
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({'success': False, 'error': 'Not found'}).encode())

    def do_POST(self):
        if self.path == '/update':
            self.handle_update()
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({'success': False, 'error': 'Not found'}).encode())

    def handle_update(self):
        result = {'success': False, 'message': ''}

        try:
            self.run_command(['git', 'fetch', '--all', '--prune'])
            self.run_command(['git', 'pull', '--rebase', '--autostash'])
        except subprocess.CalledProcessError as exc:
            try:
                self.run_command(['git', 'reset', '--hard', '@{u}'])
            except subprocess.CalledProcessError as exc2:
                result['message'] = f'Git update failed: {exc2.stderr or exc.stderr or str(exc2)}'
                self._set_headers(500)
                self.wfile.write(json.dumps(result).encode())
                return

        try:
            self.run_command(['bash', str(ROOT / 'media-center-setup.sh')])
        except subprocess.CalledProcessError as exc:
            result['message'] = f'Setup script failed: {exc.stderr or str(exc)}'
            self._set_headers(500)
            self.wfile.write(json.dumps(result).encode())
            return

        result['success'] = True
        result['message'] = 'Updated successfully.'
        self._set_headers()
        self.wfile.write(json.dumps(result).encode())

    def run_command(self, command):
        proc = subprocess.run(
            command,
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        return proc

    def log_message(self, format, *args):
        return


def run_server():
    server = HTTPServer(('127.0.0.1', PORT), UpdaterHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == '__main__':
    run_server()
