# Filling the appNavigation carcass

`/appNavigation` opens your app at the screen a ticket describes. The package ships the
machinery — a spec parser, a dispatcher, an Android driver (adb + Maestro), an iOS driver
(simctl + Maestro) and a web driver (Playwright) — and none of the knowledge about your app.
That knowledge goes into two files and a handful of test ids in the app itself. Budget an
afternoon for the first platform; the flow works without any of it in the meantime.

## 1. `app.json`

```bash
cd .claude/skills/appNavigation
cp app.example.json app.json          # the sample app BestPizza; edit every value
python3 scripts/lib/appcfg.py app.json check
```

| key                          | meaning                                                                    |
|------------------------------|----------------------------------------------------------------------------|
| `platform`                   | the default driver: `android`, `ios` or `frontend`                         |
| `defaultEnvironment`         | used when a spec has no `Server:` line                                     |
| `environments.<name>`        | `aliases` accepted on the `Server:` line; `allowAutomation: false` refuses the environment (the default for `prod`) |
| `android.package`            | applicationId; `{env}` / `{Env}` / `{ENV}` are replaced by the environment  |
| `android.launchActivity`     | fully-qualified activity started with a fresh task                         |
| `android.build`              | shell command that builds **and installs** on `$ANDROID_SERIAL`, run from the project root |
| `android.versionCodeFrom`    | `file:key` where the working tree's versionCode lives (`gradle.properties:app.versionCode`) |
| `android.versionBumpCommitPattern` | commit subject with `{versionCode}`; lets `App version:` check out that commit for the build |
| `ios.bundleId`, `ios.appName` | the bundle id and the `.app` name                                         |
| `ios.build`                  | shell command run from the project root; `{udid}` is the simulator; the driver then finds the `.app` through `ios.project` + `ios.scheme` (`xcodebuild -showBuildSettings`) or the newest one in DerivedData |
| `ios.simulator`              | preferred simulator name                                                   |
| `frontend.baseUrl.<env>`     | URL per environment; `frontend.headless`                                   |
| `login.kind`                 | `web-form` (an HTML form in a web view / custom tab), `native` (the app's own fields) or `none` |
| `login.loginButton`          | id of the button that opens the form, if the app starts on a landing screen |
| `login.selectors`            | ids of the `username` and `password` inputs and the `submit` button (empty submit → Enter) |
| `login.readySelector`        | id visible once logged in — the driver skips the login when it already is   |
| `levels[]`                   | the screens, top to bottom: `key` (what a ticket writes), `aliases`, `screen.search` (the search field, optional), `screen.row` (the id every list row carries), `screen.ready` (the id visible once the row's screen is open) |

### Ids

- **Android**: Compose `Modifier.testTag("restaurant_row")` (exposed as the resource id when
  `testTagsAsResourceId` is set on the root) or a View's `android:id` / content description.
- **iOS**: `accessibilityIdentifier`.
- **Web**: `data-testid="restaurant_row"`. A value starting with `#`, `.`, `[` or `/` is used
  as a CSS / XPath selector instead.

A list row must carry the **same id on every row**, with the text on its children; the flows
find the row that contains the query text and tap it. For the web-form login the ids are the
HTML `id` attributes of the form's inputs.

## 2. `credentials.json`

```bash
cp credentials.example.json credentials.json     # gitignored by install.sh
```

One entry per environment name (aliases resolve to it): `{"stage": {"username": "…",
"password": "…"}}`. Leave `prod` out.

## 3. Tools per platform

| platform | needs                                                                  | check                  |
|----------|------------------------------------------------------------------------|------------------------|
| android  | adb on PATH, a device or emulator, Maestro (`curl -Ls "https://get.maestro.mobile.dev" \| bash`) | `bash drivers/android/driver.sh doctor` |
| ios      | Xcode, a simulator, Maestro                                            | `bash drivers/ios/driver.sh doctor`     |
| frontend | Node 18+, then `cd drivers/frontend && npm install && npx playwright install chromium` | `bash drivers/frontend/driver.sh doctor` |

## 4. Try it

```bash
bash scripts/appNavigation.sh --spec - --dry-run <<'SPEC'
Server: stage
Restaurant: Downtown
Pizza: Margherita
SPEC
```

The dry run prints the plan (driver, environment, app id, build command, login, levels) and
touches nothing. Drop `--dry-run` for the real thing; `--manual-login` pauses for you to log
in by hand, `--current` rebuilds from the working tree.

## 5. Connect it

```
/todoSetup appNavigation
```

Pick *Connect an existing skill* → `appNavigation`. From then on `/todoFromTicket` writes the
`/appNavigation` item for tickets with a context block, and typing its `#N` runs this skill.

## Extending

- **Anything app-specific before the walk** — a data sync to trigger, a dialog to dismiss, an
  id to resolve from a database — goes into a `before_navigate` command in your driver's
  `driver.sh` (call it from `navigate`), or into extra steps in a copy of
  `drivers/maestro/flows/level.yaml`. Print a `CHOOSE level=<key>` block and exit 42 when a
  resolver finds several candidates; the dispatcher and the skill relay it.
- **A physical iPhone** — the shipped iOS driver targets the simulator; `devicectl` install /
  launch verbs are the replacement for `simctl` in `drivers/ios/driver.sh`.
- **Your own navigation skill** — you do not need this carcass at all: `/todoSetup
  appNavigation` connects any skill that accepts the spec lines as sub-bullets.
