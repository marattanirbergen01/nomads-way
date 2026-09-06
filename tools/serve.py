#!/usr/bin/env python3
"""Раздаёт build/ как CDN для разработки. CORS открыт, чтобы Flutter web с другого порта мог качать бандлы."""
import http.server, os, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build')
port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=root, **k)
    def end_headers(s):
        s.send_header('Access-Control-Allow-Origin', '*'); s.send_header('Cache-Control', 'no-store'); super().end_headers()
    def log_message(s, f, *a): sys.stderr.write("%s %s\n" % (s.address_string(), f % a))
print(f"serving {os.path.abspath(root)} on http://localhost:{port}")
http.server.ThreadingHTTPServer(('', port), H).serve_forever()
