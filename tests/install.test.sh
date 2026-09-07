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
assert_contains "dry-run notes the new skills dir" "$out" '.claude/skills/ is new'

# first install, run as from Claude Code's own terminal (CLAUDECODE set): .claude/skills is new,
# so the running session cannot see the skills and the closing text says to restart
out="$(CLAUDECODE=1 bash "$ROOT/install.sh" --target "$D" 2>&1)" || fail "install rc" "$out"
assert_contains "in-session install says restart"  "$out" 'start it again in'
assert_contains "in-session install names the symptom" "$out" 'Unknown command: /todoSetup'
assert_not_contains "no false root warning" "$out" 'is not its root'   # Windows: C:/… vs /c/… must compare equal
assert_file "RULES.md rendered"      "$D/.claude/prompt-todo/RULES.md"
assert_file "config.json written"    "$D/.claude/prompt-todo/config.json"
assert_file "MANIFEST written"       "$D/.claude/prompt-todo/MANIFEST"
assert_file "hook copied"            "$D/.claude/hooks/todo-confirm.sh"
assert_file "skill copied"           "$D/.claude/skills/todoIdealPrompt/SKILL.md"
assert_file "renamed skill copied"   "$D/.claude/skills/todoIdealAll/SKILL.md"
assert_file "detect script copied"   "$D/.claude/prompt-todo/bin/detect_platforms.py"
is_windows || { [ -x "$D/.claude/prompt-todo/bin/detect_platforms.py" ] && pass "detect script executable" || fail "detect script executable"; }
assert_file "py wrapper copied"      "$D/.claude/prompt-todo/bin/py.sh"
assert_eq "VERSION stamped" "$(cat "$ROOT/VERSION")" "$(cat "$D/.claude/prompt-todo/VERSION")"
assert_eq "import line once"   "1" "$(count_in_file '@.claude/prompt-todo/RULES.md' "$D/CLAUDE.md")"
assert_contains "CLAUDE.md content kept" "$(cat "$D/CLAUDE.md")" 'Keep the build green.'
assert_eq "hook merged once"   "1" "$(count_in_file 'todo-confirm.sh' "$D/.claude/settings.json")"
assert_eq "other hook kept"    "1" "$(count_in_file 'echo other-hook' "$D/.claude/settings.json")"
assert_eq "permissions kept"   "1" "$(count_in_file 'Bash(ls:*)' "$D/.claude/settings.json")"
assert_eq "gitignore attachments" "1" "$(count_in_file 'todoAttachments/' "$D/.gitignore")"
assert_eq "gitignore build kept"  "1" "$(count_in_file 'build/' "$D/.gitignore")"
is_windows || { [ -x "$D/.claude/hooks/todo-confirm.sh" ] && pass "hook executable" || fail "hook executable"; }
assert_eq "hook command runs through bash" "1" "$(count_in_file 'bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/todo-confirm.sh' "$D/.claude/settings.json")"
assert_eq "gitattributes: hook LF"    "1" "$(count_in_file '.claude/hooks/*.sh text eol=lf' "$D/.gitattributes")"
assert_eq "gitattributes: bin LF"     "1" "$(count_in_file '.claude/prompt-todo/bin/* text eol=lf' "$D/.gitattributes")"
# The Python scripts must write LF on Windows too (default text mode there writes CRLF).
CR="$(printf '\r')"
assert_eq "RULES.md is LF"       "0" "$(grep -c "$CR" "$D/.claude/prompt-todo/RULES.md" || true)"
assert_eq "settings.json is LF"  "0" "$(grep -c "$CR" "$D/.claude/settings.json" || true)"

# the installed hook runs from the installed tree
out="$(printf '{"prompt":"works #4","cwd":"%s"}' "$D" | ( cd "$D" && CLAUDE_PROJECT_DIR="$D" bash "$D/.claude/hooks/todo-confirm.sh" ))"
assert_contains "installed hook fires" "$out" 'item `#4`'

