#!/usr/bin/env bash
#
# install.sh — install prompt-todo into a project.
#
#   bash /path/to/prompt-todo/install.sh [--target DIR] [--without-app-navigation]
#                                             [--dry-run] [--force]
#
# Run it from inside the project (or name it with --target). Idempotent: re-running upgrades
# the package files and leaves your config, todo files and credentials alone.
#
# What it does:
#   1. preflight: git repo (warning only), Python 3 (required: python3, python or py -3), jq (optional)
#   2. copies template/.claude/** into <target>/.claude/ (package files, always overwritten)
#   3. adds the works/fixed hook to <target>/.claude/settings.json (merge, never overwrite)
#   4. appends `@.claude/prompt-todo/RULES.md` to <target>/CLAUDE.md (created if missing)
#   5. adds the attachments directory to <target>/.gitignore
#   6. writes .claude/prompt-todo/config.json from the example if absent, renders RULES.md,
#      stamps VERSION and writes MANIFEST (the list uninstall.sh removes)
#
# bash 3.2 is enough (macOS /bin/bash); on Windows run it from Git Bash (what Claude Code uses there).

set -eu

SRC="$(cd "$(dirname "${BASH_SOURCE[0]//\\//}")" && pwd)"
TEMPLATE="$SRC/template/.claude"
# shellcheck source=template/.claude/prompt-todo/bin/config.sh
. "$TEMPLATE/prompt-todo/bin/config.sh"   # prompt_todo_py: python3 / python / py -3"
TARGET="$(pwd)"
WITH_APP_NAV=1
DRY=0
FORCE=0

log()  { printf '\033[0;36m[prompt-todo]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[prompt-todo WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[prompt-todo ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
dry()  { printf '\033[0;35m[dry-run]\033[0m %s\n' "$*"; }

usage() {
  sed -n '2,/^# bash 3.2/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || err "--target needs a directory"; TARGET="$(prompt_todo_slashes "$2")"; shift 2 ;;
    --target=*) TARGET="$(prompt_todo_slashes "${1#--target=}")"; shift ;;
    --without-app-navigation) WITH_APP_NAV=0; shift ;;
    --with-app-navigation) WITH_APP_NAV=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; err "unknown argument: $1" ;;
  esac
done

[ -d "$TEMPLATE" ] || err "template not found at $TEMPLATE — run this script from a prompt-todo checkout"
[ -d "$TARGET" ] || err "target is not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$SRC" ] || err "the target is the prompt-todo checkout itself; run from your project (or pass --target)"

# ---- 1. preflight -----------------------------------------------------------

prompt_todo_py_resolve || err "Python 3 is required (it renders the rules and merges settings.json); none of python3, python, py -3 works here"
if command -v jq >/dev/null 2>&1; then JQ=1; else JQ=0; fi
if git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1; then
  # cd && pwd: Git for Windows prints C:/x/y while Git Bash's pwd says /c/x/y; compare like with like.
  GIT_ROOT="$(cd "$(git -C "$TARGET" rev-parse --show-toplevel)" && pwd)"
  [ "$GIT_ROOT" = "$TARGET" ] || warn "target $TARGET is inside the git repo $GIT_ROOT but is not its root; todo files are looked up at the repo root"
  NAME="$(git -C "$TARGET" config user.name 2>/dev/null || true)"
  [ -n "$NAME" ] || warn "git config user.name is empty — set it (git config user.name <name>) before the first todo prompt; /todoSetup offers to"
else
  warn "$TARGET is not a git repository; the todo file name will fall back to \$USER until it is one"
fi

log "installing prompt-todo $(cat "$SRC/VERSION") into $TARGET"
[ "$JQ" = 1 ] || log "jq not found; the hook and the skills will use Python ($PROMPT_TODO_PY) instead (fine)"

# Two facts the closing message depends on. Claude Code watches .claude/skills/ for live changes
# only when the directory existed at session start, so a session that is already open in a project
# without one will not see the new skills until it is restarted. CLAUDECODE is set in the
# environment of Claude Code's own terminal (the Bash tool).
HAD_SKILLS_DIR=0; [ -d "$TARGET/.claude/skills" ] && HAD_SKILLS_DIR=1
INSIDE_CLAUDE=0; [ -n "${CLAUDECODE:-}" ] && INSIDE_CLAUDE=1

# ---- 2. copy the package files ---------------------------------------------

