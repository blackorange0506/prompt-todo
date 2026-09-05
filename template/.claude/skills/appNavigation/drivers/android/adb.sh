#!/usr/bin/env bash
# adb helpers for the android driver. bash 3.2 compatible.
#
#   select_device        → sets ADB_SERIAL (APPNAV_DEVICE_SERIAL / APPNAV_DEVICE_HOST honoured)
#   adb_run / adb_shell  → adb -s $ADB_SERIAL …
#
# 1 device → use it; 0 → start-server, connect $APPNAV_DEVICE_HOST, reconnect offline, else fail;
# 2+ → APPNAV_DEVICE_SERIAL, or a numbered chooser on a TTY, else fail.

set -u
ADB_SERIAL=""

require_adb() {
  command -v adb >/dev/null 2>&1 || nav_err "adb not found on PATH. Install Android platform-tools or add them to PATH."
}

_list_devices() {
  adb devices -l 2>/dev/null \
    | awk 'NR>1 && $2=="device" {
        model="";
        for (i=3;i<=NF;i++) if ($i ~ /^model:/) { sub(/^model:/, "", $i); model=$i }
        printf "%s\t%s\n", $1, (model==""?"unknown":model)
      }'
}

_recover_adb() {
  nav_warn "No devices visible. Attempting recovery..."
  adb start-server >/dev/null 2>&1 || true
  if [ -n "${APPNAV_DEVICE_HOST:-}" ]; then
    nav_log "adb connect $APPNAV_DEVICE_HOST"
    adb connect "$APPNAV_DEVICE_HOST" >/dev/null 2>&1 || true
  fi
  adb reconnect offline >/dev/null 2>&1 || true
}

select_device() {
  require_adb
  local devices count
  devices="$(_list_devices)"
  if [ -z "$devices" ]; then
    _recover_adb
    devices="$(_list_devices)"
  fi
  [ -n "$devices" ] || nav_err "No connected device. Plug one in with USB debugging enabled, start an emulator, or set APPNAV_DEVICE_HOST=<ip:port> for wireless."
  count="$(printf '%s\n' "$devices" | wc -l | tr -d ' ')"

  if [ "$count" -eq 1 ]; then
    ADB_SERIAL="$(printf '%s' "$devices" | awk -F'\t' '{print $1}')"
    nav_log "device: $ADB_SERIAL"; return 0
  fi
  if [ -n "${APPNAV_DEVICE_SERIAL:-}" ]; then
    if printf '%s\n' "$devices" | awk -F'\t' '{print $1}' | grep -qx "$APPNAV_DEVICE_SERIAL"; then
      ADB_SERIAL="$APPNAV_DEVICE_SERIAL"; nav_log "device: $ADB_SERIAL (APPNAV_DEVICE_SERIAL)"; return 0
    fi
    nav_err "APPNAV_DEVICE_SERIAL=$APPNAV_DEVICE_SERIAL is not a connected device."
  fi
  if [ ! -t 0 ]; then
    printf '%s\n' "$devices" | awk -F'\t' '{ printf "  - %s (%s)\n", $1, $2 }' >&2
    nav_err "Several devices connected and no TTY. Set APPNAV_DEVICE_SERIAL=<serial> and re-run."
  fi
  nav_log "Several devices connected. Pick one:"
  local i=1 s m choice serials=()
  while IFS=$'\t' read -r s m; do
    printf '  %d) %s (%s)\n' "$i" "$s" "$m" >&2
    serials[i]="$s"; i=$((i + 1))
  done <<EOT
$devices
EOT
  while :; do
    printf 'Choice [1-%d]: ' "$((i - 1))" >&2
    read -r choice || nav_err "No selection received."
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then break; fi
    nav_warn "Invalid choice: $choice"
  done
  ADB_SERIAL="${serials[$choice]}"
  nav_log "device: $ADB_SERIAL"
}

adb_run()   { adb -s "$ADB_SERIAL" "$@"; }
adb_shell() { adb_run shell "$@"; }
