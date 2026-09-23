#!/usr/bin/env python3
"""Download Jira attachments into a directory. Stdlib only — runs wherever Python 3 does.

stdin : a JSON array of attachment objects as the Atlassian MCP `getJiraIssue` returns them
        in `fields.attachment` — each needs "filename" and "content" (the
        …/rest/api/3/attachment/content/<id> URL); other keys are ignored.
stdout: one path per saved file.   stderr: `FAILED <name>: <reason>` per failure.
exit  : 0 all saved · 1 at least one failed · 2 no usable credentials (nothing attempted).

Auth is HTTP basic with the email + personal API token from the credentials file, which is
`credentials.json` next to this script's directory (gitignored; copy credentials.example.json, or let /todoSetup tracker write it)
or the file named by $JIRA_CREDENTIALS_FILE. Jira answers the content URL with a 302 to a
signed S3 link: the Authorization header must NOT travel to that other host (S3 rejects a
request carrying two auth mechanisms), so the redirect handler below drops it on a host change.

    python3 download_attachments.py --dir todoAttachments/PROJ-321 < attachments.json
    python3 download_attachments.py --dir out --dry-run < attachments.json   # list, no fetch
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CREDS = os.path.join(os.path.dirname(HERE), "credentials.json")
EXAMPLE = os.path.join(os.path.dirname(HERE), "credentials.example.json")
ENV_CREDS = "JIRA_CREDENTIALS_FILE"
TIMEOUT = 60


class DropAuthOnHostChange(urllib.request.HTTPRedirectHandler):
    """Follow redirects, but never carry Authorization to a different host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urlsplit(newurl).netloc != urlsplit(req.full_url).netloc:
            new.remove_header("Authorization")
        return new


def load_creds(path):
    """(email, token), or exit 2 with a hint naming the example file."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        sys.stderr.write("no credentials file: %s — copy %s next to it and fill in your "
                         "Atlassian email and API token\n" % (path, os.path.basename(EXAMPLE)))
        sys.exit(2)
    except (OSError, ValueError) as e:
        sys.stderr.write("credentials file unreadable: %s: %s\n" % (path, e))
        sys.exit(2)
    email = (data.get("email") or "").strip() if isinstance(data, dict) else ""
    token = (data.get("token") or "").strip() if isinstance(data, dict) else ""
    if not email or not token or token == "REDACTED":
        sys.stderr.write("credentials file %s has no usable email/token — fill it in as in %s\n"
                         % (path, os.path.basename(EXAMPLE)))
        sys.exit(2)
    return email, token


def unique_path(directory, filename):
    """<dir>/<name>, or <dir>/<name (2)>… when taken; never escapes the directory."""
    name = os.path.basename(filename.replace("\\", "/")) or "attachment"
    stem, ext = os.path.splitext(name)
    candidate = os.path.join(directory, name)
    n = 2
    while os.path.exists(candidate):
        candidate = os.path.join(directory, "%s (%d)%s" % (stem, n, ext))
        n += 1
    return candidate


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", required=True, help="target directory (created if missing)")
    ap.add_argument("--creds", default=os.environ.get(ENV_CREDS) or DEFAULT_CREDS,
                    help="credentials file (default: credentials.json next to the skill, or $%s)" % ENV_CREDS)
    ap.add_argument("--dry-run", action="store_true", help="list what would be saved, fetch nothing")
    args = ap.parse_args()

    try:
        items = json.load(sys.stdin)
    except ValueError as e:
        sys.stderr.write("stdin is not a JSON array of attachments: %s\n" % e)
        sys.exit(1)
    if isinstance(items, dict):  # a whole getJiraIssue result, or its fields, pasted in
        items = (items.get("fields") or items).get("attachment") or []
    if not isinstance(items, list):
        sys.stderr.write("stdin is not a JSON array of attachments\n")
        sys.exit(1)
    items = [a for a in items if isinstance(a, dict) and a.get("content")]
    if not items:
        return 0

    if args.dry_run:
        for a in items:
            print("%s <- %s" % (unique_path(args.dir, a.get("filename") or ""), a["content"]))
        return 0

    email, token = load_creds(args.creds)
    auth = "Basic " + base64.b64encode(("%s:%s" % (email, token)).encode("utf-8")).decode("ascii")
    opener = urllib.request.build_opener(DropAuthOnHostChange())
    os.makedirs(args.dir, exist_ok=True)

    failed = 0
    for a in items:
        name = a.get("filename") or "attachment"
        req = urllib.request.Request(a["content"], headers={"Authorization": auth, "Accept": "*/*"})
        try:
            with opener.open(req, timeout=TIMEOUT) as resp:
                data = resp.read()
        except urllib.error.HTTPError as e:
            sys.stderr.write("FAILED %s: HTTP %s %s\n" % (name, e.code, e.reason))
            failed += 1
            continue
        except (urllib.error.URLError, OSError) as e:
            sys.stderr.write("FAILED %s: %s\n" % (name, getattr(e, "reason", e)))
            failed += 1
            continue
        out = unique_path(args.dir, name)
        with open(out, "wb") as f:
            f.write(data)
        print(os.path.abspath(out))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
