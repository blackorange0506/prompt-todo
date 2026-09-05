#!/usr/bin/env bash
# Frontend (web) driver for /appNavigation: Playwright in Chromium. Called by
# scripts/appNavigation.sh with the resolved plan in NAV_* variables.
#
#   driver.sh ensure_installed   node + the playwright package in this directory + chromium
#   driver.sh launch             no-op (the browser is started by navigate)
#   driver.sh login              open NAV_BASE_URL and log in only
#   driver.sh navigate           open, log in (unless none/manual), walk the levels
#   driver.sh doctor             the same checks as ensure_installed
#
# Setup, once:  cd drivers/frontend && npm install && npx playwright install chromium

set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$HERE/../../scripts/lib/common.sh"

CMD="${1:-}"
[ -n "$CMD" ] || nav_err "usage: driver.sh ensure_installed|launch|login|navigate|doctor" 2

check_tools() {
  command -v node >/dev/null 2>&1 || nav_err "node not found — install Node.js 18+"
  if ! ( cd "$HERE" && node -e "import('playwright').then(()=>process.exit(0),()=>process.exit(1))" ); then
    nav_err "playwright is not installed for the driver. Run:  cd $HERE && npm install && npx playwright install chromium"
  fi
  nav_log "node $(node --version), playwright present"
}

case "$CMD" in
  doctor|ensure_installed) check_tools ;;
  launch) : ;;
  login)    ( cd "$HERE" && node appNavigation.mjs --login-only ) ;;
  navigate) ( cd "$HERE" && node appNavigation.mjs ) ;;
  *) nav_err "unknown command: $CMD" 2 ;;
esac
