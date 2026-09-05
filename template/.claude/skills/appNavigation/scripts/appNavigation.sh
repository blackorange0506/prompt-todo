#!/usr/bin/env bash
#
# appNavigation.sh — turn a spec (Server + the level lines) into a live app screen.
#
#   appNavigation.sh --spec <file|->  [--driver android|ios|frontend] [--dry-run]
#                                     [--current] [--manual-login] [--login-only]
#
# 1. reads app.json (APPNAV_CONFIG or the skill's own) and validates it
# 2. parses the spec (parse_spec.sh) and picks the environment
# 3. loads the environment's login from credentials.json (unless login.kind is none / --manual-login)
# 4. resolves the levels in app.json order, up to the first one the spec does not name
# 5. exports the plan as NAV_* variables and hands over to drivers/<driver>/driver.sh:
#      ensure_installed → (launch + manual login pause) → navigate
#
# Exit codes: 0 ok · 1 error · 2 bad arguments · 3 app.json missing/invalid ·
#             42 ambiguous match — the driver printed a CHOOSE block on stderr; re-run with
#             APPNAV_<LEVEL>_PICK=<n> (1-based) in the environment.
# bash 3.2 compatible.

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

EXIT_AMBIGUOUS=42

print_help() {
  sed -n '3,/^# bash 3.2/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'HELP'

Environment overrides:
  APPNAV_CONFIG              app.json to use (default: the skill's own)
  APPNAV_CREDENTIALS_FILE    credentials.json to use
  APPNAV_<LEVEL>_PICK        1-based pick when re-running after exit 42 (LEVEL upper-case)
  APPNAV_DEVICE_SERIAL / APPNAV_DEVICE_HOST     android device
  APPNAV_IOS_SIM             ios simulator name or udid
  APPNAV_STRICT_VERSION=1    fail instead of reinstalling on a version mismatch
  MAESTRO_BIN                path to the maestro CLI
HELP
}

SPEC_SRC=""; DRIVER=""; DRY=0; CURRENT=0; MANUAL=0; LOGIN_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --spec) [ $# -ge 2 ] || nav_err "--spec needs a value" 2; SPEC_SRC="$2"; shift 2 ;;
    --driver) [ $# -ge 2 ] || nav_err "--driver needs a value" 2; DRIVER="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --current) CURRENT=1; shift ;;
    --manual-login) MANUAL=1; shift ;;
    --login-only) LOGIN_ONLY=1; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) print_help >&2; nav_err "unknown argument: $1" 2 ;;
  esac
done
[ -n "$SPEC_SRC" ] || { print_help >&2; nav_err "missing --spec <file|->" 2; }

# ---- 1. app.json ---------------------------------------------------------------------------

require_python3
if [ ! -f "$APP_CONFIG" ]; then
  nav_err "no app config at $APP_CONFIG — the carcass is not filled in yet. Copy app.example.json to app.json and follow $SKILL_DIR/README.md" 3
fi
app_check || nav_err "fix app.json and re-run" 3

# ---- 2. spec -----------------------------------------------------------------------------

if [ "$SPEC_SRC" = "-" ]; then RAW_SPEC="$(cat -)"; else
  [ -f "$SPEC_SRC" ] || nav_err "spec file not found: $SPEC_SRC" 2
  RAW_SPEC="$(cat -- "$SPEC_SRC")"
fi
[ -n "$(printf '%s' "$RAW_SPEC" | tr -d '[:space:]')" ] || nav_err "spec is empty" 2

set +e
PARSED="$(printf '%s\n' "$RAW_SPEC" | bash "$SCRIPT_DIR/parse_spec.sh" -)"
rc=$?
set -e
[ "$rc" -eq 0 ] || exit "$rc"
get_kv() { printf '%s\n' "$PARSED" | sed -n "s/^$1=//p" | head -1; }

ENV_NAME="$(get_kv SERVER)"
if [ -z "$ENV_NAME" ]; then
  d="$(app_get defaultEnvironment '')"
  [ -n "$d" ] || nav_err "the spec has no Server: line and app.json has no defaultEnvironment" 2
  ENV_NAME="$(app_env "$d")"
  nav_log "no Server: line — using defaultEnvironment '$ENV_NAME'"
fi
VERSION_CODE="$(get_kv VERSION_CODE)"
[ -n "$DRIVER" ] || DRIVER="$(app_get platform android)"
case "$DRIVER" in android|ios|frontend) ;; *) nav_err "unknown driver '$DRIVER' (android, ios, frontend)" 2 ;; esac
DRIVER_SH="$SKILL_DIR/drivers/$DRIVER/driver.sh"

