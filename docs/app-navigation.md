# App navigation: from a ticket to the screen

`/appNavigation` (alias `/openApp`) opens your app at the place a ticket describes. It is the
optional half of the flow: `/todoFromTicket` writes a `/appNavigation` item when a ticket
ends in a context block and a navigation skill is connected, and typing that item's `#N`
opens the app there, so the dev items' `QA:` checks can start from the right screen.

```markdown
- [ ] #32 PROJ-321 /appNavigation
  - Server: stage
  - Restaurant: Downtown
  - Pizza: Margherita
  - Topping: Olives
```

The package ships this as a **carcass**: everything that is the same for every app, and
nothing that is specific to yours. Filling it is described in
`.claude/skills/appNavigation/README.md` (copied into your project by `install.sh`); this page
is the design.

## The contract

```
appNavigation.sh --spec <file|-> [--driver android|ios|frontend] [--dry-run] [--current] [--manual-login]
```

- **Spec** — `Server:` (an environment from `app.json`), `App version:`, then one line per
  level: `<Level>: <id> | <Field> : <Value> | <Value>`. Level names and aliases come from
  `app.json`; every line and every `|` alternative is optional. The run walks the levels in
  `app.json` order and stops at the deepest one the spec names without a gap.
- **Plan** — the dispatcher resolves the environment, the login, the build and the levels,
  prints the plan, and exports it as `NAV_*` variables. `--dry-run` stops there.
- **Driver** — `drivers/<platform>/driver.sh` gets three calls: `ensure_installed`
  (right build on the device, else build + install), `launch`, `navigate` (login unless
  already past it, then one `level.yaml` per level).
- **Exit codes** — `0` reached the deepest level; `3` no or invalid `app.json` (the carcass
  is not filled); `42` a level matched several rows: the driver printed a `CHOOSE level=<key>`
  block, and the caller re-runs with `APPNAV_<KEY>_PICK=<n>`.

## The config model — `app.json`

The sample app in every example is BestPizza (web + Android + iOS; screens
Restaurant → Pizza → Topping). `app.example.json` is its config; the README lists every key.
Three ideas carry the model:

1. **Environments** replace hard-coded flavour lists: `Server: staging` resolves through
   `environments.stage.aliases`; `{env}` in the package name or the build command becomes
   `stage`; `prod` is refused unless `allowAutomation` is set.
2. **Login** is one of three shapes — a web form (an OAuth page in a web view), the app's own
   fields, or none — described by the ids of the username, password and submit elements and
   the id that proves the app is past the login.
3. **Levels** are the screens, each with the id of its search field (optional), the id every
   list row carries, and the id visible once the row's screen is open. The flows type the
   query, find the row containing it, tap, and wait.

## Drivers

| driver     | tools                          | mechanics                                                                          |
|------------|--------------------------------|------------------------------------------------------------------------------------|
| `android`  | adb, Maestro                   | `pm path` / `dumpsys` decide whether to build; `am start` opens a fresh task; Maestro runs `login_*.yaml` and `level.yaml` per level; ids are Compose test tags |
| `ios`      | Xcode, simctl, Maestro         | `get_app_container` + `CFBundleVersion` decide whether to build; `simctl install/launch`; the same Maestro flows; ids are accessibility identifiers |
| `frontend` | Node, Playwright               | Chromium opens `frontend.baseUrl.<env>`, fills the login, walks the levels with `data-testid` selectors; several matching rows → the CHOOSE block and exit 42; prints the final `URL:` |

The two Maestro drivers share `drivers/maestro/flows/`. Maestro has no loops, so
`drivers/maestro/run.sh` writes the run's root flow (one `runFlow: level.yaml` per level)
to a temp file. Backend-only projects have no driver: skip the step in `/todoSetup`.

## What was left out on purpose

The flow this was extracted from resolved ids against a database pulled from the device,
dismissed app-specific dialogs and waited for a data sync before descending. None of that
generalises. The extension point is a `before_navigate` command in your `driver.sh` (called
from `navigate`) or extra steps in a copy of `level.yaml`; a resolver that finds several
candidates prints the `CHOOSE` block and exits 42 like the frontend driver does.

## Connecting a skill you already have

`/todoSetup appNavigation` → *Connect an existing skill* lists `.claude/skills/*`. Any skill
that takes the spec lines as sub-bullets qualifies; the rules and `/todoFromTicket` then use
its name. The carcass can also be connected before it is filled — the wizard warns, and the
`/appNavigation` items start appearing in ticket blocks while you work on it.

## Testing the carcass

- `bash tests/parse_spec.test.sh` — the grammar, against `app.example.json` and without one.
- `bash tests/app_navigation.test.sh` — dry runs, the level gap, exit 3, exit 42 through a
  stub driver, the generated Maestro root flow.
- `bash tests/frontend.test.sh` — Playwright against `tests/fixtures/frontend/index.html`, a
  static BestPizza page (login form, searchable restaurants, menu, toppings); skipped when
  Playwright is not installed in `drivers/frontend`.
