#!/usr/bin/env bash
# Tiny assertion helpers shared by tests/*.test.sh. No framework.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_BASE="$ROOT/tests/.tmp"
mkdir -p "$TMP_BASE"
FAILS=0
PASSES=0
pass() { PASSES=$((PASSES + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}
assert_contains() { # name haystack needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing [$3] in: $(printf '%s' "$2" | head -c 300)" ;; esac
}
assert_not_contains() { # name haystack needle
  case "$2" in *"$3"*) fail "$1" "unexpected [$3]" ;; *) pass "$1" ;; esac
}
assert_file() { if [ -f "$2" ]; then pass "$1"; else fail "$1" "no file $2"; fi; }
assert_no_file() { if [ ! -e "$2" ]; then pass "$1"; else fail "$1" "unexpected file $2"; fi; }
count_in_file() { grep -cF -- "$1" "$2" 2>/dev/null || true; }
new_tmp() { local d; d="$(mktemp -d "$TMP_BASE/$1.XXXXXX")"; printf '%s' "$d"; }
report() {
  printf '%s: %d passed, %d failed\n' "$1" "$PASSES" "$FAILS"
  [ "$FAILS" -eq 0 ]
}
