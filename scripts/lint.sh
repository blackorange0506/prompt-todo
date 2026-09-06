#!/usr/bin/env bash
# Runs shellcheck over every shell script, py_compile over every python script and
# node --check over every .mjs (when node is present).
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/.."
sh_files="$(git ls-files -co --exclude-standard '*.sh' | tr '\n' ' ')"
# shellcheck disable=SC2086
shellcheck -x -e SC1091,SC2016,SC2015 $sh_files
py_files="$(git ls-files -co --exclude-standard '*.py' | tr '\n' ' ')"
# shellcheck disable=SC2086
[ -z "$py_files" ] || python3 -m py_compile $py_files
mjs_files="$(git ls-files -co --exclude-standard '*.mjs' | tr '\n' ' ')"
if [ -n "$mjs_files" ] && command -v node >/dev/null 2>&1; then
  for f in $mjs_files; do node --check "$f"; done
fi
echo "[lint] ok"
