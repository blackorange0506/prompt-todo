#!/usr/bin/env bash
#
# uninstall.sh — remove what install.sh added to a project.
#
#   bash /path/to/prompt-todo/uninstall.sh [--target DIR] [--keep-config] [--dry-run]
#
# Removes the package files listed in .claude/prompt-todo/MANIFEST, the hook entry in
# .claude/settings.json, the import line in CLAUDE.md and the .gitignore entries. Keeps every
# TODO.*.md file, the attachments directory and — with --keep-config — config.json.
# Files you added under .claude/skills/appNavigation are never deleted; if any exist the
# directory is left in place and you are told. Runs on macOS, Linux and Windows (Git Bash).

set -eu

TARGET="$(pwd)"
KEEP_CONFIG=0
DRY=0

log()  { printf '\033[0;36m[prompt-todo]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[prompt-todo WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[prompt-todo ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
dry()  { printf '\033[0;35m[dry-run]\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || err "--target needs a directory"; TARGET="$2"; shift 2 ;;
    --target=*) TARGET="${1#--target=}"; shift ;;
    --keep-config) KEEP_CONFIG=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "unknown argument: $1" ;;
  esac
done

TARGET="$(cd "$TARGET" && pwd)"
FLOW="$TARGET/.claude/prompt-todo"
[ -f "$FLOW/MANIFEST" ] || err "no .claude/prompt-todo/MANIFEST in $TARGET — nothing installed here (or an older install; delete .claude/prompt-todo, .claude/hooks/todo-confirm.sh and .claude/skills/todo* by hand)"

# Python 3 by whatever name it has here (config.sh's prompt_todo_py); an install older than
# that helper falls back to python3.
# shellcheck source=template/.claude/prompt-todo/bin/config.sh
[ -f "$FLOW/bin/config.sh" ] && . "$FLOW/bin/config.sh"
command -v prompt_todo_py >/dev/null 2>&1 || prompt_todo_py() { python3 "$@"; }

rm_file() {
  local f="$TARGET/$1"
  [ -e "$f" ] || return 0
  if [ "$DRY" = 1 ]; then dry "rm $1"; else rm -f "$f"; fi
}

# The hook first, while merge_settings.py is still there.
SETTINGS="$TARGET/.claude/settings.json"
if [ -f "$SETTINGS" ] && prompt_todo_py "$FLOW/bin/merge_settings.py" "$SETTINGS" --check 2>/dev/null; then
  if [ "$DRY" = 1 ]; then dry "remove the hook from .claude/settings.json"; else prompt_todo_py "$FLOW/bin/merge_settings.py" "$SETTINGS" --remove; fi
fi

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  rm_file "$rel"
done < "$FLOW/MANIFEST"
for extra in .claude/prompt-todo/RULES.md .claude/prompt-todo/VERSION .claude/prompt-todo/MANIFEST .claude/prompt-todo/config.json.bak; do
  rm_file "$extra"
done
if [ "$KEEP_CONFIG" = 1 ]; then
  log "keeping .claude/prompt-todo/config.json"
else
  rm_file .claude/prompt-todo/config.json
fi

CLAUDE_MD="$TARGET/CLAUDE.md"
if [ -f "$CLAUDE_MD" ] && grep -qF '@.claude/prompt-todo/RULES.md' "$CLAUDE_MD"; then
  if [ "$DRY" = 1 ]; then dry "remove the import line from CLAUDE.md"; else
    prompt_todo_py - "$CLAUDE_MD" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
out = [l for l in lines if l.strip() not in ("@.claude/prompt-todo/RULES.md", "# Prompt TODO")]
open(p, "w", encoding="utf-8").write("\n".join(out))
PY
    log "CLAUDE.md: import line removed"
  fi
fi

# The .gitignore entry for the attachments directory stays: it may hold downloaded files the
# user wants kept out of git. The .gitattributes lines install.sh added go.
GITATTRIBUTES="$TARGET/.gitattributes"
if [ -f "$GITATTRIBUTES" ] && grep -qF '.claude/prompt-todo/bin/* text eol=lf' "$GITATTRIBUTES"; then
  if [ "$DRY" = 1 ]; then dry "remove the prompt-todo lines from .gitattributes"; else
    grep -vxF -e '.claude/hooks/*.sh text eol=lf' -e '.claude/prompt-todo/bin/* text eol=lf' "$GITATTRIBUTES" > "$GITATTRIBUTES.tmp" || true
    if [ -s "$GITATTRIBUTES.tmp" ]; then mv "$GITATTRIBUTES.tmp" "$GITATTRIBUTES"; else rm -f "$GITATTRIBUTES.tmp" "$GITATTRIBUTES"; fi
    log ".gitattributes: prompt-todo lines removed"
  fi
fi

# Empty directories left behind.
if [ "$DRY" = 0 ]; then
  for d in .claude/skills/todoSetup .claude/skills/todoArchive .claude/skills/todoFromTicket .claude/skills/todoIdealPrompt \
           .claude/skills/todoIdealAll .claude/skills/todoIdealize .claude/skills/todoNumber .claude/skills/todoReverse .claude/skills/todoMarkCode .claude/skills/todoScore .claude/skills/todoHelp .claude/prompt-todo/bin .claude/prompt-todo .claude/hooks .claude/skills/appNavigation .claude/skills; do
    [ -d "$TARGET/$d" ] && rmdir "$TARGET/$d" 2>/dev/null || true
  done
  APP="$TARGET/.claude/skills/appNavigation"
  if [ -d "$APP" ]; then
    find "$APP" -type d -empty -delete 2>/dev/null || true
    if [ -d "$APP" ]; then
      warn "kept $APP — it still holds your own files ($(cd "$APP" && find . -type f | sed 's|^\./||' | tr '\n' ' '))"
    fi
  fi
fi
log "prompt-todo removed from $TARGET (TODO.*.md files untouched)"
