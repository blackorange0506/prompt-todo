#!/usr/bin/env bash
# Fixtures → expected KEY=VALUE for the appNavigation spec parser.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$ROOT/template/.claude/skills/appNavigation"
P="$SK/scripts/parse_spec.sh"
FX="$ROOT/tests/fixtures/spec"
D="$(new_tmp spec)"

for n in full aliases; do
  out="$(APPNAV_CONFIG="$SK/app.example.json" bash "$P" "$FX/$n.txt" 2>"$D/$n.err")" || fail "$n rc" "$(cat "$D/$n.err")"
  if diff -u "$FX/$n.expected" <(printf '%s\n' "$out") > "$D/$n.diff"; then pass "fixture $n"; else fail "fixture $n" "$(cat "$D/$n.diff")"; fi
done
out="$(APPNAV_CONFIG="$D/none.json" bash "$P" "$FX/noconfig.txt" 2>/dev/null)"
if diff -u "$FX/noconfig.expected" <(printf '%s\n' "$out") > "$D/noconfig.diff"; then pass "fixture noconfig"; else fail "fixture noconfig" "$(cat "$D/noconfig.diff")"; fi

out="$(printf 'Server: prod\nRestaurant: Downtown\n' | APPNAV_CONFIG="$SK/app.example.json" bash "$P" - 2>"$D/prod.err")" && fail "prod accepted" || assert_eq "prod refused (rc 3)" "3" "$?"
assert_contains "prod message" "$(cat "$D/prod.err")" 'not allowed for automation'
printf 'Server: mars\n' | APPNAV_CONFIG="$SK/app.example.json" bash "$P" - >/dev/null 2>"$D/mars.err" && fail "unknown env accepted" || assert_eq "unknown env (rc 2)" "2" "$?"

out="$(printf '   \n\n' | APPNAV_CONFIG="$SK/app.example.json" bash "$P" - 2>/dev/null)"
assert_eq "empty spec → nothing" "" "$out"
out="$(printf 'App version: 1.2.3\n' | APPNAV_CONFIG="$SK/app.example.json" bash "$P" - 2>&1)"
assert_contains "non-integer version warns" "$out" 'not an integer'
report parse_spec
