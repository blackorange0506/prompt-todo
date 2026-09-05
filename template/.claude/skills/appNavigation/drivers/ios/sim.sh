#!/usr/bin/env bash
# Simulator helpers for the ios driver. bash 3.2 compatible.
#
#   select_simulator   → sets SIM_UDID: APPNAV_IOS_SIM (name or udid) → NAV_SIMULATOR (the
#                        app.json preference, booted or not) → the one booted simulator →
#                        the newest available iPhone (booted here)
#   sim_run <verb> …   → xcrun simctl <verb> $SIM_UDID …

set -u
SIM_UDID=""

require_xcode() {
  command -v xcrun >/dev/null 2>&1 || nav_err "xcrun not found. Install Xcode and its command line tools."
  xcrun simctl help >/dev/null 2>&1 || nav_err "simctl unavailable. Run: sudo xcode-select -s /Applications/Xcode.app"
}

_all_sims()    { xcrun simctl list devices available 2>/dev/null | sed -n 's/^ *\(.*\) (\([0-9A-F-]\{36\}\)) (\(Booted\|Shutdown\)).*/\2	\1	\3/p'; }
_booted_sims() { _all_sims | awk -F'\t' '$3=="Booted"'; }
_iphones()     { _all_sims | awk -F'\t' '$2 ~ /^iPhone/'; }

_boot_and_wait() {
  nav_log "booting simulator $1"
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
  open -a Simulator >/dev/null 2>&1 || true
}

_ensure_booted() { _booted_sims | grep -q "^$1" || _boot_and_wait "$1"; }

select_simulator() {
  require_xcode
  local want="${APPNAV_IOS_SIM:-}" hit
  if [ -n "$want" ]; then
    hit="$(_all_sims | awk -F'\t' -v q="$want" '$1==q || $2==q {print $1; exit}')"
    [ -n "$hit" ] || nav_err "APPNAV_IOS_SIM=$want matches no available simulator"
    SIM_UDID="$hit"; _ensure_booted "$SIM_UDID"; nav_log "simulator: $want ($SIM_UDID)"; return 0
  fi
  if [ -n "${NAV_SIMULATOR:-}" ]; then
    hit="$(_all_sims | awk -F'\t' -v q="$NAV_SIMULATOR" '$2==q {print $1; exit}')"
    if [ -n "$hit" ]; then SIM_UDID="$hit"; _ensure_booted "$SIM_UDID"; nav_log "simulator: $NAV_SIMULATOR ($SIM_UDID)"; return 0; fi
    nav_warn "app.json ios.simulator '$NAV_SIMULATOR' is not available here"
  fi
  local booted count
  booted="$(_booted_sims)"
  count="$(printf '%s' "$booted" | grep -c . || true)"
  if [ "$count" -eq 1 ]; then
    SIM_UDID="$(printf '%s' "$booted" | cut -f1)"; nav_log "simulator: $(printf '%s' "$booted" | cut -f2) ($SIM_UDID)"; return 0
  fi
  if [ "$count" -gt 1 ]; then
    printf '%s\n' "$booted" | awk -F'\t' '{ printf "  - %s (%s)\n", $2, $1 }' >&2
    nav_err "several simulators are booted; set APPNAV_IOS_SIM=<name|udid>"
  fi
  local candidate; candidate="$(_iphones | tail -1)"
  [ -n "$candidate" ] || nav_err "no iPhone simulator available; create one in Xcode > Settings > Platforms"
  SIM_UDID="$(printf '%s' "$candidate" | cut -f1)"
  nav_log "simulator: $(printf '%s' "$candidate" | cut -f2) ($SIM_UDID)"
  _boot_and_wait "$SIM_UDID"
}

sim_run() { local verb="$1"; shift; xcrun simctl "$verb" "$SIM_UDID" "$@"; }
