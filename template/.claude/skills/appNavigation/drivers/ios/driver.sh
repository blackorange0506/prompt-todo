#!/usr/bin/env bash
# iOS driver for /appNavigation: xcodebuild + simctl + Maestro (simulator only). Called by
# scripts/appNavigation.sh with the resolved plan in NAV_* variables; bash 3.2 compatible.
#
#   driver.sh ensure_installed   the bundle (NAV_APP_ID, CFBundleVersion) is on the simulator, else build + install
#   driver.sh launch             (re)launch the app
#   driver.sh login              login flow only
#   driver.sh navigate           launch + login + levels through Maestro
#   driver.sh doctor             check xcrun, a simulator, maestro
#
# Env from the dispatcher: NAV_APP_ID (bundle id), NAV_APP_NAME (the .app name), NAV_BUILD (run from
# the project root; {udid} is replaced by the simulator's udid), NAV_PROJECT + NAV_SCHEME (to locate
# the built .app through xcodebuild -showBuildSettings; otherwise DerivedData is searched for the
# newest NAV_APP_NAME.app), NAV_SIMULATOR, NAV_VERSION_CODE, NAV_CURRENT, and the login/level set.
# Every Maestro `id:` is the view's accessibilityIdentifier.

set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$HERE/../../scripts/lib/common.sh"
# shellcheck source=sim.sh
. "$HERE/sim.sh"
# shellcheck source=../maestro/run.sh
. "$HERE/../maestro/run.sh"

CMD="${1:-}"
[ -n "$CMD" ] || nav_err "usage: driver.sh ensure_installed|launch|login|navigate|doctor" 2

app_container() { sim_run get_app_container "$NAV_APP_ID" app 2>/dev/null || true; }
installed_version() {
  local c; c="$(app_container)"
  [ -n "$c" ] && [ -f "$c/Info.plist" ] && plutil -extract CFBundleVersion raw "$c/Info.plist" 2>/dev/null || true
}

built_app_path() {
  local dir=""
  if [ -n "${NAV_PROJECT:-}" ] && [ -n "${NAV_SCHEME:-}" ]; then
    dir="$(cd "$PROJECT_ROOT" && xcodebuild -project "$NAV_PROJECT" -scheme "$NAV_SCHEME" -configuration Debug -sdk iphonesimulator -showBuildSettings 2>/dev/null \
           | awk -F' = ' '/^ +TARGET_BUILD_DIR = /{print $2; exit}')"
  fi
  if [ -n "$dir" ] && [ -d "$dir/$NAV_APP_NAME.app" ]; then printf '%s' "$dir/$NAV_APP_NAME.app"; return 0; fi
  # Fallback: the newest matching bundle in DerivedData.
  find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name "$NAV_APP_NAME.app" -path '*iphonesimulator*' 2>/dev/null \
    | while IFS= read -r p; do printf '%s\t%s\n' "$(stat -f %m "$p" 2>/dev/null || stat -c %Y "$p")" "$p"; done | sort -n | tail -1 | cut -f2
}

run_build() {
  [ -n "${NAV_BUILD:-}" ] || nav_err "ios.build is empty in app.json — build and install the app yourself, then re-run"
  local cmd; cmd="$(printf '%s' "$NAV_BUILD" | sed "s/{udid}/$SIM_UDID/g")"
  nav_log "build: $cmd"
  ( cd "$PROJECT_ROOT" && bash -c "$cmd" ) || nav_err "build command failed"
  local app; app="$(built_app_path)"
  [ -n "$app" ] && [ -d "$app" ] || nav_err "built $NAV_APP_NAME.app not found; set ios.project + ios.scheme in app.json"
  nav_log "install: $app"
  sim_run install "$app"
}

cmd_ensure_installed() {
  select_simulator
  local have want="${NAV_VERSION_CODE:-}" need=0
  have="$(installed_version)"
  if [ -n "$have" ]; then nav_log "installed: $NAV_APP_ID CFBundleVersion=$have"; else nav_log "$NAV_APP_ID is not installed"; fi
  if [ "${NAV_CURRENT:-0}" = 1 ]; then need=1
  elif [ -z "$have" ]; then need=1
  elif [ -n "$want" ] && [ "$want" != "$have" ]; then need=1; fi
  if [ "$need" = 0 ]; then nav_log "installed build matches — nothing to do"; return 0; fi
  [ "${APPNAV_STRICT_VERSION:-0}" != 1 ] || nav_err "installed build does not match (strict mode)"
  [ -z "$want" ] || [ "${NAV_CURRENT:-0}" = 1 ] || nav_warn "building the working tree; CFBundleVersion $want was asked for"
  run_build
}

cmd_launch() {
  select_simulator
  sim_run terminate "$NAV_APP_ID" >/dev/null 2>&1 || true
  sim_run launch "$NAV_APP_ID" >/dev/null 2>&1 || nav_warn "simctl launch returned non-zero; Maestro's launchApp will try again"
}

case "$CMD" in
  doctor)           require_xcode; select_simulator; nav_log "maestro: $(find_maestro)"; nav_log "doctor ok" ;;
  ensure_installed) cmd_ensure_installed ;;
  launch)           cmd_launch ;;
  login)            select_simulator; maestro_login ios "$SIM_UDID" ;;
  navigate)         cmd_launch; maestro_navigate ios "$SIM_UDID" ;;
  *) nav_err "unknown command: $CMD" 2 ;;
esac
