#!/usr/bin/env bash
# Read values from .claude/prompt-todo/config.json in bash 3.2+, with jq when it exists and
# Python 3 otherwise. Source this file, then:
#
#   prompt_todo_root                       # the project root (CLAUDE_PROJECT_DIR, git toplevel, or cwd)
#   prompt_todo_py script.py args…       # run Python 3, whatever it is called on this machine
#   config_get '.projectTitle' 'My App'  # a scalar; the default when the file or key is missing
#   config_list '.confirmWords'          # one element per line; empty when missing
#
# Never fails the caller: a missing or broken config yields the defaults, so the hook and the
# skills keep working before the wizard has run.
#
# Runs on macOS, Linux and Windows (Git Bash / MSYS2 — what Claude Code's Bash tool and hooks
# use there; WSL is plain Linux). On Windows the interpreter is usually `python` or the `py`
# launcher rather than `python3`, and paths may arrive with backslashes.

# Backslashes → slashes, so dirname/cd work on a Windows path (`C:\x\y` → `C:/x/y`, which
# Git Bash accepts). A no-op on Unix paths.
prompt_todo_slashes() { printf '%s' "${1//\\//}"; }

# Which command runs Python 3 here: `python3` (Unix, Microsoft Store Python), `python`
# (python.org installers on Windows, some Linux), or the `py -3` launcher (Windows). A
# candidate counts only if it actually runs and is a 3.x — the Windows Store ships a
# `python3.exe` stub that only opens the Store, and `python` may be 2.x. Cached in
# PROMPT_TODO_PY for the process (set it beforehand to force one).
_prompt_todo_py_ok() { "$@" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; }
prompt_todo_py_resolve() {
  if [ -z "${PROMPT_TODO_PY:-}" ]; then
    if _prompt_todo_py_ok python3; then PROMPT_TODO_PY=python3
    elif _prompt_todo_py_ok python; then PROMPT_TODO_PY=python
    elif _prompt_todo_py_ok py -3; then PROMPT_TODO_PY=py
    else PROMPT_TODO_PY=none
    fi
  fi
  [ "$PROMPT_TODO_PY" != none ]
}
# PYTHONUTF8=1: Windows Python would otherwise read config.json and write its output in the
# console code page (cp1252), which cannot hold the arrows and dashes in the rules and the help
# texts. PYTHONDONTWRITEBYTECODE=1: no bin/__pycache__ next to the scripts.
prompt_todo_py() {
  prompt_todo_py_resolve || { echo "prompt-todo: no Python 3 found (tried python3, python, py -3)" >&2; return 127; }
  case "$PROMPT_TODO_PY" in
    py) PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 py -3 "$@" ;;
    *)  PYTHONUTF8=1 PYTHONDONTWRITEBYTECODE=1 "$PROMPT_TODO_PY" "$@" ;;
  esac
}

prompt_todo_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    prompt_todo_slashes "$CLAUDE_PROJECT_DIR"; return
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then printf '%s' "$top"; else pwd; fi
}

prompt_todo_config_file() {
  printf '%s/.claude/prompt-todo/config.json' "$(prompt_todo_root)"
}

_config_has_jq() { command -v jq >/dev/null 2>&1; }
_config_has_py() { prompt_todo_py_resolve; }

# Python fallback: walks a jq-style path of the form .a.b.c (no arrays, no filters). The
# `tr` strips the CR that Windows Python puts before every newline it writes to a pipe —
# without it each confirm word but the last would carry a trailing CR and never match.
_config_py() {
  # $1 = mode (get|list), $2 = file, $3 = path
  prompt_todo_py - "$1" "$2" "$3" <<'PY' 2>/dev/null | tr -d '\r'
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
  file="$(prompt_todo_config_file)"
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
  file="$(prompt_todo_config_file)"
  [ -f "$file" ] || return 0
  if _config_has_jq; then
    jq -r "($path // []) | .[]" "$file" 2>/dev/null || true
  elif _config_has_py; then
    _config_py list "$file" "$path" || true
  fi
}
