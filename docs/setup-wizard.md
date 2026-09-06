# The setup wizard: `/todoSetup`

`install.sh` leaves a working flow behind: a generic tag table, no tracker, no app
navigation. `/todoSetup` is how you change that, inside Claude Code, one step at a time. Every
step shows the current value, offers **Skip**, and can be run again later on its own.

```
/todoSetup                 all steps in order
/todoSetup tags            one step
/todoSetup --yes           every default, no questions
/todoSetup tracker --yes   one step, its default
```

Everything the wizard writes goes to `.claude/prompt-todo/config.json`; after each change it
re-renders `.claude/prompt-todo/RULES.md`, the file Claude actually follows. You can also edit
the config by hand and run `bash .claude/prompt-todo/bin/py.sh render_rules.py` yourself.

| # | step            | asks                                                                 | writes                                   | skipped means                                                |
|---|-----------------|----------------------------------------------------------------------|------------------------------------------|--------------------------------------------------------------|
| 1 | `todo`          | project title; confirms `git config user.name` (offers to set it); create `TODO.<name>.md` now? | `projectTitle`; the todo file           | title stays `My App` or what it was; the first `#new` prompt asks about the file again |
| 2 | `tags`          | nothing when the repo says what it is: detects the platforms (Gradle, Xcode, `package.json`, Maven, CMake …) and writes the matching table; one platform question only when nothing is detected | `tags`  | `Docs:` / `Infra:` only (with `--yes`) |
| 3 | `rules`         | nothing — renders, then checks the `CLAUDE.md` import, the hook entry, jq/Python, and pipe-tests the hook | `RULES.md`; offers to repair the import and the hook | —                                        |
| 4 | `tracker`       | Jira (Atlassian MCP) / GitHub Issues (gh) / none; host + project keys or `owner/repo`; runs the connection check and a test fetch | `tracker`                | `/todoFromTicket` works only with pasted ticket text; the ticket-key input of app navigation is unavailable |
| 5 | `appNavigation` | Skip (default) or connect an existing skill (the shipped placeholder included)      | `appNavigation.mode` + `skill`           | ticket context blocks stay as plain sub-bullets of the first dev item; implement the skill later and re-run this step |
| 6 | `permissions`   | add allow rules to `.claude/settings.local.json` for what the skills run          | `settings.local.json`                    | Claude Code asks on each of those commands                   |
| 7 | `summary`       | prints the effective config and what is off; offers a smoke test (`#new` item numbered, then removed) | nothing lasting                | —                                                            |

## Step 1 — why a title and a git name

Every person on the project gets their own todo file, named after their git user name, so
files never collide in git and Claude never touches a teammate's items. The same name becomes
the marker Claude leaves in code comments, `[jd#12]`, which is how a change is traced back to
the prompt that caused it; `/todoMarkCode off` switches those markers off for the project. The
project title only appears in the file headers.

For `git config user.name` = `jd` and the title `My App`:

```
TODO.jd.md               your items              header:  # My App — TODO
TODO.jd.archive.md       done items, moved by    header:  # My App — TODO archive
                         /todoArchive; ids live on there, so numbers are never reused
```

## Step 2 — the tag table comes from the repo

Tags exist to tell platforms apart inside one repo, so the wizard looks at the repo instead of
asking. `bin/detect_platforms.py` recognises:

| Platform  | Markers                                                                                          |
|-----------|--------------------------------------------------------------------------------------------------|
| Android   | `AndroidManifest.xml`; a Gradle file with the Android plugin                                     |
| IOS       | `*.xcodeproj`, `*.xcworkspace`, `Podfile`, `Package.swift` for iOS, `Info.plist` next to Swift   |
| Web       | `package.json` with React, Vue, Angular, Svelte, Next, Nuxt, Vite, Astro or Solid; a root `index.html` |
| Backend   | `pom.xml`; Gradle with Spring, Ktor, a JVM plugin; `go.mod`; Django / FastAPI / Flask; Express, Fastify, Nest; Rails; Composer; an ASP.NET project |
| Desktop   | Electron, Tauri, Compose Desktop, `*.sln`, WPF / WinForms / Avalonia / MAUI, Qt `*.pro`; CMake / Makefile / Meson with C or C++ sources when nothing else matched |

The table is built from the result: one row per detected platform, `MobileWeb:` and the
browser rows (`Chrome:` `Safari:` `Firefox:` `Edge:`) only with a web frontend, the `+` rows
(`Android+:` — seen on Android, almost certainly elsewhere too: fix all, verify Android first)
only when two or more platforms are found, `Docs:` and `Infra:` always, `QA:` and `Admin:` as
the ignore rows. There is no `All:` tag and no default tag: an item without a tag is simply
about this project, so an Android-only app never carries a hint that web or browser work is
expected. An Android-only repo ends up with:

| Tag        | Meaning                                              |
|------------|------------------------------------------------------|
| `Android:` | Android app only                                     |
| `Docs:`    | documentation only                                   |
| `Infra:`   | build, CI, tooling                                   |
| `QA:`      | the user's personal row — Claude ignores it entirely |
| `Admin:`   | the user's personal row — Claude ignores it entirely |

When nothing is detected (a plain library, an empty repo), the step asks one question — which
platform is this — and builds the table from the answer; `--yes` writes `Docs:` and `Infra:`
only. For the rare manual change: `/todoSetup tags add <Tag>: <meaning>`,
`/todoSetup tags remove <Tag>`, `/todoSetup tags detect` (rebuild from the repo again).

## Step 4 — why a tracker connection

See [jira-mcp.md](jira-mcp.md): what the connection is for, the worked example, the
Atlassian MCP setup, the GitHub alternative and paste mode.

## Step 5 — app navigation

The wizard never builds the navigation skill for you. It offers to connect one you already
have, or to skip and come back. The package ships `.claude/skills/appNavigation/SKILL.md` as a
description of what the skill should do — implementing it is app-specific work, see
[app-navigation.md](app-navigation.md). Connecting the placeholder before it is implemented is
allowed (the wizard says so), so the rules and `/todoFromTicket` already produce the
`/appNavigation` items while you work on it.

## Team use

Commit `.claude/prompt-todo/config.json`, `RULES.md`, the skills and the hook. A teammate who
clones the project gets the same flow; they run `/todoSetup todo` once for their own todo
file, and `/todoSetup permissions` if they want the allow rules (that file is personal).
