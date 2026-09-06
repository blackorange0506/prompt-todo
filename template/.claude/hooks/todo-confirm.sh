#!/usr/bin/env bash
# UserPromptSubmit hook: the executable form of the todo rules' confirm trigger.
#
# When the submitted prompt, trimmed, is exactly one of the confirm words (config.json
# `confirmWords`, default "works", "fixed", "works, fixed") — optionally followed by an item id,
# "works #39" — inject the tick + /todoIdealPrompt --replace instruction into the model's
# context, so the step no longer depends on Claude re-reading the rules. Without an id the item
# is the one most recently worked in the session; with one it is exactly that item, no guessing.
# Any other prompt: no output, exit 0. The rule text in .claude/prompt-todo/RULES.md stays the
# source of truth; keep the two in agreement.
#
# Wired in .claude/settings.json (hooks.UserPromptSubmit) by install.sh. Pipe-test:
#   echo '{"prompt":"works"}'     | .claude/hooks/todo-confirm.sh
#   echo '{"prompt":"works #39"}' | .claude/hooks/todo-confirm.sh
#
# Needs jq or python3 (either); bash 3.2 is enough.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../prompt-todo/bin/config.sh
. "$HERE/../prompt-todo/bin/config.sh"

input=$(cat)

json_field() {
  # $1 = field name; prints its string value or nothing
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r ".$1 // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); v=d.get(sys.argv[1]); print(v if isinstance(v,str) else "", end="")
except Exception:
    pass' "$1" 2>/dev/null
  fi
}

prompt="$(json_field prompt)"
[ -n "$prompt" ] || exit 0
cwd="$(json_field cwd)"

# Trim leading/trailing whitespace (including newlines).
shopt -s extglob
prompt="${prompt##+([[:space:]])}"
prompt="${prompt%%+([[:space:]])}"

# The project root: where the todo file and config.json live.
if [ -n "$cwd" ] && [ -d "$cwd" ]; then cd "$cwd" 2>/dev/null || true; fi
root="$(prompt_todo_root)"
cd "$root" 2>/dev/null || true

# The confirm words, as one regex alternation. Regex metacharacters in a word are escaped.
words_rx=""
while IFS= read -r w; do
  [ -n "$w" ] || continue
  w="$(printf '%s' "$w" | sed -e 's/[][\.*^$+?(){}|\\]/\\&/g')"
  if [ -n "$words_rx" ]; then words_rx="$words_rx|$w"; else words_rx="$w"; fi
done <<EOT
$(config_list '.confirmWords')
EOT
[ -n "$words_rx" ] || words_rx='works|fixed|works, fixed'

# The exact words, optionally followed by "#N" (a space before it is optional).
rx="^($words_rx)([[:space:]]*#([0-9]+))?\$"
if [[ "$prompt" =~ $rx ]]; then
  word="${BASH_REMATCH[1]}"
  id="${BASH_REMATCH[3]:-}"
else
  exit 0
fi

# The ignore rows, e.g. "`QA:` / `Admin:`".
ignore=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  if [ -n "$ignore" ]; then ignore="$ignore / \`$t:\`"; else ignore="\`$t:\`"; fi
done <<EOT
$(config_list '.tags.ignore')
EOT
if [ -n "$ignore" ]; then
  ignore_note="Top-level $ignore rows are never ticked or rewritten."
  ignore_or=", or is a top-level $ignore row,"
else
  ignore_note=""
  ignore_or=""
fi

name=$(git config user.name 2>/dev/null)
if [ -n "$name" ]; then
  todo="TODO.${name}.md"
  if [ -f "$todo" ]; then
    file_note="in \`${todo}\` (the current user's todo file)."
  else
    file_note="in \`${todo}\` — the file does not exist; say so and ask before creating it."
  fi
else
  file_note="in \`TODO.<name>.md\`, where <name> is \`git config user.name\` (unset here — resolve it or ask)."
fi

if [ -n "$id" ]; then
  which_item="It names item \`#${id}\`: confirm exactly that item — no guessing, no candidate question, and an id wins over a \`#wait\` hold. If \`#${id}\` is not in the file${ignore_or} say so and touch nothing. If it is already \`[x]\`, still run the rewrite."
  steps_item="item \`#${id}\`"
else
  which_item="It confirms the todo item most recently worked in this session. If more than one item is plausibly the one, ask which (max 3 candidates) BEFORE touching the file."
  steps_item="that item"
fi

context="TODO CONFIRM TRIGGER (hook): the prompt is \"${prompt}\" (\"${word}\"${id:+ + item id}). ${which_item} The file: ${file_note} Do ALL of this in THIS turn, without asking: (1) Autoincrement pass on the file — every \`#new…\` / id-less top-level \`- [ ]\` line gets the next id (highest #N in the file and its archive + 1), report token→id; (2) mark ${steps_item} \`[x]\` — Edit tool only, never the shell; (3) invoke the \`todoIdealPrompt\` skill with args \`#N --replace\` for it and finish its whole output in this reply (ideal prompt, feedback, the replaced item). Never renumber or reuse ids. ${ignore_note}"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$context" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
else
  python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":sys.argv[1]}}))' "$context"
fi
