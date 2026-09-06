#!/usr/bin/env bash
# prompt_todo_py (config.sh) finds Python 3 under whatever name it has, and bin/py.sh runs
# the package scripts through it. Shims stand in for the Windows cases on every OS.
# shellcheck disable=SC2030,SC2031  # PATH is changed inside subshells on purpose: one shim set per case
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PYSH="$ROOT/template/.claude/prompt-todo/bin/py.sh"
D="$(new_tmp python)"

prompt_todo_py_resolve || fail "a Python 3 exists here"
REAL="$(prompt_todo_py -c 'import sys; print(sys.executable)')"; REAL="${REAL//\\//}"
assert_contains "resolver picked one of the names" "python3 python py" "$PROMPT_TODO_PY"

shim() { # dir name behaviour(real|store-stub|py2|missing)
  local f="$1/$2"
  case "$3" in
    real)       printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL" > "$f" ;;
    py)         printf '#!/bin/sh\n[ "$1" = -3 ] || exit 1\nshift\nexec "%s" "$@"\n' "$REAL" > "$f" ;;
    store-stub) printf '#!/bin/sh\necho "Python was not found; install it from the Microsoft Store" >&2\nexit 9009\n' > "$f" ;;
    py2)        printf '#!/bin/sh\ncase "$*" in *version_info*) exit 1;; esac\nexit 0\n' > "$f" ;;
  esac
  chmod +x "$f"
}
resolve_with() { # shim-dir → the name the resolver settles on, with the shims first on PATH
  ( PATH="$1:$PATH"; unset PROMPT_TODO_PY; prompt_todo_py_resolve && printf '%s' "$PROMPT_TODO_PY" || printf 'none' )
}

S1="$D/s1"; mkdir -p "$S1"; shim "$S1" python3 store-stub; shim "$S1" python real
assert_eq "Store stub python3 skipped → python" "python" "$(resolve_with "$S1")"

S2="$D/s2"; mkdir -p "$S2"; shim "$S2" python3 store-stub; shim "$S2" python py2; shim "$S2" py py
assert_eq "python 2 skipped → py -3" "py" "$(resolve_with "$S2")"

S3="$D/s3"; mkdir -p "$S3"; shim "$S3" python3 real
assert_eq "python3 first when it works" "python3" "$(resolve_with "$S3")"

S4="$D/s4"; mkdir -p "$S4"; for n in python3 python py; do shim "$S4" "$n" store-stub; done
# every name broken: nothing found, a clear error, exit 127
out="$( PATH="$S4:$PATH"; unset PROMPT_TODO_PY
        # hide the real interpreters too
        for n in python3 python py; do eval "$n() { return 127; }"; done
        prompt_todo_py -c 'print(1)' 2>&1; echo "rc=$?" )"
assert_contains "none found → message" "$out" 'no Python 3 found'
assert_contains "none found → rc 127"  "$out" 'rc=127'

# a value set beforehand wins
assert_eq "PROMPT_TODO_PY preset is honoured" "python" "$( PATH="$S1:$PATH" PROMPT_TODO_PY=python bash -c '. "$0"; prompt_todo_py -c "import sys; print(\"python\")"' "$ROOT/template/.claude/prompt-todo/bin/config.sh" )"

# the wrapper
out="$(bash "$PYSH" render_rules.py --help 2>&1)"
assert_contains "py.sh runs a package script" "$out" 'usage: render_rules.py'
out="$(bash "$PYSH" 2>&1; echo "rc=$?")"
assert_contains "py.sh without a script → usage" "$out" 'usage: py.sh'
assert_contains "py.sh without a script → rc 2"  "$out" 'rc=2'
out="$(bash "$PYSH" nope.py 2>&1; echo "rc=$?")"
assert_contains "py.sh unknown script → error" "$out" 'no such script'
out="$( PATH="$S1:$PATH" bash "$PYSH" render_rules.py --help 2>&1 )"
assert_contains "py.sh works through the python shim" "$out" 'usage: render_rules.py'

# a Windows-style path with backslashes is normalised
assert_eq "slashes" "C:/Users/jd/proj" "$(prompt_todo_slashes 'C:\Users\jd\proj')"
assert_eq "slashes: unix path untouched" "/home/jd/proj" "$(prompt_todo_slashes '/home/jd/proj')"

report python
