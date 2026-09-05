# Changelog

## 0.1.0 — 2026-09-06

First public version.

- Todo core: per-user `TODO.<name>.md`, ids that are never reused, `#new` autoincrement,
  `#wait` / `#go`, the confirm-word hook (`works` / `fixed` → tick + `/todoIdealPrompt --replace`),
  `[<name>#N]` code markers, ticket blocks, a configurable tag table (platform tags
  Android / IOS / Web / MobileWeb / Backend / Desktop / All plus IOS+ / Android+ / Web+ / MobileWeb+ / Docs / Infra).
- Skills: `/todoSetup` (seven-step wizard, every step skippable and re-runnable),
  `/todoFromTicket` (Jira via the Atlassian MCP server, GitHub Issues via `gh`, paste mode),
  `/todoIdealPrompt`, `/todoIdealize`, `/todoNumber`, `/todoReverse`, `/todoArchive`.
- Rules rendered from `config.json` into `RULES.md`, imported by `CLAUDE.md`.
- `install.sh` / `uninstall.sh`: idempotent, merge into existing `settings.json`, `CLAUDE.md`
  and `.gitignore`.
- `appNavigation` carcass: spec parser, dispatcher, Android (adb + Maestro), iOS (simctl +
  Maestro) and web (Playwright) drivers, `app.json` config model, BestPizza sample.
- Tests for the hook, the renderer, the installer, the parser, the dispatcher and the
  Playwright driver; CI on Linux and macOS (bash 3.2 included); a ban-list check.