# ---- 3. login --------------------------------------------------------------------------------

export NAV_ENV="$ENV_NAME" NAV_VERSION_CODE="$VERSION_CODE" NAV_CURRENT="$CURRENT" NAV_MANUAL_LOGIN="$MANUAL"
NAV_LOGIN_KIND="$(app_get login.kind none)"; export NAV_LOGIN_KIND
NAV_LOGIN_BUTTON="$(app_get login.loginButton '')"; export NAV_LOGIN_BUTTON
NAV_LOGIN_USERNAME_SEL="$(app_get login.selectors.username '')"; export NAV_LOGIN_USERNAME_SEL
NAV_LOGIN_PASSWORD_SEL="$(app_get login.selectors.password '')"; export NAV_LOGIN_PASSWORD_SEL
NAV_LOGIN_SUBMIT_SEL="$(app_get login.selectors.submit '')"; export NAV_LOGIN_SUBMIT_SEL
NAV_READY_SEL="$(app_get login.readySelector '')"; export NAV_READY_SEL
export NAV_USERNAME="" NAV_PASSWORD=""
if [ "$NAV_LOGIN_KIND" != none ] && [ "$MANUAL" = 0 ]; then
  CREDS="$(creds_get "$ENV_NAME" || true)"
  [ -n "$CREDS" ] || nav_err "no usable login for '$ENV_NAME' in ${APPNAV_CREDENTIALS_FILE:-$SKILL_DIR/credentials.json} — fill it in, or pass --manual-login"
  NAV_USERNAME="$(printf '%s\n' "$CREDS" | sed -n 's/^USERNAME=//p')"
  NAV_PASSWORD="$(printf '%s\n' "$CREDS" | sed -n 's/^PASSWORD=//p')"
fi

# ---- 4. levels --------------------------------------------------------------------------------

COUNT=0; STOPPED=""; SKIPPED=""
# shellcheck disable=SC2034  # aliases: read but only the key matters here
while IFS=$'\t' read -r key aliases search row ready; do
  [ -n "$key" ] || continue
  ukey="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]' | tr ' -' '__')"
  query="$(get_kv "LEVEL_${ukey}_QUERY")"
  if [ -z "$query" ]; then
    [ -n "$STOPPED" ] || STOPPED="$key"
    continue
  fi
  if [ -n "$STOPPED" ]; then SKIPPED="$SKIPPED $key"; continue; fi
  COUNT=$((COUNT + 1))
  pick=""
  eval "pick=\${APPNAV_${ukey}_PICK:-}"
  export "NAV_LEVEL_${COUNT}_KEY=$key" "NAV_LEVEL_${COUNT}_QUERY=$query" "NAV_LEVEL_${COUNT}_QUERY_RX=$(rx_escape "$query")" \
         "NAV_LEVEL_${COUNT}_ID=$(get_kv "LEVEL_${ukey}_ID")" "NAV_LEVEL_${COUNT}_FIELD=$(get_kv "LEVEL_${ukey}_FIELD_NAME")" \
         "NAV_LEVEL_${COUNT}_SEARCH=$search" "NAV_LEVEL_${COUNT}_ROW=$row" "NAV_LEVEL_${COUNT}_READY=$ready" \
         "NAV_LEVEL_${COUNT}_PICK=$pick"
done <<EOT
$(app_levels)
EOT
export NAV_LEVEL_COUNT="$COUNT"
[ -z "$SKIPPED" ] || nav_warn "the spec names$SKIPPED but not '$STOPPED' above them — stopping at the last reachable level"

# ---- 5. platform specifics --------------------------------------------------------------

