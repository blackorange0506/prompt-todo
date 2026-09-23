#!/usr/bin/env bash
# bin/download_attachments.py against two stub HTTP servers: the Jira-style redirect to a
# second host loses the Authorization header, files land under their original names with a
# collision suffix, and the exit codes say what happened (tests/download_stub.py has the list).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SCRIPT="$ROOT/template/.claude/prompt-todo/bin/download_attachments.py"
PYSH="$ROOT/template/.claude/prompt-todo/bin/py.sh"

out="$(prompt_todo_py "$ROOT/tests/download_stub.py" "$SCRIPT" 2>&1; echo "rc=$?")"
assert_contains "stub-server run passes" "$out" 'ALL OK'
assert_contains "stub-server run rc 0"   "$out" 'rc=0'

# the wrapper runs it, and an empty list is a no-op without credentials
out="$(printf '[]' | bash "$PYSH" download_attachments.py --dir "$(new_tmp download)/x" 2>&1; echo "rc=$?")"
assert_eq "py.sh: empty list → rc 0, no output" "rc=0" "$out"
out="$(bash "$PYSH" download_attachments.py --help 2>&1)"
assert_contains "py.sh: --help" "$out" 'usage: download_attachments.py'

report download
