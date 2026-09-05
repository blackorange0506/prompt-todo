#!/usr/bin/env bash
# Android driver for /appNavigation: adb + Maestro. Called by scripts/appNavigation.sh with the
# resolved plan in NAV_* environment variables; bash 3.2 compatible.
#
#   driver.sh ensure_installed   the right build (package, versionCode) is on the device, else build + install
#   driver.sh launch             start the app's task afresh
#   driver.sh login              run the login flow only
#   driver.sh navigate           launch + login (unless manual/none) + one level.yaml per level
#   driver.sh doctor             check adb, a device, maestro
#
# Env from the dispatcher:
#   NAV_APP_ID             applicationId (android.package with {env} expanded)
#   NAV_LAUNCH_ACTIVITY    fully-qualified launch activity
#   NAV_BUILD              build + install command, run from the project root ({env} expanded)
#   NAV_VERSION_CODE       wanted versionCode ("" → any)
#   NAV_CURRENT            1 → uninstall + rebuild from the working tree unconditionally
#   NAV_VERSION_CODE_FROM  "file:key" where the working tree's versionCode is read, e.g. gradle.properties:app.versionCode
#   NAV_VERSION_BUMP_PATTERN  commit-subject pattern with {versionCode}; when the wanted code differs from
#                          the working tree's, that commit is checked out for the build (clean tree required)
#   NAV_LOGIN_*, NAV_USERNAME/PASSWORD, NAV_READY_SEL, NAV_LEVEL_COUNT, NAV_LEVEL_i_*   (see run.sh)
#   APPNAV_DEVICE_SERIAL / APPNAV_DEVICE_HOST / APPNAV_STRICT_VERSION=1 / MAESTRO_BIN

set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$HERE/../../scripts/lib/common.sh"
# shellcheck source=adb.sh
. "$HERE/adb.sh"
# shellcheck source=../maestro/run.sh
. "$HERE/../maestro/run.sh"

CMD="${1:-}"
[ -n "$CMD" ] || nav_err "usage: driver.sh ensure_installed|launch|login|navigate|doctor" 2

# ---- device introspection ------------------------------------------------------------

is_installed() {
  local out
  out="$(adb_shell "pm path $NAV_APP_ID 2>/dev/null" | tr -d '\r' || true)"
  [ -n "$out" ]
}

installed_version_code() {
  adb_shell "dumpsys package $NAV_APP_ID 2>/dev/null" | tr -d '\r' | grep -E 'versionCode=' | head -1 \
    | sed -E 's/.*versionCode=([0-9]+).*/\1/' || true
}

# The working tree's versionCode, from NAV_VERSION_CODE_FROM ("file:key"): a `key=N` or
# `key = N` line in that file. Empty when unknown.
tree_version_code() {
  local spec="${NAV_VERSION_CODE_FROM:-}" file key
  [ -n "$spec" ] || return 0
  file="${spec%%:*}"; key="${spec#*:}"
  [ -f "$PROJECT_ROOT/$file" ] || return 0
  grep -E "^[[:space:]]*$(printf '%s' "$key" | sed 's/\./\\./g')[[:space:]]*=[[:space:]]*[0-9]+" "$PROJECT_ROOT/$file" \
    | head -1 | sed -E 's/.*=[[:space:]]*([0-9]+).*/\1/' || true
}

find_bump_commit() {
  local pattern="${NAV_VERSION_BUMP_PATTERN:-}" subject
  [ -n "$pattern" ] || return 0
  subject="$(printf '%s' "$pattern" | sed "s/{versionCode}/$1/")"
  git -C "$PROJECT_ROOT" log --grep="$(printf '%s' "$subject" | sed 's/[][\.*^$]/\\&/g')" --pretty=%H | head -1
}