case "$DRIVER" in
  android)
    NAV_APP_ID="$(app_expand "$(app_get android.package '')" "env=$ENV_NAME")"; export NAV_APP_ID
    NAV_LAUNCH_ACTIVITY="$(app_get android.launchActivity '')"; export NAV_LAUNCH_ACTIVITY
    NAV_BUILD="$(app_expand "$(app_get android.build '')" "env=$ENV_NAME")"; export NAV_BUILD
    NAV_VERSION_CODE_FROM="$(app_get android.versionCodeFrom '')"; export NAV_VERSION_CODE_FROM
    NAV_VERSION_BUMP_PATTERN="$(app_get android.versionBumpCommitPattern '')"; export NAV_VERSION_BUMP_PATTERN
    ;;
  ios)
    NAV_APP_ID="$(app_get ios.bundleId '')"; export NAV_APP_ID
    NAV_APP_NAME="$(app_get ios.appName '')"; export NAV_APP_NAME
    NAV_BUILD="$(app_expand "$(app_get ios.build '')" "env=$ENV_NAME")"; export NAV_BUILD
    NAV_SIMULATOR="$(app_get ios.simulator '')"; export NAV_SIMULATOR
    NAV_PROJECT="$(app_get ios.project '')"; export NAV_PROJECT
    NAV_SCHEME="$(app_get ios.scheme '')"; export NAV_SCHEME
    ;;
  frontend)
    export NAV_APP_ID="frontend"
    NAV_BASE_URL="$(app_get "frontend.baseUrl.$ENV_NAME" '')"; export NAV_BASE_URL
    [ -n "$NAV_BASE_URL" ] || nav_err "frontend.baseUrl has no entry for '$ENV_NAME' in app.json"
    NAV_HEADLESS="$(app_get frontend.headless false)"; export NAV_HEADLESS
    ;;
esac

# ---- plan ------------------------------------------------------------------------------------

print_plan() {
  printf 'driver:      %s\n' "$DRIVER"
  printf 'environment: %s\n' "$ENV_NAME"
  printf 'version:     %s%s\n' "${VERSION_CODE:-any}" "$([ "$CURRENT" = 1 ] && printf ' (--current: rebuild from the working tree)')"
  case "$DRIVER" in
    android)  printf 'app:         %s (%s)\n' "$NAV_APP_ID" "${NAV_LAUNCH_ACTIVITY:-launcher}"; printf 'build:       %s\n' "${NAV_BUILD:-<none>}" ;;
    ios)      printf 'app:         %s (%s)\n' "$NAV_APP_ID" "$NAV_APP_NAME"; printf 'build:       %s\n' "${NAV_BUILD:-<none>}" ;;
    frontend) printf 'url:         %s\n' "$NAV_BASE_URL" ;;
  esac
  if [ "$MANUAL" = 1 ]; then printf 'login:       manual (pause for you to log in)\n'
  elif [ "$NAV_LOGIN_KIND" = none ]; then printf 'login:       none\n'
  else printf 'login:       %s as %s\n' "$NAV_LOGIN_KIND" "$NAV_USERNAME"; fi
  local i=1 k q p
  [ "$COUNT" -gt 0 ] || printf 'levels:      none — the run ends after the login\n'
  while [ "$i" -le "$COUNT" ]; do
    eval "k=\${NAV_LEVEL_${i}_KEY}"; eval "q=\${NAV_LEVEL_${i}_QUERY}"; eval "p=\${NAV_LEVEL_${i}_PICK}"
    printf 'level %d:     %s → "%s"%s\n' "$i" "$k" "$q" "${p:+ (pick $p)}"
    i=$((i + 1))
  done
}

if [ "$DRY" = 1 ]; then
  nav_log "dry run — the plan:"
  print_plan | sed 's/^/  /' >&2
  exit 0
fi
print_plan | sed 's/^/  /' >&2

# ---- 6. driver -------------------------------------------------------------------------------

[ -f "$DRIVER_SH" ] || nav_err "driver not found: $DRIVER_SH"

run_driver() {
  set +e
  bash "$DRIVER_SH" "$1"
  local rc=$?
  set -e
  if [ "$rc" -eq "$EXIT_AMBIGUOUS" ]; then
    nav_warn "ambiguous match — see the CHOOSE block above; re-run with APPNAV_<LEVEL>_PICK=<n>"
    exit "$EXIT_AMBIGUOUS"
  fi
  [ "$rc" -eq 0 ] || nav_err "driver '$DRIVER' failed at '$1' (rc=$rc)" "$rc"
}

run_driver ensure_installed
if [ "$LOGIN_ONLY" = 1 ]; then run_driver login; nav_log "done (login only)"; exit 0; fi
if [ "$MANUAL" = 1 ]; then
  [ -t 0 ] || [ -r /dev/tty ] || nav_err "--manual-login needs a TTY"
  run_driver launch
  printf '\n[appNavigation] The app is up. Log in by hand, then press y to continue (q to abort).\n' >&2
  while :; do
    printf 'Continue? [y/q]: ' >&2
    IFS= read -r reply </dev/tty || nav_err "could not read from /dev/tty"
    case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')" in
      y|yes) break ;; q|quit|abort) nav_err "aborted" ;; *) printf 'y or q\n' >&2 ;;
    esac
  done
fi
run_driver navigate
nav_log "done — the app is on the deepest level the spec named"
