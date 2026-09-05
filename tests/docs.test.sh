#!/usr/bin/env bash
# The docs keep their last sections (a bad edit once truncated three of them past a table).
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check() { if grep -qF -- "$2" "$ROOT/$1"; then pass "$1 has '$2'"; else fail "$1 lacks '$2'"; fi; }
check template/.claude/todo-flow/README.md "## 7. Where things live"
check docs/todo-workflow.md "## 7. Where things live"
check docs/setup-wizard.md "## Team use"
check docs/jira-mcp.md "## Attachments"
check docs/app-navigation.md "## Testing the carcass"
check template/.claude/skills/appNavigation/README.md "## Extending"
check README.md "## License"
report docs
