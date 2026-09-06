# Prompt TODO

Think of your todo list as:
- a prompt manager and a prompt tracker;
- a learning loop for prompting: each finished item comes back as the prompt you should have written;
- the layer between the code base and the project-management system (Jira and friends).

Read [docs/todo-workflow.md](docs/todo-workflow.md) for the whole flow with examples.




## Install

```bash
git clone https://github.com/<you>/prompt-todo ~/src/prompt-todo
cd ~/your/project
bash ~/src/prompt-todo/install.sh          # add --without-app-navigation to skip that placeholder
```

Then open Claude Code in the project and run:

```
/todoSetup
```

`/todoHelp` prints the one-screen cheat sheet: what to type to work an item, how to finish
one, the skills.

If Claude Code is already open in the project (for example you ran the installer from its
terminal), restart it before `/todoSetup`: Claude Code only watches skill directories that existed
when the session started, so a session that predates `.claude/skills/` reports
`Unknown command: /todoSetup` until restarted. The installer says so when it detects that case.

The wizard walks through seven steps — project title and git name, tags, rules check, ticket
tracker, app navigation, permissions, summary. Every step can be skipped and run again later
on its own (`/todoSetup tracker`); `/todoSetup --yes` takes every default. The flow already
works right after `install.sh` with a generic tag table and no tracker; `/todoSetup tags` trims
the table to the platforms the repo actually contains.

Requirements: bash 3.2+, git, python3. `jq` is used when present. The tracker step needs the
Atlassian MCP server (Jira) or the `gh` CLI (GitHub Issues).

## What install.sh does

| Adds                                        | Purpose                                                       |
|---------------------------------------------|---------------------------------------------------------------|
| `.claude/prompt-todo/`                        | `config.json` (yours), `RULES.md` (generated), the render scripts, the readme |
| `.claude/hooks/todo-confirm.sh`             | catches `works` / `fixed` so the rewrite never depends on memory |
| `.claude/skills/todo*`                      | `/todoSetup`, `/todoFromTicket`, `/todoIdealPrompt`, `/todoIdealAll`, `/todoNumber`, `/todoReverse`, `/todoArchive`, `/todoMarkCode`, `/todoScore`, `/todoHelp` |
| `.claude/skills/appNavigation/`             | the navigation placeholder, a description to implement (optional) |
| one line in `CLAUDE.md`                     | `@.claude/prompt-todo/RULES.md` — the rules are always in context |
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
