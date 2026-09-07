# Changelog

## 0.1.2 — unreleased

- Windows support (native Claude Code with Git for Windows; WSL always worked). Python 3 is
  found under any of its names — `python3`, `python`, or the `py` launcher — by a resolver in
  `bin/config.sh` (`prompt_todo_py`) that the installer, the uninstaller and the hook use; the
  Microsoft Store's `python3` stub and a Python 2 `python` are skipped. New
  `bin/py.sh` wrapper (`bash .claude/prompt-todo/bin/py.sh render_rules.py`) is the one
  command the skills, the docs and the permission rules use to run the package scripts on every
  OS. The hook entry in `settings.json` is now `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/
  todo-confirm.sh …` (Git Bash does not run a bare `.sh` path); an entry with the previous
  default command is upgraded in place on re-install, a command the user rewrote is kept.
  Backslash paths from Windows are normalised in the hook and the wrapper. The repo carries a
  `.gitattributes` keeping every text file LF, and `install.sh` adds two lines to the project's
  `.gitattributes` so the hook and the scripts survive a `core.autocrlf=true` checkout
  (`uninstall.sh` removes them). CI now also runs on `windows-latest` under Git Bash, without
  `jq`, and installs into a fresh project on each OS. The Python scripts write LF on Windows too
  (`RULES.md`, `settings.json`, the `--stdout` render the snapshot tests compare; Windows Python
  would otherwise write CRLF), and `install.sh` no longer warns "is not its root" on every
  Windows install (Git for Windows prints `C:/…` where Git Bash's `pwd` says `/c/…`).
- `/todoFromTicket` no longer puts a `QA:` sub-checkbox under every dev item: a ticket block is
  now the `/appNavigation` item (when there is one), then 1–5 dev items, then 1–5 separate
  `QA:` items with their own ids — the manual checks for the ticket, as many as it needs, not
  one per dev item. They are ordinary `QA:` ignore rows: Claude never works or ticks them, the
  user does. The confirm word ticks only the dev item; the rules, the hook, `/todoIdealPrompt`,
  `/todoIdealAll` and `/todoArchive` drop the sub-checkbox handling. New `docs/todo-from-ticket.md`
  documents the skill end to end.
- Prompt scores: every rewrite of an item to its ideal prompt (confirm word, `/todoIdealPrompt
  --replace`, `/todoIdealAll`, `/todoReverse`) now appends ` (N/5)` to the item line — how close
  the original prompt was to the ideal one, 5 = already ideal, 1 = the result came from the
  corrections. `/todoIdealPrompt` prints the score first in its feedback. New `promptScores`
  config key and `/todoScore on|off` to switch it; on by default, existing scores are never
  touched.
- New `/todoHelp`: prints the cheat sheet, most important first — what to type to work an item
  (`#12`, `#new`, `#newCam`, `#new1`, a pasted line, `#wait` / `#go`), how to finish one
  (`works`, `fixed`, `works #12`) and what that does, then the skills one line each. Read-only;
  shows the configured confirm words and says which parts (tracker, app navigation, code
  markers) are off.
- New `/todoMarkCode on|off`: switches the `[<name>#N]` code markers off (or back on) for the
  project through a new `codeMarkers` config key. The **Code markers** rule is now a rendered
  block: off, it tells Claude to write no markers and leave existing ones alone, and
  `/todoReverse` then records the item without marking code. Markers are on by default.
- `/todoSetup tags` no longer shows a 21-row table and asks what to remove: it runs the new
  `bin/detect_platforms.py`, which reads the repo (Gradle with the Android plugin or a manifest,
  Xcode projects, `package.json` frameworks, Maven / Spring / Go / Django, CMake or Makefile C/C++
  sources, Electron, WPF, Qt …) and builds the table from what it finds — one row per detected
  platform, `+` rows only with two or more platforms, browser rows only with a web frontend,
  `Docs:` / `Infra:` always. The step asks nothing when something is detected; one short platform
  question otherwise. Manual changes moved to `/todoSetup tags add|remove|detect`.
- The `All:` tag and the default tag are gone: an item without a tag is simply about this
  project, so nothing implies that an Android-only app has web or browser work.
  `config.example.json` ships the generic set (Android, IOS, Web, MobileWeb, Backend, Desktop,
  Docs, Infra) with no default; the renderer's fallback default is empty too.
- `/todoIdealize` is renamed `/todoIdealAll` (the batch form of `/todoIdealPrompt`); the old name
  is gone everywhere, and `install.sh` removes the old skill directory on upgrade.

## 0.1.1 — unreleased

- `install.sh`: when `.claude/skills/` did not exist before the install, the closing message says
  that a Claude Code session already open in the project has to be restarted before `/todoSetup`
  works (Claude Code only watches skill directories that existed at session start). Run from
  Claude Code's own terminal (`CLAUDECODE` set), it warns explicitly and names the symptom
  (`Unknown command: /todoSetup`). `--dry-run` notes the same. README says it too.

## 0.1.0 — 2026-09-06

First public version, as Prompt TODO (`prompt-todo`).

- Todo core: per-user `TODO.<name>.md`, ids that are never reused, `#new` autoincrement,
  `#wait` / `#go`, the confirm-word hook (`works` / `fixed` → tick + `/todoIdealPrompt --replace`),
  `[<name>#N]` code markers, ticket blocks, a configurable tag table (platform tags
  Android / IOS / Web / MobileWeb / Backend / Desktop / All plus IOS+ / Android+ / Web+ / MobileWeb+, the browsers Chrome / Safari / Firefox / Edge with
  their + forms, Docs / Infra).
- Skills: `/todoSetup` (seven-step wizard, every step skippable and re-runnable),
  `/todoFromTicket` (Jira via the Atlassian MCP server, GitHub Issues via `gh`, paste mode),
  `/todoIdealPrompt`, `/todoIdealize`, `/todoNumber`, `/todoReverse`, `/todoArchive`.
- Rules rendered from `config.json` into `RULES.md`, imported by `CLAUDE.md`.
- `install.sh` / `uninstall.sh`: idempotent, merge into existing `settings.json`, `CLAUDE.md`
  and `.gitignore`.
- `appNavigation` placeholder: a description of what the skill should do, to be implemented
  per app and connected with `/todoSetup appNavigation`.
- Tests for the hook, the renderer, the installer and the docs; CI on Linux and macOS
  (bash 3.2 included); a ban-list check.
