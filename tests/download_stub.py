"""Stub-server test for bin/download_attachments.py, run by tests/download.test.sh.

Two local HTTP servers on 127.0.0.1 (different ports = different hosts to the redirect
handler): /content/1 on the first answers 302 to /file/a.txt on the second, the way Jira
redirects to its signed S3 link. Checks: the file lands with the right bytes, the first hop
carried basic auth and the redirected hop none, a name collision gets " (2)", a 404 is
reported and gives exit 1, no credentials file gives exit 2 with the example's name, and a
whole getJiraIssue result pasted on stdin is accepted. Prints ALL OK at the end.
"""
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading

SCRIPT = sys.argv[1]
seen = []


def serve(handler):
    srv = http.server.HTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


class Files(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        seen.append((self.path, self.headers.get("Authorization")))
        if self.path == "/file/a.txt":
            body = b"hello\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


files = serve(Files)


class Jira(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        seen.append((self.path, self.headers.get("Authorization")))
        if self.path == "/content/1":
            self.send_response(302)
            self.send_header("Location", "http://127.0.0.1:%d/file/a.txt" % files.server_port)
            self.end_headers()
        elif self.path == "/content/2":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"second")
        else:
            self.send_response(404)
            self.end_headers()


jira = serve(Jira)
base = "http://127.0.0.1:%d" % jira.server_port

tmp = tempfile.mkdtemp()
creds = os.path.join(tmp, "creds.json")
with open(creds, "w", encoding="utf-8") as f:
    json.dump({"email": "u@example.test", "token": "tok"}, f)
out = os.path.join(tmp, "out")
items = [
    {"filename": "a.txt", "content": base + "/content/1"},
    {"filename": "a.txt", "content": base + "/content/2"},
    {"filename": "missing.png", "content": base + "/nope"},
]


def run(stdin, creds_file):
    return subprocess.run([sys.executable, SCRIPT, "--dir", out, "--creds", creds_file],
                          input=json.dumps(stdin), capture_output=True, text=True)


p = run(items, creds)
assert p.returncode == 1, "one failure → exit 1, got %s: %s" % (p.returncode, p.stderr)
with open(os.path.join(out, "a.txt"), "rb") as f:
    assert f.read() == b"hello\n", "redirected download saved"
with open(os.path.join(out, "a (2).txt"), "rb") as f:
    assert f.read() == b"second", "collision suffix"
assert not os.path.exists(os.path.join(out, "missing.png")), "no file for a 404"
hops = dict(seen)
assert hops["/content/1"] and hops["/content/1"].startswith("Basic "), "first hop authed"
assert hops["/file/a.txt"] is None, "redirected hop must carry no Authorization"
assert "FAILED missing.png: HTTP 404" in p.stderr, p.stderr
assert p.stdout.count("\n") == 2, "one path per saved file"

p2 = run(items[:1], os.path.join(tmp, "none.json"))
assert p2.returncode == 2 and "credentials.example.json" in p2.stderr, (p2.returncode, p2.stderr)

p3 = run({"fields": {"attachment": items[1:2]}}, creds)
assert p3.returncode == 0 and p3.stdout.strip().endswith("a (3).txt"), (p3.stdout, p3.stderr)

p4 = subprocess.run([sys.executable, SCRIPT, "--dir", out, "--dry-run"],
                    input=json.dumps(items[:1]), capture_output=True, text=True)
assert p4.returncode == 0 and "a (4).txt <- " in p4.stdout and not os.path.exists(os.path.join(out, "a (4).txt")), p4.stdout

print("ALL OK")
