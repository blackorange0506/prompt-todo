---
name: appNavigation
description: "Open the app on a device, simulator or browser at the screen a ticket describes: from a ticket key, a ticket URL, free-form spec text (`Server:` plus the level lines app.json defines, e.g. `Restaurant: Downtown`), or a todo item whose text is `/appNavigation` with the spec as sub-bullets. Ensures the right build for the environment is installed, logs in with the environment's credentials, then walks the levels one screen at a time. A carcass: app.json, credentials.json and the test ids in the app must be filled in first (README.md). Also answers to /openApp. Use whenever the user wants the app opened at a place a ticket names — phrases like '/appNavigation PROJ-321', '/openApp PROJ-321', 'open the app at this restaurant', 'reproduce PROJ-321 on my device', 'navigate to the Margherita pizza'."
argument-hint: "<KEY | url | spec text> [--current] [--manual-login] [--driver android|ios|frontend]"
allowed-tools: Read, Glob, Grep, AskUserQuestion, Bash(bash .claude/skills/appNavigation/scripts/appNavigation.sh:*), Bash(bash .claude/skills/appNavigation/scripts/parse_spec.sh:*), Bash(bash .claude/skills/appNavigation/drivers/*), Bash(python3 .claude/skills/appNavigation/scripts/lib/appcfg.py:*), Bash(gh issue view:*), mcp__atlassian__getJiraIssue
---

# /appNavigation

Turns a locator — a ticket, its URL, spec text, or a `/appNavigation` todo item — into a live
app screen. The mechanics (which build, how to log in, which screens exist and how their lists
are searched) live in `app.json` and the driver for the platform; this skill only resolves the
spec and runs the script. Until `app.json` exists the script stops with a pointer to the
README: that is the carcass state, and it is fine to leave it so.

## Input forms

```
/appNavigation PROJ-321
/appNavigation https://yourcompany.atlassian.net/browse/PROJ-321
/appNavigation Server: stage
               Restaurant: Downtown
               Pizza: Margherita
               Topping: Olives
#32                       ← a todo item whose text is "/appNavigation" + the spec as sub-bullets
```

Every line is optional; every `|` alternative inside a line is optional. The levels are the
`levels[].key` (and `aliases`) of `app.json`, in order: the run walks them and stops at the
deepest one the spec names without a gap. Keys are case-insensitive; a leading `- ` or `**` is
ignored, so a todo item's sub-bullets are a spec as they are.

| Line           | Value                                                                              |
|----------------|------------------------------------------------------------------------------------|
| `Server:`      | an environment name or alias from `app.json` (`prod` is refused unless `allowAutomation`) |
| `App version:` | an integer version code, or `versionName(versionCode)` — `2.4.1(240)` → 240        |
| `<Level>:`     | `<id>` and/or `<Field> : <Value>` and/or `<Value>` — the value is typed into the level's search and matched against its rows |

## What Claude does

1. **Resolve the spec text.**
   - **Todo item** — its sub-bullets are the spec; pass them as they are.
   - **Ticket key / URL** — needs a configured tracker (`.claude/todo-flow/config.json`,
     `tracker.kind`): Jira → `mcp__atlassian__getJiraIssue` (markdown); GitHub →
     `gh issue view`. Pipe the description through `parse_spec.sh -` (it ignores prose); if it
     yields nothing, build the block from whatever environment / level mentions the text has
     and ask only for what is missing. No tracker → say so and ask for the spec text.
   - **Free text** — as is.
2. **Run the script** with the spec on stdin (the dry run first when the user asks what would
   happen, or when the spec came from prose):
   ```bash
   bash .claude/skills/appNavigation/scripts/appNavigation.sh --spec - [--dry-run] [--driver X] [--current] [--manual-login] <<'SPEC'
   Server: stage
   Restaurant: Downtown
   Pizza: Margherita
   SPEC
   ```
   `--current` installs from the working tree and ignores `App version:`; `--manual-login`
   pauses on the terminal for a hand login (TTY only); `--driver` overrides `platform`.
3. **Exit 42** — a level matched several rows (the frontend driver, or a `before_navigate`
   resolver you added): the script printed
   ```
   [appNavigation] CHOOSE level=Restaurant
     1) Downtown  Main St 1
     2) Downtown East  Main St 99
   ```
   Present the candidates with `AskUserQuestion`, then re-run with the same spec plus
   `APPNAV_RESTAURANT_PICK=<n>` in the environment.
4. **Exit 3** — no or invalid `app.json`: the carcass is not filled. Say so, point to
   `.claude/skills/appNavigation/README.md`, and stop; do not try to fill it in unasked.
5. **Report** the screen reached (the deepest level in the plan the script printed), any
   warning about levels it could not reach, and for the frontend driver the final `URL:`.

## Environment overrides

- `APPNAV_DEVICE_SERIAL` / `APPNAV_DEVICE_HOST` — Android device (several connected → required).
- `APPNAV_IOS_SIM` — simulator name or udid.
- `APPNAV_<LEVEL>_PICK` — 1-based pick after exit 42.
- `APPNAV_STRICT_VERSION=1` — fail instead of reinstalling on a version mismatch.
- `APPNAV_CONFIG`, `APPNAV_CREDENTIALS_FILE` — other config / credentials files.
- `MAESTRO_BIN` — the maestro CLI. `APPNAV_KEEP_OPEN_SECONDS` — frontend: how long the browser stays open.

## Files

- `app.json` — the app: platform, environments, build, login, levels (`app.example.json` is
  the sample BestPizza app).
- `credentials.json` — per-environment logins, gitignored (`credentials.example.json`).
- `scripts/appNavigation.sh` — dispatcher; `scripts/parse_spec.sh` — the spec grammar.
- `drivers/android`, `drivers/ios` (Maestro flows in `drivers/maestro/flows`), `drivers/frontend`
  (Playwright).

```bash
bash .claude/skills/appNavigation/scripts/appNavigation.sh -h
```
