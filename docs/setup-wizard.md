# The setup wizard: `/todoSetup`

`install.sh` leaves a working flow behind: the default tag table, no tracker, no app
navigation. `/todoSetup` is how you change that, inside Claude Code, one step at a time. Every
step shows the current value, offers **Skip**, and can be run again later on its own.

```
/todoSetup                 all steps in order
/todoSetup tags            one step
/todoSetup --yes           every default, no questions
/todoSetup tracker --yes   one step, its default
```

Everything the wizard writes goes to `.claude/todo-flow/config.json`; after each change it
re-renders `.claude/todo-flow/RULES.md`, the file Claude actually follows. You can also edit
the config by hand and run `python3 .claude/todo-flow/bin/render_rules.py` yourself.

| # | step            | asks                                                                 | writes                                   | skipped means                                                |
|---|-----------------|----------------------------------------------------------------------|------------------------------------------|--------------------------------------------------------------|
| 1 | `todo`          | project title; confirms `git config user.name` (offers to set it); create `TODO.<name>.md` now? | `projectTitle`; the todo file           | title stays `My App` or what it was; the first `#new` prompt asks about the file again |
| 2 | `tags`          | shows the default table; remove rows, add rows, change the default, change the ignore rows | `tags`                        | the default table below                                      |
| 3 | `rules`         | nothing — renders, then checks the `CLAUDE.md` import, the hook entry, jq/python3, and pipe-tests the hook | `RULES.md`; offers to repair the import and the hook | —                                        |
| 4 | `tracker`       | Jira (Atlassian MCP) / GitHub Issues (gh) / none; host + project keys or `owner/repo`; runs the connection check and a test fetch | `tracker`                | `/todoFromTicket` works only with pasted ticket text; the ticket-key input of app navigation is unavailable |
| 5 | `appNavigation` | Skip (default) or connect an existing skill (the shipped carcass included)          | `appNavigation.mode` + `skill`           | ticket context blocks stay as plain sub-bullets of the first dev item; fill the carcass later and re-run this step |
| 6 | `permissions`   | add allow rules to `.claude/settings.local.json` for what the skills run          | `settings.local.json`                    | Claude Code asks on each of those commands                   |
| 7 | `summary`       | prints the effective config and what is off; offers a smoke test (`#new` item numbered, then removed) | nothing lasting                | —                                                            |

## Step 1 — why a title and a git name

Every person on the project gets their own todo file, named after their git user name, so
files never collide in git and Claude never touches a teammate's items. The same name becomes
the marker Claude leaves in code comments, `[jd#12]`, which is how a change is traced back to
the prompt that caused it. The project title only appears in the file headers.

For `git config user.name` = `jd` and the title `My App`:

```
TODO.jd.md               your items              header:  # My App — TODO
TODO.jd.archive.md       done items, moved by    header:  # My App — TODO archive
                         /todoArchive; ids live on there, so numbers are never reused
```

## Step 2 — the default tag table

| Tag           | Meaning                                                                                                |
|---------------|--------------------------------------------------------------------------------------------------------|
| `Android:`    | Android app only                                                                                       |
| `IOS:`        | iOS app only                                                                                           |
| `Web:`        | web frontend in a desktop browser                                                                      |
| `MobileWeb:`  | web frontend in a phone browser                                                                        |
| `Backend:`    | backend / API only                                                                                     |
| `Desktop:`    | desktop app (macOS / Windows / Linux)                                                                  |
| `All:`        | every platform — the default when no tag is present                                                    |
| `IOS+:`       | seen on iOS, almost certainly elsewhere too: fix all, verify iOS first                                 |
| `Android+:`   | seen on Android, almost certainly elsewhere too: fix all, verify Android first                         |
| `Web+:`       | seen in the desktop browser, almost certainly in the phone browser too: fix both, verify desktop first |
| `MobileWeb+:` | seen in the phone browser, almost certainly in the desktop browser too: fix both, verify mobile first  |
| `Chrome:`     | the web frontend in Chrome only                                                                        |
| `Safari:`     | the web frontend in Safari only                                                                        |
| `Firefox:`    | the web frontend in Firefox only                                                                       |
| `Edge:`       | the web frontend in Edge only                                                                          |
| `Chrome+:`    | seen in Chrome, almost certainly in the other browsers too: fix all, verify Chrome first               |
| `Safari+:`    | seen in Safari, almost certainly in the other browsers too: fix all, verify Safari first               |
| `Firefox+:`   | seen in Firefox, almost certainly in the other browsers too: fix all, verify Firefox first             |
| `Edge+:`      | seen in Edge, almost certainly in the other browsers too: fix all, verify Edge first                   |
| `Docs:`       | documentation only                                                                                     |
| `Infra:`      | build, CI, tooling                                                                                     |
| `QA:`         | the user's personal row — Claude ignores it entirely                                                   |
| `Admin:`      | the user's personal row — Claude ignores it entirely                                                   |

A mobile-only team keeps `Android:`, `IOS:` and their `+` pair; a web team keeps `Web:`,
`MobileWeb:`, their `+` pair and `Backend:`, and the browser tags only when it ships
browser-specific fixes; `Docs:` and `Infra:` suit everyone. The default tag can be set to none:
an item without a tag then simply has no tag.

## Step 4 — why a tracker connection

See [jira-mcp.md](jira-mcp.md): what the connection is for, the worked example, the
Atlassian MCP setup, the GitHub alternative and paste mode.

## Step 5 — app navigation

The wizard never builds the navigation skill for you. It offers to connect one you already
have, or to skip and come back: filling the shipped carcass is described in
[app-navigation.md](app-navigation.md). Connecting the carcass before it is filled is allowed
(the wizard warns), so the rules and `/todoFromTicket` already produce the `/appNavigation`
items while you work on it.

## Team use

Commit `.claude/todo-flow/config.json`, `RULES.md`, the skills and the hook. A teammate who
clones the project gets the same flow; they run `/todoSetup todo` once for their own todo
file, and `/todoSetup permissions` if they want the allow rules (that file is personal).