run_build() {
  [ -n "${NAV_BUILD:-}" ] || nav_err "android.build is empty in app.json — cannot install; install the app yourself and re-run"
  nav_log "build: $NAV_BUILD"
  ( cd "$PROJECT_ROOT" && ANDROID_SERIAL="$ADB_SERIAL" bash -c "$NAV_BUILD" ) || nav_err "build command failed"
}

build_at_version() {
  local want="$1" tree commit branch
  tree="$(tree_version_code)"
  if [ -z "$want" ] || [ -z "$tree" ] || [ "$want" = "$tree" ]; then run_build; return 0; fi
  commit="$(find_bump_commit "$want")"
  if [ -z "$commit" ]; then
    nav_warn "no commit matches the version bump pattern for versionCode $want — building the working tree (versionCode $tree)"
    run_build; return 0
  fi
  if [ -n "$(git -C "$PROJECT_ROOT" status --porcelain)" ]; then
    nav_err "working tree is dirty; commit or stash before a build at another versionCode ($want → commit ${commit:0:10}), or use --current"
  fi
  branch="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$branch" != "HEAD" ] || branch="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  nav_log "checkout ${commit:0:10} (versionCode $want); back to $branch afterwards"
  trap 'git -C "$PROJECT_ROOT" checkout --quiet "'"$branch"'" || nav_warn "failed to restore '"$branch"'"' EXIT
  git -C "$PROJECT_ROOT" checkout --quiet "$commit"
  run_build
  git -C "$PROJECT_ROOT" checkout --quiet "$branch"
  trap - EXIT
}

# ---- commands --------------------------------------------------------------------------

cmd_doctor() {
  require_adb; nav_log "adb: $(command -v adb)"
  select_device
  nav_log "maestro: $(find_maestro)"
  nav_log "doctor ok"
}

cmd_ensure_installed() {
  select_device
  local want="${NAV_VERSION_CODE:-}" have="" installed=0 need=0
  if is_installed; then installed=1; have="$(installed_version_code)"; nav_log "installed: $NAV_APP_ID versionCode=${have:-?}"; else nav_log "$NAV_APP_ID is not installed"; fi
  if [ "${NAV_CURRENT:-0}" = 1 ]; then need=1; nav_log "--current: reinstalling from the working tree"
  elif [ "$installed" = 0 ]; then need=1
  elif [ -n "$want" ] && [ "$want" != "$have" ]; then need=1; fi
  if [ "$need" = 0 ]; then nav_log "installed build matches — nothing to do"; return 0; fi
  [ "${APPNAV_STRICT_VERSION:-0}" != 1 ] || nav_err "installed build does not match (strict mode)"
  if [ "$installed" = 1 ]; then nav_log "adb uninstall $NAV_APP_ID"; adb_run uninstall "$NAV_APP_ID" >/dev/null 2>&1 || true; fi
  if [ "${NAV_CURRENT:-0}" = 1 ]; then run_build; else build_at_version "$want"; fi
  is_installed || nav_err "build finished but $NAV_APP_ID is not on the device — check the build output"
  nav_log "installed: versionCode=$(installed_version_code)"
}

cmd_launch() {
  select_device
  # -f 0x10008000 = NEW_TASK | CLEAR_TASK: a fresh task whether the process is alive or not.
  if [ -n "${NAV_LAUNCH_ACTIVITY:-}" ]; then
    adb_shell am start -W -n "$NAV_APP_ID/$NAV_LAUNCH_ACTIVITY" -f 0x10008000 >/dev/null 2>&1 \
      || nav_warn "am start returned non-zero; Maestro's launchApp will try again"
  else
    adb_shell monkey -p "$NAV_APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  fi
}

case "$CMD" in
  doctor)           cmd_doctor ;;
  ensure_installed) cmd_ensure_installed ;;
  launch)           cmd_launch ;;
  login)            select_device; maestro_login android "$ADB_SERIAL" ;;
  navigate)         cmd_launch; maestro_navigate android "$ADB_SERIAL" ;;
  *) nav_err "unknown command: $CMD" 2 ;;
esac