MANIFEST_TMP="$(mktemp "${TMPDIR:-/tmp}/prompt-todo-manifest.XXXXXX")"
trap 'rm -f "$MANIFEST_TMP"' EXIT

copy_one() {
  # $1 = path relative to template/.claude
  local rel="$1" src="$TEMPLATE/$1" dst="$TARGET/.claude/$1"
  printf '.claude/%s\n' "$rel" >> "$MANIFEST_TMP"
  if [ "$DRY" = 1 ]; then
    if [ -f "$dst" ]; then
      if cmp -s "$src" "$dst"; then :; else dry "update .claude/$rel"; fi
    else
      dry "add    .claude/$rel"
    fi
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  case "$rel" in *.sh|*.py|*.mjs) chmod +x "$dst" ;; esac
}

( cd "$TEMPLATE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) | while IFS= read -r rel; do
  case "$rel" in
    .DS_Store|*/.DS_Store) continue ;;
    skills/appNavigation/*) [ "$WITH_APP_NAV" = 1 ] || continue ;;
  esac
  copy_one "$rel"
done
[ "$DRY" = 1 ] || log "package files copied to .claude/ ($(wc -l < "$MANIFEST_TMP" | tr -d ' ') files)"

# 0.1.2 renamed /todoIdealize to /todoIdealAll; an upgrade would otherwise leave both skills behind.
OLD_SKILL="$TARGET/.claude/skills/todoIdealize"
if [ -d "$OLD_SKILL" ]; then
  if [ "$DRY" = 1 ]; then dry "remove .claude/skills/todoIdealize (renamed to todoIdealAll)"; else
    rm -rf "$OLD_SKILL" && log "removed .claude/skills/todoIdealize (renamed to todoIdealAll)"
  fi
fi

FLOW="$TARGET/.claude/prompt-todo"
BIN="$TEMPLATE/prompt-todo/bin"   # the copy in the target may not exist on --dry-run

# ---- 3. hook in settings.json ---------------------------------------------------

SETTINGS="$TARGET/.claude/settings.json"
if prompt_todo_py "$BIN/merge_settings.py" "$SETTINGS" --check 2>/dev/null; then
  log "hook already wired in .claude/settings.json"
elif [ "$DRY" = 1 ]; then
  dry "add the UserPromptSubmit hook to .claude/settings.json"
else
  prompt_todo_py "$BIN/merge_settings.py" "$SETTINGS"
fi

# ---- 4. CLAUDE.md import --------------------------------------------------------

CLAUDE_MD="$TARGET/CLAUDE.md"
IMPORT='@.claude/prompt-todo/RULES.md'
if [ -f "$CLAUDE_MD" ] && grep -qF "$IMPORT" "$CLAUDE_MD"; then
  log "CLAUDE.md already imports the rules"
elif [ "$DRY" = 1 ]; then
  dry "append '$IMPORT' to CLAUDE.md$([ -f "$CLAUDE_MD" ] || printf ' (new file)')"
else
  if [ -f "$CLAUDE_MD" ]; then
    # keep a trailing newline before the import line
    [ -z "$(tail -c 1 "$CLAUDE_MD")" ] || printf '\n' >> "$CLAUDE_MD"
    printf '\n# Prompt TODO\n%s\n' "$IMPORT" >> "$CLAUDE_MD"
  else
    printf '# Project notes for Claude\n\n# Prompt TODO\n%s\n' "$IMPORT" > "$CLAUDE_MD"
  fi
  log "CLAUDE.md imports $IMPORT"
fi

# ---- 5. .gitignore --------------------------------------------------------------

ATTACH_DIR="todoAttachments"
if [ -f "$FLOW/config.json" ]; then
  v="$(prompt_todo_py -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("attachmentsDir") or "")
except Exception: pass' "$FLOW/config.json" 2>/dev/null || true)"
  [ -n "$v" ] && ATTACH_DIR="$v"
fi
GITIGNORE="$TARGET/.gitignore"
ensure_ignored() {
  local line="$1"
  if [ -f "$GITIGNORE" ] && grep -qxF "$line" "$GITIGNORE"; then return; fi
  if [ "$DRY" = 1 ]; then dry "add '$line' to .gitignore"; return; fi
  if [ -f "$GITIGNORE" ] && [ -n "$(tail -c 1 "$GITIGNORE")" ]; then printf '\n' >> "$GITIGNORE"; fi
  printf '%s\n' "$line" >> "$GITIGNORE"
  log ".gitignore: $line"
}
ensure_ignored "${ATTACH_DIR%/}/"

# ---- 5b. .gitattributes: the scripts must stay LF ----------------------------------
# A Windows checkout with core.autocrlf=true would turn them into CRLF, which bash cannot run.

GITATTRIBUTES="$TARGET/.gitattributes"
ensure_attr() {
  local line="$1"
  if [ -f "$GITATTRIBUTES" ] && grep -qxF "$line" "$GITATTRIBUTES"; then return; fi
  if [ "$DRY" = 1 ]; then dry "add '$line' to .gitattributes"; return; fi
  if [ -f "$GITATTRIBUTES" ] && [ -n "$(tail -c 1 "$GITATTRIBUTES")" ]; then printf '\n' >> "$GITATTRIBUTES"; fi
  printf '%s\n' "$line" >> "$GITATTRIBUTES"
  log ".gitattributes: $line"
}
ensure_attr ".claude/hooks/*.sh text eol=lf"
ensure_attr ".claude/prompt-todo/bin/* text eol=lf"

# ---- 6. config, rules, version, manifest -------------------------------------------

if [ "$DRY" = 1 ]; then
  if [ -f "$FLOW/config.json" ]; then
    [ "$FORCE" = 1 ] && dry "reset .claude/prompt-todo/config.json from the example (backup: config.json.bak)"
  else
    dry "write .claude/prompt-todo/config.json from the example (tag table trimmed by /todoSetup tags, no tracker)"
  fi
  dry "render .claude/prompt-todo/RULES.md, write VERSION and MANIFEST"
  [ "$HAD_SKILLS_DIR" = 1 ] || dry "note: .claude/skills/ is new; a Claude Code session already open in $TARGET will need a restart to see the skills"
  log "dry run finished; nothing was written"
  exit 0
fi

if [ -f "$FLOW/config.json" ] && [ "$FORCE" = 1 ]; then
  cp "$FLOW/config.json" "$FLOW/config.json.bak"
  cp "$FLOW/config.example.json" "$FLOW/config.json"
  log "config.json reset from the example (--force); previous copy in config.json.bak"
elif [ ! -f "$FLOW/config.json" ]; then
  cp "$FLOW/config.example.json" "$FLOW/config.json"
  log "config.json written with the defaults (edit it with /todoSetup)"
fi
prompt_todo_py "$FLOW/bin/render_rules.py" --check >/dev/null || err "config.json is invalid; fix it or re-run with --force"
prompt_todo_py "$FLOW/bin/render_rules.py" >/dev/null
cp "$SRC/VERSION" "$FLOW/VERSION"
LC_ALL=C sort -u "$MANIFEST_TMP" > "$FLOW/MANIFEST"
log "rules rendered to .claude/prompt-todo/RULES.md"

cat <<DONE

Installed prompt-todo $(cat "$SRC/VERSION") in $TARGET
  rules:    .claude/prompt-todo/RULES.md   (imported from CLAUDE.md)
  config:   .claude/prompt-todo/config.json
  skills:   /todoSetup /todoFromTicket /todoIdealPrompt /todoIdealAll /todoNumber /todoReverse /todoArchive /todoMarkCode /todoScore /todoHelp$([ "$WITH_APP_NAV" = 1 ] && printf ' /appNavigation (placeholder)')

DONE

# The closing advice depends on whether a running Claude Code session can see the new skills.
if [ "$HAD_SKILLS_DIR" = 0 ] && [ "$INSIDE_CLAUDE" = 1 ]; then
  warn "this ran inside a Claude Code session and .claude/skills/ did not exist when that session started; the running session cannot see /todoSetup (Claude Code only watches skill directories that existed at startup)"
  cat <<DONE
Next: exit Claude Code, start it again in $TARGET, then run  /todoSetup
      (the session this ran in will keep saying "Unknown command: /todoSetup" until restarted;
      every step can be skipped and re-run later; /todoSetup --yes takes all defaults)
DONE
elif [ "$HAD_SKILLS_DIR" = 0 ]; then
  cat <<DONE
Next: open Claude Code in $TARGET and run  /todoSetup
      If Claude Code is already open in this project, restart it first: a new .claude/skills/
      directory is only seen from the next session.
      (every step can be skipped and re-run later; /todoSetup --yes takes all defaults)
DONE
else
  cat <<DONE
Next: open Claude Code in $TARGET and run  /todoSetup
      (every step can be skipped and re-run later; /todoSetup --yes takes all defaults)
DONE
fi
