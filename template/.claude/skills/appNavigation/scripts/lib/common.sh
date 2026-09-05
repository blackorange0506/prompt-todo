#!/usr/bin/env bash
# Shared helpers for the appNavigation scripts and drivers. bash 3.2 compatible.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"    # from scripts/
#   nav_log / nav_warn / nav_err                          # stderr; nav_err exits 1
#   SKILL_DIR, SCRIPTS_DIR, PROJECT_ROOT, APP_CONFIG      # paths
#   app_get <dotted.path> [default]                       # one value from app.json
#   app_expand <template> [k=v ...]                       # {env} {Env} {ENV} substitution
#   creds_get <env>                                       # USERNAME=… / PASSWORD=… lines, or exit 1
#   rx_escape <string>                                    # for Maestro `text:` regexes

set -u

_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$_COMMON_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
if git -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  PROJECT_ROOT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
fi
APP_CONFIG="${APPNAV_CONFIG:-$SKILL_DIR/app.json}"
APPCFG="$_COMMON_DIR/appcfg.py"

nav_log()  { printf '\033[0;36m[appNavigation]\033[0m %s\n' "$*" >&2; }
nav_warn() { printf '\033[0;33m[appNavigation WARN]\033[0m %s\n' "$*" >&2; }
nav_err()  { printf '\033[0;31m[appNavigation ERROR]\033[0m %s\n' "$1" >&2; exit "${2:-1}"; }

require_python3() { command -v python3 >/dev/null 2>&1 || nav_err "python3 is required"; }

app_get()    { python3 "$APPCFG" "$APP_CONFIG" get "$@"; }
app_expand() { python3 "$APPCFG" "$APP_CONFIG" expand "$@"; }
app_levels() { python3 "$APPCFG" "$APP_CONFIG" levels; }
app_envs()   { python3 "$APPCFG" "$APP_CONFIG" environments; }
app_env()    { python3 "$APPCFG" "$APP_CONFIG" env "$1"; }
app_check()  { python3 "$APPCFG" "$APP_CONFIG" check; }

creds_get() {
  local env="$1" file="${APPNAV_CREDENTIALS_FILE:-$SKILL_DIR/credentials.json}"
  if [ ! -f "$file" ]; then
    if [ -f "$SKILL_DIR/credentials.example.json" ] && [ -z "${APPNAV_CREDENTIALS_FILE:-}" ]; then
      cp "$SKILL_DIR/credentials.example.json" "$file"
      nav_warn "created $file from the example — fill in real logins per environment and re-run"
    fi
    return 1
  fi
  python3 - "$file" "$env" <<'PY'
import json, sys
path, env = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception as e:
    sys.stderr.write("[appNavigation] %s: %s\n" % (path, e)); sys.exit(1)
d = data.get(env) if isinstance(data, dict) else None
if not isinstance(d, dict):
    sys.exit(1)
u, p = d.get("username", ""), d.get("password", "")
if not u or not p or "REDACTED" in (u, p):
    sys.exit(1)
print("USERNAME=%s" % u)
print("PASSWORD=%s" % p)
PY
}

rx_escape() { printf '%s' "$1" | sed -E 's/[][\\.^$*+?(){}|]/\\&/g'; }

# Maestro binary: MAESTRO_BIN → ~/.maestro/bin/maestro → PATH.
find_maestro() {
  local m="${MAESTRO_BIN:-$HOME/.maestro/bin/maestro}"
  [ -x "$m" ] || m="$(command -v maestro 2>/dev/null || true)"
  [ -n "$m" ] && [ -x "$m" ] || nav_err "maestro not found. Install with: curl -Ls 'https://get.maestro.mobile.dev' | bash — or set MAESTRO_BIN."
  printf '%s' "$m"
}
