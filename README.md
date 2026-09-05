# claude-todo-flow

A todo-driven workflow for [Claude Code](https://claude.com/claude-code): your todo file is
the prompt manager, the prompt tracker and the link between tickets and code.

- One markdown file per developer, `TODO.<git user.name>.md`, with numbered items.
- Type `#12` and Claude works item 12. Type `works` and Claude ticks it **and rewrites it into
  the prompt that would have produced the result in one try** — a prompt-writing training log
  that grows with the project.
- Every change carries a `[jd#12]` marker in a comment, so `grep` leads from code back to the
  prompt that caused it.
- `/todoFromTicket PROJ-321` turns a Jira ticket or GitHub issue into numbered first prompts,
  each with the check you will perform by hand.
- Optional: an `/appNavigation` skill that opens your app at the screen a ticket describes —
  shipped as a description only; you implement it for your app.

Read [docs/todo-workflow.md](docs/todo-workflow.md) ("Smart TODO") for the whole flow with examples.

## Install

```bash
git clone https://github.com/<you>/claude-todo-flow ~/src/claude-todo-flow
cd ~/your/project
bash ~/src/claude-todo-flow/install.sh          # add --without-app-navigation to skip that placeholder
```

Then open Claude Code in the project and run:

```
/todoSetup
```

The wizard walks through seven steps — project title and git name, tags, rules check, ticket
tracker, app navigation, permissions, summary. Every step can be skipped and run again later
on its own (`/todoSetup tracker`); `/todoSetup --yes` takes every default. The flow already
works right after `install.sh` with the default tag table and no tracker.

Requirements: bash 3.2+, git, python3. `jq` is used when present. The tracker step needs the
Atlassian MCP server (Jira) or the `gh` CLI (GitHub Issues).

## What install.sh does

| Adds                                        | Purpose                                                       |
|---------------------------------------------|---------------------------------------------------------------|
| `.claude/todo-flow/`                        | `config.json` (yours), `RULES.md` (generated), the render scripts, the readme |
| `.claude/hooks/todo-confirm.sh`             | catches `works` / `fixed` so the rewrite never depends on memory |
| `.claude/skills/todo*`                      | `/todoSetup`, `/todoFromTicket`, `/todoIdealPrompt`, `/todoIdealize`, `/todoNumber`, `/todoReverse`, `/todoArchive` |
| `.claude/skills/appNavigation/`             | the navigation placeholder, a description to implement (optional) |
| one line in `CLAUDE.md`                     | `@.claude/todo-flow/RULES.md` — the rules are always in context |
| one entry in `.claude/settings.json`        | the hook, merged next to whatever is already there            |
| one line in `.gitignore`                    | the attachments directory                                     |

Re-running `install.sh` upgrades the package files and leaves your config, todo files and
credentials alone. `uninstall.sh` removes exactly what was added and keeps `TODO.*.md`.

Commit `.claude/` with the project: the whole team then shares one configuration, one rule
set and one set of skills, and each person has their own todo file.

## Docs

- [docs/todo-workflow.md](docs/todo-workflow.md) — the flow, for people
- [docs/setup-wizard.md](docs/setup-wizard.md) — every wizard step: what it asks, what it writes
- [docs/jira-mcp.md](docs/jira-mcp.md) — connecting Jira (Atlassian MCP) or GitHub Issues
- [docs/app-navigation.md](docs/app-navigation.md) — what `/appNavigation` should do and how to connect yours

## Development

```bash
bash tests/run.sh              # hook, renderer, installer, docs
bash scripts/lint.sh           # shellcheck + py_compile
bash scripts/check_banlist.sh  # no traces of the project this was extracted from
```

CI runs everything on Linux and macOS (the macOS job also runs the tests under `/bin/bash` 3.2).

## License

MIT.
