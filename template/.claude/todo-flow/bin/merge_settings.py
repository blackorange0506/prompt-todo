#!/usr/bin/env python3
"""Add (or remove) the todo-confirm hook in a Claude Code settings.json, keeping everything else.

Usage:
  merge_settings.py <settings.json>            # add the UserPromptSubmit hook if absent
  merge_settings.py <settings.json> --remove   # remove every hook whose command mentions todo-confirm.sh
  merge_settings.py <settings.json> --check    # exit 0 if present, 1 if absent; writes nothing

The file is created if missing. A hook is "present" when any UserPromptSubmit command contains
"todo-confirm.sh", so a user who moved or rewrote the command keeps their version.
"""
import json
import os
import sys

MARK = "todo-confirm.sh"
HOOK = {
    "type": "command",
    "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/todo-confirm.sh 2>/dev/null || true",
    "timeout": 10,
    "statusMessage": "todo confirm check",
}


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        return {}
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        sys.stderr.write("[merge_settings] %s is not valid JSON: %s\n" % (path, e))
        sys.exit(2)
    if not isinstance(data, dict):
        sys.stderr.write("[merge_settings] %s: top level must be an object\n" % path)
        sys.exit(2)
    return data


def save(path, data):
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def groups(data):
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        sys.stderr.write("[merge_settings] \"hooks\" must be an object\n")
        sys.exit(2)
    lst = hooks.setdefault("UserPromptSubmit", [])
    if not isinstance(lst, list):
        sys.stderr.write("[merge_settings] hooks.UserPromptSubmit must be a list\n")
        sys.exit(2)
    return lst


def present(data):
    for g in data.get("hooks", {}).get("UserPromptSubmit", []) or []:
        for h in (g.get("hooks") or []) if isinstance(g, dict) else []:
            if isinstance(h, dict) and MARK in str(h.get("command", "")):
                return True
    return False


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "--add"
    data = load(path)
    if mode == "--check":
        sys.exit(0 if present(data) else 1)
    if mode == "--remove":
        if not present(data):
            print("[merge_settings] hook not present in %s" % path)
            return
        lst = groups(data)
        kept = []
        for g in lst:
            if isinstance(g, dict):
                g["hooks"] = [h for h in (g.get("hooks") or []) if not (isinstance(h, dict) and MARK in str(h.get("command", "")))]
                if g["hooks"] or g.get("matcher"):
                    kept.append(g)
            else:
                kept.append(g)
        data["hooks"]["UserPromptSubmit"] = kept
        if not kept:
            del data["hooks"]["UserPromptSubmit"]
        if not data["hooks"]:
            del data["hooks"]
        save(path, data)
        print("[merge_settings] removed the todo-confirm hook from %s" % path)
        return
    if present(data):
        print("[merge_settings] hook already present in %s" % path)
        return
    groups(data).append({"hooks": [dict(HOOK)]})
    save(path, data)
    print("[merge_settings] added the todo-confirm hook to %s" % path)


if __name__ == "__main__":
    main()
