#!/usr/bin/env bash
# install.sh into a temp git repo twice; idempotence; --dry-run; uninstall.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
D="$(new_tmp install)"
( cd "$D" && git init -q && git config user.name jd )
mkdir -p "$D/.claude"
cat > "$D/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo other-hook"}]}]}}
JSON
printf '# Project notes\n\nKeep the build green.\n' > "$D/CLAUDE.md"
printf 'build/\n' > "$D/.gitignore"

# dry run writes nothing
before="$(cd "$D" && find . -type f | sort)"
out="$(bash "$ROOT/install.sh" --target "$D" --dry-run 2>&1)"
after="$(cd "$D" && find . -type f | sort)"
assert_eq "dry-run writes nothing" "$before" "$after"
assert_contains "dry-run lists the hook" "$out" 'UserPromptSubmit hook'

out="$(bash "$ROOT/install.sh" --target "$D" 2>&1)" || fail "install rc" "$out"
assert_file "RULES.md rendered"      "$D/.claude/prompt-todo/RULES.md"
assert_file "config.json written"    "$D/.claude/prompt-todo/config.json"
assert_file "MANIFEST written"       "$D/.claude/prompt-todo/MANIFEST"
assert_file "hook copied"            "$D/.claude/hooks/todo-confirm.sh"
assert_file "skill copied"           "$D/.claude/skills/todoIdealPrompt/SKILL.md"
assert_eq "VERSION stamped" "$(cat "$ROOT/VERSION")" "$(cat "$D/.claude/prompt-todo/VERSION")"
assert_eq "import line once"   "1" "$(count_in_file '@.claude/prompt-todo/RULES.md' "$D/CLAUDE.md")"
assert_contains "CLAUDE.md content kept" "$(cat "$D/CLAUDE.md")" 'Keep the build green.'
assert_eq "hook merged once"   "1" "$(count_in_file 'todo-confirm.sh' "$D/.claude/settings.json")"
assert_eq "other hook kept"    "1" "$(count_in_file 'echo other-hook' "$D/.claude/settings.json")"
assert_eq "permissions kept"   "1" "$(count_in_file 'Bash(ls:*)' "$D/.claude/settings.json")"
assert_eq "gitignore attachments" "1" "$(count_in_file 'todoAttachments/' "$D/.gitignore")"
assert_eq "gitignore build kept"  "1" "$(count_in_file 'build/' "$D/.gitignore")"
[ -x "$D/.claude/hooks/todo-confirm.sh" ] && pass "hook executable" || fail "hook executable"

# the installed hook runs from the installed tree
out="$(printf '{"prompt":"works #4","cwd":"%s"}' "$D" | ( cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$D/.claude/hooks/todo-confirm.sh" ))"
assert_contains "installed hook fires" "$out" 'item `#4`'

# a user edit to config survives the re-install, package files are refreshed
python3 - "$D/.claude/prompt-todo/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["projectTitle"]="Edited"; json.dump(c,open(p,"w"))
PY
echo "# scribble" >> "$D/.claude/skills/todoNumber/SKILL.md"
out="$(bash "$ROOT/install.sh" --target "$D" 2>&1)" || fail "re-install rc" "$out"
assert_eq "config untouched on re-run" "1" "$(count_in_file 'Edited' "$D/.claude/prompt-todo/config.json")"
assert_eq "package file refreshed"     "0" "$(count_in_file '# scribble' "$D/.claude/skills/todoNumber/SKILL.md")"
assert_eq "import line still once"     "1" "$(count_in_file '@.claude/prompt-todo/RULES.md' "$D/CLAUDE.md")"
assert_eq "hook still once"            "1" "$(count_in_file 'todo-confirm.sh' "$D/.claude/settings.json")"
assert_eq "gitignore line still once"  "1" "$(count_in_file 'todoAttachments/' "$D/.gitignore")"
assert_contains "re-rendered with the edited title" "$(cat "$D/.claude/prompt-todo/RULES.md")" '# Edited — TODO'

# --force resets config with a backup
out="$(bash "$ROOT/install.sh" --target "$D" --force 2>&1)"
assert_file "config backup" "$D/.claude/prompt-todo/config.json.bak"
assert_eq "config reset" "0" "$(count_in_file 'Edited' "$D/.claude/prompt-todo/config.json")"

# --without-app-navigation
E="$(new_tmp install-noapp)"; ( cd "$E" && git init -q )
bash "$ROOT/install.sh" --target "$E" --without-app-navigation >/dev/null 2>&1 || fail "install without app nav"
assert_no_file "no appNavigation skill" "$E/.claude/skills/appNavigation"
assert_file "placeholder skill installed by default" "$D/.claude/skills/appNavigation/SKILL.md"
assert_file "CLAUDE.md created" "$E/CLAUDE.md"

# uninstall restores
printf '# My App — TODO\n- [ ] #1 keep me\n' > "$D/TODO.jd.md"
out="$(bash "$ROOT/uninstall.sh" --target "$D" 2>&1)" || fail "uninstall rc" "$out"
assert_no_file "prompt-todo dir gone"   "$D/.claude/prompt-todo"
assert_no_file "hook gone"            "$D/.claude/hooks/todo-confirm.sh"
assert_no_file "skills gone"          "$D/.claude/skills/todoIdealPrompt"
assert_file    "todo file kept"       "$D/TODO.jd.md"
assert_eq "import line removed" "0" "$(count_in_file '@.claude/prompt-todo/RULES.md' "$D/CLAUDE.md")"
assert_contains "CLAUDE.md content kept after uninstall" "$(cat "$D/CLAUDE.md")" 'Keep the build green.'
assert_eq "hook entry removed" "0" "$(count_in_file 'todo-confirm.sh' "$D/.claude/settings.json")"
assert_eq "other hook survives" "1" "$(count_in_file 'echo other-hook' "$D/.claude/settings.json")"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$D/.claude/settings.json" && pass "settings still JSON" || fail "settings still JSON"
report install
