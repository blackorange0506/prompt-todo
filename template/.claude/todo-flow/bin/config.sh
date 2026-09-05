#!/usr/bin/env bash
# Read values from .claude/todo-flow/config.json in bash 3.2+, with jq when it exists and
# python3 otherwise. Source this file, then:
#
#   todo_flow_root                       # the project root (CLAUDE_PROJECT_DIR, git toplevel, or cwd)
#   config_get '.projectTitle' 'My App'  # a scalar; the default when the file or key is missing
#   config_list '.confirmWords'          # one element per line; empty when missing
#
# Never fails the caller: a missing or broken config yields the defaults, so the hook and the
# skills keep working before the wizard has run.

todo_flow_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"; return
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then printf '%s' "$top"; else pwd; fi
}

todo_flow_config_file() {
  printf '%s/.claude/todo-flow/config.json' "$(todo_flow_root)"
}

_config_has_jq() { command -v jq >/dev/null 2>&1; }
_config_has_py() { command -v python3 >/dev/null 2>&1; }

# Python fallback: walks a jq-style path of the form .a.b.c (no arrays, no filters).
_config_py() {
  # $1 = mode (get|list), $2 = file, $3 = path
  python3 - "$1" "$2" "$3" <<'PY' 2>/dev/null
import json, sys
mode, path, jqpath = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(1)
cur = data
for part in [p for p in jqpath.split(".") if p]:
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(1)
if mode == "get":
    if cur is None or isinstance(cur, (dict, list)):
        sys.exit(1)
    print(cur if not isinstance(cur, bool) else str(cur).lower())
else:
    if not isinstance(cur, list):
        sys.exit(1)
    for x in cur:
        print(x)
PY
}

config_get() {
  local path="$1" default="${2:-}" file out
  file="$(todo_flow_config_file)"
  if [ -f "$file" ]; then
    if _config_has_jq; then
      out="$(jq -r "$path // empty" "$file" 2>/dev/null || true)"
    elif _config_has_py; then
      out="$(_config_py get "$file" "$path" || true)"
    fi
  fi
  if [ -n "${out:-}" ]; then printf '%s' "$out"; else printf '%s' "$default"; fi
}

config_list() {
  local path="$1" file
  file="$(todo_flow_config_file)"
  [ -f "$file" ] || return 0
  if _config_has_jq; then
    jq -r "($path // []) | .[]" "$file" 2>/dev/null || true
  elif _config_has_py; then
    _config_py list "$file" "$path" || true
  fi
}