# a user edit to config survives the re-install, package files are refreshed
prompt_todo_py - "$D/.claude/prompt-todo/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["projectTitle"]="Edited"; json.dump(c,open(p,"w"))
PY
echo "# scribble" >> "$D/.claude/skills/todoNumber/SKILL.md"
mkdir -p "$D/.claude/skills/todoIdealize" && echo "old" > "$D/.claude/skills/todoIdealize/SKILL.md"
out="$(env -u CLAUDECODE bash "$ROOT/install.sh" --target "$D" 2>&1)" || fail "re-install rc" "$out"
assert_not_contains "re-install has no restart note" "$out" 'restart'
assert_contains     "re-install keeps the next step"  "$out" 'run  /todoSetup'
assert_eq "config untouched on re-run" "1" "$(count_in_file 'Edited' "$D/.claude/prompt-todo/config.json")"
assert_eq "package file refreshed"     "0" "$(count_in_file '# scribble' "$D/.claude/skills/todoNumber/SKILL.md")"
assert_no_file "old todoIdealize dir removed on upgrade" "$D/.claude/skills/todoIdealize"
assert_contains "upgrade names the removed skill" "$out" 'renamed to todoIdealAll'
assert_eq "import line still once"     "1" "$(count_in_file '@.claude/prompt-todo/RULES.md' "$D/CLAUDE.md")"
assert_eq "hook still once"            "1" "$(count_in_file 'todo-confirm.sh' "$D/.claude/settings.json")"
assert_eq "gitignore line still once"  "1" "$(count_in_file 'todoAttachments/' "$D/.gitignore")"
assert_eq "gitattributes line still once" "1" "$(count_in_file '.claude/hooks/*.sh text eol=lf' "$D/.gitattributes")"
assert_contains "re-rendered with the edited title" "$(cat "$D/.claude/prompt-todo/RULES.md")" '# Edited — TODO'

# --force resets config with a backup
out="$(bash "$ROOT/install.sh" --target "$D" --force 2>&1)"
assert_file "config backup" "$D/.claude/prompt-todo/config.json.bak"
assert_eq "config reset" "0" "$(count_in_file 'Edited' "$D/.claude/prompt-todo/config.json")"

# --without-app-navigation
E="$(new_tmp install-noapp)"; ( cd "$E" && git init -q )
out="$(env -u CLAUDECODE bash "$ROOT/install.sh" --target "$E" --without-app-navigation 2>&1)" || fail "install without app nav" "$out"
assert_contains     "fresh install outside Claude Code hints at a restart" "$out" 'restart it first'
assert_not_contains "fresh install outside Claude Code has no in-session warning" "$out" 'start it again in'
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
assert_eq "gitattributes lines removed" "" "$(grep -F 'text eol=lf' "$D/.gitattributes" 2>/dev/null || true)"
assert_eq "other hook survives" "1" "$(count_in_file 'echo other-hook' "$D/.claude/settings.json")"
prompt_todo_py -c 'import json,sys; json.load(open(sys.argv[1]))' "$D/.claude/settings.json" && pass "settings still JSON" || fail "settings still JSON"

# an install from before 0.1.2 wired the hook without the bash prefix: upgraded in place, once
U="$(new_tmp install-upgrade)"; ( cd "$U" && git init -q )
mkdir -p "$U/.claude"
cat > "$U/.claude/settings.json" <<'JSON'
{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/todo-confirm.sh 2>/dev/null || true","timeout":10}]}]}}
JSON
out="$(env -u CLAUDECODE bash "$ROOT/install.sh" --target "$U" 2>&1)" || fail "upgrade install rc" "$out"
assert_eq "old hook command upgraded"  "1" "$(count_in_file 'bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/todo-confirm.sh' "$U/.claude/settings.json")"
assert_eq "old hook command not duplicated" "1" "$(count_in_file 'todo-confirm.sh' "$U/.claude/settings.json")"
# a command the user rewrote is left alone
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"my-wrapper todo-confirm.sh"}]}]}}\n' > "$U/.claude/settings.json"
out="$(env -u CLAUDECODE bash "$ROOT/install.sh" --target "$U" 2>&1)" || fail "custom-hook install rc" "$out"
assert_eq "custom hook command kept" "1" "$(count_in_file 'my-wrapper todo-confirm.sh' "$U/.claude/settings.json")"
assert_eq "custom hook not duplicated" "1" "$(count_in_file 'todo-confirm.sh' "$U/.claude/settings.json")"
report install
