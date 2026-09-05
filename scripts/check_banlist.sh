#!/usr/bin/env bash
# Fail when any banned word (scripts/banlist.txt) appears in the repository's tracked files
# (plus untracked, unignored ones — everything `git ls-files -co --exclude-standard` lists).
# Run before every commit and in CI.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LIST="$HERE/banlist.txt"
cd "$ROOT" || exit 1
files="$(git ls-files -co --exclude-standard | grep -v '^scripts/banlist.txt$' | grep -v '^scripts/check_banlist.sh$')"
[ -n "$files" ] || { echo "[banlist] no files"; exit 0; }
hits=0
while IFS= read -r pat; do
  case "$pat" in ''|'#'*) continue ;; esac
  flags="-nE"
  case "$pat" in i:*) flags="-inE"; pat="${pat#i:}" ;; esac
  # shellcheck disable=SC2086
  out="$(printf '%s\n' "$files" | xargs grep $flags -- "$pat" 2>/dev/null || true)"
  if [ -n "$out" ]; then
    hits=1
    printf '[banlist] "%s":\n%s\n' "$pat" "$out"
  fi
done < "$LIST"
if [ "$hits" = 1 ]; then echo "[banlist] FAILED"; exit 1; fi
echo "[banlist] clean ($(printf '%s\n' "$files" | wc -l | tr -d ' ') files)"
