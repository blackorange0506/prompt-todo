#!/usr/bin/env bash
#
# parse_spec.sh — read a free-form navigation spec from $1 (file path) or stdin and emit
# normalised KEY=VALUE lines on stdout. The level names come from app.json (levels[].key and
# aliases, case-insensitive); without an app.json every `Key: value` line is accepted.
#
# Spec format (every line optional, keys case-insensitive, markdown bullets tolerated):
#   Server: stage | test | dev | prod              (an environment name or alias from app.json)
#   App version: <versionCode> | <versionName>(<versionCode>)
#   <Level>: <id> | <Field Name> : <Field Value> | <Field Value>
#
# Output keys (only the ones present in the input are printed; LEVEL keys are upper-case):
#   SERVER=<canonical environment name>     exit 2 when unknown, 3 when automation is refused
#   VERSION_CODE=<int>
#   LEVEL_<KEY>_ID=<int>
#   LEVEL_<KEY>_FIELD_NAME=<string>
#   LEVEL_<KEY>_FIELD_VALUE=<string>
#   LEVEL_<KEY>_QUERY=<string>              what the driver types into the level's search:
#                                           the field value, else the free text, else the id
#
# Within a `|`-separated line every alternative is optional. The first integer-only alternative
# is the id; the first `<name> : <value>` alternative the field; otherwise the first non-integer
# text is the free-text fallback.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

print_help() {
  cat <<'HELP'
Usage: parse_spec.sh <spec-file>      # read spec from file
       parse_spec.sh -                # read spec from stdin
       parse_spec.sh -h | --help

Emits KEY=VALUE lines on stdout, one per resolved spec field. Unrecognised lines are ignored.
Logs go to stderr. APPNAV_CONFIG names the app.json to use (default: the skill's own).
HELP
}

case "${1:-}" in
  -h|--help) print_help; exit 0 ;;
  '') print_help >&2; exit 2 ;;
esac

SRC="$1"
if [ "$SRC" = "-" ]; then
  RAW="$(cat -)"
else
  [ -f "$SRC" ] || { printf '[parse_spec] not a file: %s\n' "$SRC" >&2; exit 2; }
  RAW="$(cat -- "$SRC")"
fi

trim() {
  local s="${1-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr ' -' '__'; }
is_int() { [[ "$1" =~ ^-?[0-9]+$ ]]; }

# The levels app.json knows: "KEY<TAB>aliases" per line (empty without an app.json).
LEVELS="$(app_levels 2>/dev/null || true)"

# Prints the canonical level key for a spec key, or nothing.
level_key_for() {
  local q key aliases a
  q="$(lower "$1")"
  [ -n "$LEVELS" ] || return 0
  while IFS=$'\t' read -r key aliases _rest; do
    [ -n "$key" ] || continue
    [ "$(lower "$key")" = "$q" ] && { printf '%s' "$key"; return 0; }
    local IFS_SAVE="$IFS"; IFS=','
    for a in $aliases; do
      [ "$(lower "$a")" = "$q" ] && { IFS="$IFS_SAVE"; printf '%s' "$key"; return 0; }
    done
    IFS="$IFS_SAVE"
  done <<EOT
$LEVELS
EOT
  return 0
}

canonical_server() {
  local s="$1"
  if [ -f "$APP_CONFIG" ]; then
    app_env "$s"        # exits 2 / 3 with its own message
  else
    lower "$s"
  fi
}

split_alternatives() {
  local raw="$1" piece IFS='|'
  # shellcheck disable=SC2206
  local parts=($raw)
  for piece in "${parts[@]}"; do
    piece="$(trim "$piece")"
    [ -n "$piece" ] && printf '%s\n' "$piece"
  done
  return 0
}

emit_level() {
  # $1 = upper-case key, $2 = raw RHS
  local key="$1" rhs="$2" alt id_set=0 field_set=0 fallback="" fname="" fval="" id=""
  while IFS= read -r alt; do
    [ -n "$alt" ] || continue
    if [ $id_set -eq 0 ] && is_int "$alt"; then
      id="$alt"; printf 'LEVEL_%s_ID=%s\n' "$key" "$alt"; id_set=1; continue
    fi
    if [ $field_set -eq 0 ] && [[ "$alt" == *":"* ]]; then
      fname="$(trim "${alt%%:*}")"; fval="$(trim "${alt#*:}")"
      if [ -n "$fname" ] && [ -n "$fval" ]; then
        printf 'LEVEL_%s_FIELD_NAME=%s\nLEVEL_%s_FIELD_VALUE=%s\n' "$key" "$fname" "$key" "$fval"
        field_set=1; continue
      fi
    fi
    [ -z "$fallback" ] && fallback="$alt"
  done <<EOT
$(split_alternatives "$rhs")
EOT
  local query=""
  if [ -n "$fval" ]; then query="$fval"; elif [ -n "$fallback" ]; then query="$fallback"; else query="$id"; fi
  [ -n "$query" ] && printf 'LEVEL_%s_QUERY=%s\n' "$key" "$query"
  return 0
}

while IFS= read -r line; do
  line="${line%$'\r'}"
  line="$(trim "$line")"
  [ -n "$line" ] || continue
  # Markdown tolerance: "- Server: stage", "* Server: stage", "**Server:** stage".
  line="${line#- }"
  line="${line#\* }"
  line="${line//\*\*/}"
  [[ "$line" == *":"* ]] || continue
  key="$(trim "${line%%:*}")"
  rhs="$(trim "${line#*:}")"
  [ -n "$rhs" ] || continue
  key_lc="$(lower "$key")"
  case "$key_lc" in
    server|environment|env)
      first="$(trim "$(printf '%s' "$rhs" | cut -d'|' -f1)")"
      env="$(canonical_server "$first")"
      [ -n "$env" ] && printf 'SERVER=%s\n' "$env"
      ;;
    'app version'|appversion|version|versioncode|'version code'|build)
      first="$(trim "$(printf '%s' "$rhs" | cut -d'|' -f1)")"
      if is_int "$first"; then
        printf 'VERSION_CODE=%s\n' "$first"
      elif [[ "$first" =~ \(([0-9]+)\)[[:space:]]*$ ]]; then
        printf 'VERSION_CODE=%s\n' "${BASH_REMATCH[1]}"
      else
        printf '[parse_spec] WARN: App version is not an integer: %s\n' "$first" >&2
      fi
      ;;
    *)
      canon="$(level_key_for "$key")"
      if [ -n "$canon" ]; then
        emit_level "$(upper "$canon")" "$rhs"
      elif [ -z "$LEVELS" ] && [[ "$key" =~ ^[A-Za-z][A-Za-z0-9\ _-]*$ ]]; then
        emit_level "$(upper "$key")" "$rhs"
      fi
      # otherwise: prose, ignored
      ;;
  esac
done <<EOT
$RAW
EOT
