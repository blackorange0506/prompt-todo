#!/usr/bin/env bash
# The Playwright driver against the static BestPizza fixture page. Skipped (exit 0) when
# playwright is not installed in the driver directory.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$ROOT/template/.claude/skills/appNavigation"
FD="$SK/drivers/frontend"
if ! command -v node >/dev/null 2>&1 || ! ( cd "$FD" && node -e "import('playwright').then(()=>process.exit(0),()=>process.exit(1))" 2>/dev/null ); then
  echo "  skip frontend: playwright not installed (cd $FD && npm install && npx playwright install chromium)"
  exit 0
fi
D="$(new_tmp frontend)"
URL="file://$ROOT/tests/fixtures/frontend/index.html"
python3 - "$SK/app.example.json" "$D/app.json" "$URL" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["platform"] = "frontend"; c["frontend"] = {"baseUrl": {"stage": sys.argv[3]}, "headless": True}
json.dump(c, open(sys.argv[2], "w"))
PY
printf '{"stage":{"username":"qa@example.com","password":"pw"}}' > "$D/creds.json"
export APPNAV_CONFIG="$D/app.json" APPNAV_CREDENTIALS_FILE="$D/creds.json" APPNAV_KEEP_OPEN_SECONDS=0
run() { bash "$SK/scripts/appNavigation.sh" "$@"; }

out="$(printf 'Server: stage\nRestaurant: Harbour\nPizza: Four Cheese\nTopping: Basil\n' | run --spec - 2>&1)"
assert_eq "three levels rc" "0" "$?"
assert_contains "logged in"  "$out" 'logged in as qa@example.com'
assert_contains "level 3"    "$out" 'level 3: Topping → "Basil"'
assert_contains "final url"  "$out" 'URL: file://'
assert_contains "url on topping" "$out" '#topping/Basil'

out="$(printf 'Server: stage\nRestaurant: Downtown\n' | run --spec - 2>&1)"
assert_eq "ambiguous rc 42" "42" "$?"
assert_contains "CHOOSE block" "$out" 'CHOOSE level=Restaurant'
assert_contains "candidate 2"  "$out" '2) Downtown East'

out="$(printf 'Server: stage\nRestaurant: Downtown\nPizza: Margherita\n' | APPNAV_RESTAURANT_PICK=1 run --spec - 2>&1)"
assert_eq "pick rc 0" "0" "$?"
assert_contains "pick used"  "$out" 'pick 1 of 2'
assert_contains "pizza url"  "$out" '#pizza/Margherita'

out="$(printf 'Server: stage\nRestaurant: Nowhere\n' | run --spec - 2>&1)"
assert_eq "no match rc 0" "0" "$?"
assert_contains "no match warning" "$out" 'no row contains "Nowhere"'

out="$(printf 'Server: stage\n' | run --spec - --login-only 2>&1)"
assert_eq "login only rc 0" "0" "$?"
assert_contains "login only url" "$out" '#home'
report frontend
