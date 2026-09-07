#!/usr/bin/env bash
# config → RULES.md snapshots. UPDATE_SNAPSHOTS=1 rewrites tests/fixtures/render/*.md.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
RENDER="$ROOT/template/.claude/prompt-todo/bin/render_rules.py"
TPL="$ROOT/template/.claude/prompt-todo/RULES.template.md"
FX="$ROOT/tests/fixtures/render"
D="$(new_tmp render)"

mk() { # name python-expression-over-c
  prompt_todo_py - "$ROOT/template/.claude/prompt-todo/config.example.json" "$D/$1.json" "$2" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(c,open(sys.argv[2],"w"),indent=1)
PY
}
mk default   'pass'
mk trimmed   'c["tags"]["list"]=[{"tag":"Bug","meaning":"defect"},{"tag":"Feature","meaning":"new"}]; c["tags"]["default"]=""; c["tags"]["ignore"]=[]; c["projectTitle"]="BestPizza"'
mk jira      'c["tracker"]["kind"]="jira"; c["tracker"]["jira"]={"host":"bestpizza.atlassian.net","projectKeys":["BP","OPS"]}'
mk github    'c["tracker"]["kind"]="github"; c["tracker"]["github"]={"repo":"bestpizza/app"}; c["attachmentsDir"]="tickets"'
mk appnav    'c["appNavigation"]={"mode":"existing","skill":"navigateApp"}; c["confirmWords"]=["done"]'
mk withdefault 'c["tags"]["default"]="Android"'
mk markersoff 'c["codeMarkers"]="off"'
mk scoresoff 'c["promptScores"]="off"'

for n in default trimmed jira github appnav markersoff scoresoff; do
  out="$(prompt_todo_py "$RENDER" --config "$D/$n.json" --template "$TPL" --stdout)" || { fail "render $n"; continue; }
  if [ "${UPDATE_SNAPSHOTS:-0}" = 1 ]; then printf '%s\n' "$out" > "$FX/$n.md"; pass "snapshot $n updated"; continue; fi
  if [ ! -f "$FX/$n.md" ]; then fail "snapshot $n missing (run with UPDATE_SNAPSHOTS=1)"; continue; fi
  if diff -u "$FX/$n.md" <(printf '%s\n' "$out") > "$D/$n.diff"; then pass "snapshot $n"; else fail "snapshot $n" "$(head -40 "$D/$n.diff")"; fi
done

out="$(prompt_todo_py "$RENDER" --config "$D/default.json" --template "$TPL" --stdout)"
# Windows Python turns \n into \r\n unless told not to; the snapshots above would then fail with ^M.
assert_not_contains "stdout is LF (no CR)" "$out" "$(printf '\r')"
prompt_todo_py "$RENDER" --config "$D/default.json" --template "$TPL" --out "$D/rules.md" >/dev/null
assert_eq "written file is LF (no CR)" "0" "$(grep -c "$(printf '\r')" "$D/rules.md" || true)"
assert_not_contains "no leftover placeholders" "$out" '{{'
assert_contains "no default tag by default" "$out" 'There is no default tag'
assert_not_contains "no All tag"        "$out" '`All:`'
assert_not_contains "no browser tags by default" "$out" '`Chrome:`'
out="$(prompt_todo_py "$RENDER" --config "$D/withdefault.json" --template "$TPL" --stdout)"
assert_contains "default marked"       "$out" 'Android app only — also the **default**'
out="$(prompt_todo_py "$RENDER" --config "$D/default.json" --template "$TPL" --stdout)"
assert_contains "tracker none line"    "$out" 'No ticket tracker is connected'
assert_contains "appNav none line"     "$out" 'No app-navigation skill is connected'
assert_contains "markers on by default" "$out" '**Code markers — prompt history.**'
assert_contains "reverse adds markers"  "$out" 'while code markers are on'
out="$(prompt_todo_py "$RENDER" --config "$D/markersoff.json" --template "$TPL" --stdout)"
assert_contains "markers off line"     "$out" '**Code markers — off.**'
assert_not_contains "no marker example when off" "$out" '[jd#19]'
out="$(prompt_todo_py "$RENDER" --config "$D/default.json" --template "$TPL" --stdout)"
assert_contains "scores on by default"  "$out" '**Prompt scores.**'
assert_contains "score token"           "$out" '(3/5)'
out="$(prompt_todo_py "$RENDER" --config "$D/scoresoff.json" --template "$TPL" --stdout)"
assert_contains "scores off line"       "$out" '**Prompt scores — off.**'
out="$(prompt_todo_py "$RENDER" --config "$D/appnav.json" --template "$TPL" --stdout)"
assert_contains "appNav skill name"    "$out" '`/navigateApp` skill'
assert_contains "custom confirm word"  "$out" '`"done"`, optionally'
out="$(prompt_todo_py "$RENDER" --config "$D/trimmed.json" --template "$TPL" --stdout)"
assert_contains "no default tag line"  "$out" 'There is no default tag'
assert_contains "title in header"      "$out" '# BestPizza — TODO'

# invalid configs are refused
mk bad1 'c["tags"]["default"]="Nope"'
mk bad2 'c["tags"]["list"].append({"tag":"QA","meaning":"x"})'
mk bad3 'c["tracker"]["kind"]="trello"'
mk bad4 'c["codeMarkers"]=False'
mk bad5 'c["promptScores"]=True'
for n in bad1 bad2 bad3 bad4 bad5; do
  if prompt_todo_py "$RENDER" --config "$D/$n.json" --check >/dev/null 2>&1; then fail "$n accepted"; else pass "$n refused"; fi
done
report render
