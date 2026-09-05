#!/usr/bin/env bash
# Pipe-tests for template/.claude/hooks/todo-confirm.sh.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HOOK="$ROOT/template/.claude/hooks/todo-confirm.sh"

D="$(new_tmp hook)"
( cd "$D" && git init -q && git config user.name jd )
mkdir -p "$D/.claude/prompt-todo/bin" "$D/.claude/hooks"
cp "$ROOT/template/.claude/prompt-todo/bin/config.sh" "$D/.claude/prompt-todo/bin/"
cp "$HOOK" "$D/.claude/hooks/"
cp "$ROOT/template/.claude/prompt-todo/config.example.json" "$D/.claude/prompt-todo/config.json"
printf '# My App — TODO\n\n- [ ] #12 Something\n' > "$D/TODO.jd.md"

run_hook() { # prompt [cwd]
  python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1], "cwd": sys.argv[2]}))' "$1" "${2:-$D}" \
    | ( cd "${2:-$D}" && CLAUDE_PROJECT_DIR="$D" bash "$D/.claude/hooks/todo-confirm.sh" )
}

out="$(run_hook 'works')"
assert_contains "works → trigger"            "$out" 'TODO CONFIRM TRIGGER'
assert_contains "works → most recent item"   "$out" 'most recently worked'
assert_contains "works → names the file"     "$out" 'TODO.jd.md'
assert_contains "works → file exists note"   "$out" "the current user's todo file"
assert_contains "works → ignore rows"        "$out" '`QA:` / `Admin:`'
python3 -c 'import json,sys; json.loads(sys.stdin.read())' <<<"$out" && pass "output is JSON" || fail "output is JSON"

out="$(run_hook '  works #12
')"
assert_contains "whitespace + id → trigger"  "$out" 'It names item `#12`'
out="$(run_hook 'fixed#7')"
assert_contains "fixed#7 (no space) → id 7"  "$out" 'item `#7`'
out="$(run_hook 'works, fixed')"
assert_contains "works, fixed → trigger"     "$out" 'the prompt is \"works, fixed\"'

for p in 'Works' 'works on it' 'it works' 'works #' '#12' 'fixed the bug'; do
  out="$(run_hook "$p")"
  assert_eq "no trigger for [$p]" "" "$out"
done

# subdirectory cwd → resolved to the root, file found
mkdir -p "$D/src/deep"
out="$(run_hook 'works' "$D/src/deep")"
assert_contains "subdir cwd → root file"     "$out" "the current user's todo file"

# missing todo file
rm "$D/TODO.jd.md"
out="$(run_hook 'works')"
assert_contains "missing file note"          "$out" 'does not exist'
printf '# My App — TODO\n' > "$D/TODO.jd.md"

# custom confirm words + no ignore tags
python3 - "$D/.claude/prompt-todo/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["confirmWords"]=["done","ship it"]; c["tags"]["ignore"]=[]; json.dump(c,open(p,"w"))
PY
out="$(run_hook 'ship it #3')"
assert_contains "custom word → trigger"      "$out" 'item `#3`'
assert_not_contains "no ignore tags → no note" "$out" 'never ticked'
out="$(run_hook 'works')"
assert_eq "default word gone when configured" "" "$out"

# missing config → defaults
rm "$D/.claude/prompt-todo/config.json"
out="$(run_hook 'fixed')"
assert_contains "no config → default words"  "$out" 'TODO CONFIRM TRIGGER'

# python fallback: a PATH without jq
B="$D/bin"; mkdir -p "$B"
for t in bash sh python3 git sed cat dirname; do ln -sf "$(command -v $t)" "$B/$t"; done
out="$(printf '{"prompt":"works","cwd":"%s"}' "$D" | ( cd "$D" && PATH="$B" CLAUDE_PROJECT_DIR="$D" "$B/bash" "$D/.claude/hooks/todo-confirm.sh" ))"
assert_contains "no jq → python fallback"    "$out" 'TODO CONFIRM TRIGGER'

report hook
