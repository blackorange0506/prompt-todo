#!/usr/bin/env bash
# The appNavigation dispatcher: dry runs, exit codes, the generated Maestro flow.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$ROOT/template/.claude/skills/appNavigation"
D="$(new_tmp appnav)"
printf '{"stage":{"username":"qa@example.com","password":"pw"},"dev":{"username":"dev@example.com","password":"pw"}}' > "$D/creds.json"
export APPNAV_CONFIG="$SK/app.example.json" APPNAV_CREDENTIALS_FILE="$D/creds.json"
run() { bash "$SK/scripts/appNavigation.sh" "$@"; }

out="$(printf -- '- Server: staging\n- **Restaurant:** Downtown\n- Pizza: Margherita\n- Topping: Extra : Olives\n' | run --spec - --dry-run 2>&1)"
assert_eq "dry run rc" "0" "$?"
assert_contains "env resolved"     "$out" 'environment: stage'
assert_contains "package expanded" "$out" 'com.bestpizza.app.stage.debug'
assert_contains "build expanded"   "$out" './gradlew :app:installStageDebug'
assert_contains "login line"       "$out" 'web-form as qa@example.com'
assert_contains "level 3"          "$out" 'level 3:     Topping → "Olives"'

out="$(printf 'Server: dev\nRestaurant: Downtown\nTopping: Olives\n' | run --spec - --dry-run 2>&1)"
assert_contains "gap warning"      "$out" "names Topping but not 'Pizza'"
assert_not_contains "gap stops"    "$out" 'level 2:'

out="$(printf 'Restaurant: Harbour\n' | run --spec - --dry-run --driver frontend 2>&1)"
assert_contains "default env"      "$out" "defaultEnvironment 'stage'"
assert_contains "frontend url"     "$out" 'https://stage.bestpizza.example.com'

out="$(printf 'Server: stage\n' | run --spec - --dry-run --driver ios --manual-login 2>&1)"
assert_contains "ios bundle"       "$out" 'com.bestpizza.app (BestPizza)'
assert_contains "manual login"     "$out" 'login:       manual'
assert_contains "no levels"        "$out" 'levels:      none'

printf 'Server: prod\n' | run --spec - --dry-run >/dev/null 2>&1 && fail "prod accepted" || assert_eq "prod → rc 3" "3" "$?"
printf 'Server: stage\n' | APPNAV_CONFIG="$D/missing.json" run --spec - --dry-run >"$D/m.out" 2>&1 && fail "missing config accepted" || assert_eq "missing app.json → rc 3" "3" "$?"
assert_contains "missing config message" "$(cat "$D/m.out")" 'not filled in yet'
printf '   \n' | run --spec - --dry-run >/dev/null 2>&1 && fail "empty accepted" || assert_eq "empty spec → rc 2" "2" "$?"
printf 'Server: stage\n' | APPNAV_CREDENTIALS_FILE="$D/nocreds.json" run --spec - --dry-run >"$D/c.out" 2>&1 && fail "no creds accepted" || assert_eq "no creds → rc 1" "1" "$?"
assert_contains "no creds message" "$(cat "$D/c.out")" 'no usable login'
printf 'Server: stage\n' | run --spec - --dry-run --driver desktop >/dev/null 2>&1 && fail "bad driver accepted" || assert_eq "bad driver → rc 2" "2" "$?"

# exit 42 from a stub driver is passed through; picks reach the driver
cp -R "$SK" "$D/skill"
cat > "$D/skill/drivers/android/driver.sh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  ensure_installed) echo "stub ensure_installed $NAV_APP_ID" >&2 ;;
  navigate)
    echo "stub navigate pick=$NAV_LEVEL_1_PICK count=$NAV_LEVEL_COUNT rx=$NAV_LEVEL_1_QUERY_RX" >&2
    if [ -z "$NAV_LEVEL_1_PICK" ]; then printf '[appNavigation] CHOOSE level=Restaurant\n  1) Downtown\n  2) Downtown East\n' >&2; exit 42; fi ;;
esac
STUB
out="$(printf 'Server: stage\nRestaurant: Down (town)\n' | APPNAV_CONFIG="$SK/app.example.json" bash "$D/skill/scripts/appNavigation.sh" --spec - 2>&1)"
assert_eq "stub → rc 42" "42" "$?"
assert_contains "CHOOSE relayed" "$out" 'CHOOSE level=Restaurant'
assert_contains "ambiguous hint" "$out" 'APPNAV_<LEVEL>_PICK'
out="$(printf 'Server: stage\nRestaurant: Down (town)\n' | APPNAV_RESTAURANT_PICK=2 APPNAV_CONFIG="$SK/app.example.json" bash "$D/skill/scripts/appNavigation.sh" --spec - 2>&1)"
assert_eq "pick → rc 0" "0" "$?"
assert_contains "pick reached driver" "$out" 'pick=2 count=1'
assert_contains "query regex-escaped" "$out" 'rx=Down \(town\)'

# the generated Maestro root flow
gen="$(
  NAV_APP_ID=com.bestpizza.app NAV_LOGIN_KIND=web-form NAV_READY_SEL=home_root NAV_LEVEL_COUNT=2 \
  NAV_LEVEL_1_QUERY=Downtown NAV_LEVEL_1_QUERY_RX=Downtown NAV_LEVEL_1_SEARCH=restaurant_search NAV_LEVEL_1_ROW=restaurant_row NAV_LEVEL_1_READY=restaurant_root \
  NAV_LEVEL_2_QUERY='Four Cheese' NAV_LEVEL_2_QUERY_RX='Four Cheese' NAV_LEVEL_2_SEARCH=menu_search NAV_LEVEL_2_ROW=pizza_row NAV_LEVEL_2_READY=pizza_root \
  bash -c '. "$1/scripts/lib/common.sh"; . "$1/drivers/maestro/run.sh"; f="$(_write_root_flow)"; cat "$f"; rm -f "$f"' _ "$SK"
)"
assert_eq "two level runFlows"   "2" "$(printf '%s\n' "$gen" | grep -c 'level.yaml')"
assert_eq "one login runFlow"    "1" "$(printf '%s\n' "$gen" | grep -c 'login_web_form.yaml')"
assert_contains "query with space quoted" "$gen" 'QUERY: "Four Cheese"'
assert_contains "absolute flow path"      "$gen" "file: $SK/drivers/maestro/flows/level.yaml"
gen="$(NAV_APP_ID=x NAV_LOGIN_KIND=none NAV_LEVEL_COUNT=0 bash -c '. "$1/scripts/lib/common.sh"; . "$1/drivers/maestro/run.sh"; f="$(_write_root_flow)"; cat "$f"; rm -f "$f"' _ "$SK")"
assert_eq "no login, no levels" "0" "$(printf '%s\n' "$gen" | grep -c 'runFlow')"

# every driver answers -h / usage without tools
for d in android ios frontend; do
  bash "$SK/drivers/$d/driver.sh" >/dev/null 2>&1 && fail "$d driver no-arg" || assert_eq "$d driver usage rc 2" "2" "$?"
done
report app_navigation
