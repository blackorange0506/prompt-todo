#!/usr/bin/env bash
# detect_platforms.py: repo fixtures → platforms, and the tag set built from them.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DETECT="$ROOT/template/.claude/prompt-todo/bin/detect_platforms.py"
D="$(new_tmp detect)"

mkdir -p "$D/android/app/src/main" "$D/gradle-android" "$D/maven" "$D/jvm" "$D/cpp" "$D/web" "$D/node" \
         "$D/multi/app/src/main" "$D/multi/ios/App.xcodeproj" "$D/electron" "$D/empty" "$D/skipped/node_modules/x"
touch "$D/android/app/src/main/AndroidManifest.xml"
printf 'plugins { alias(libs.plugins.android.application) }\n' > "$D/gradle-android/build.gradle.kts"
printf '<project/>\n' > "$D/maven/pom.xml"
printf 'plugins { id("java-library") }\n' > "$D/jvm/build.gradle.kts"
printf 'project(x)\n' > "$D/cpp/CMakeLists.txt"; printf 'int main(){}\n' > "$D/cpp/main.cpp"
printf '{"dependencies":{"react":"18"}}\n' > "$D/web/package.json"
printf '{"dependencies":{"express":"4"}}\n' > "$D/node/package.json"
touch "$D/multi/app/src/main/AndroidManifest.xml"
printf '{"devDependencies":{"electron":"30"}}\n' > "$D/electron/package.json"
printf '{"dependencies":{"react":"18"}}\n' > "$D/skipped/node_modules/x/package.json"

platforms() { prompt_todo_py "$DETECT" --root "$1" --json | prompt_todo_py -c 'import json,sys; print(",".join(json.load(sys.stdin)["platforms"]))'; }
tags()      { prompt_todo_py "$DETECT" --root "$1" --tags | prompt_todo_py -c 'import json,sys; t=json.load(sys.stdin); print(",".join(r["tag"] for r in t["list"]) + "|" + t["default"] + "|" + ",".join(t["ignore"]))'; }

assert_eq "android manifest"        "Android"      "$(platforms "$D/android")"
assert_eq "android gradle plugin"   "Android"      "$(platforms "$D/gradle-android")"
assert_eq "maven is backend"        "Backend"      "$(platforms "$D/maven")"
assert_eq "plain jvm gradle"        "Backend"      "$(platforms "$D/jvm")"
assert_eq "cmake with c++ sources"  "Desktop"      "$(platforms "$D/cpp")"
assert_eq "react is web"            "Web"          "$(platforms "$D/web")"
assert_eq "express is backend"      "Backend"      "$(platforms "$D/node")"
assert_eq "electron is desktop"     "Desktop"      "$(platforms "$D/electron")"
assert_eq "android + ios"           "Android,IOS"  "$(platforms "$D/multi")"
assert_eq "empty repo"              ""             "$(platforms "$D/empty")"
assert_eq "node_modules skipped"    ""             "$(platforms "$D/skipped")"
assert_eq "plain output"            "no platform detected" "$(prompt_todo_py "$DETECT" --root "$D/empty")"
assert_contains "plain output names evidence" "$(prompt_todo_py "$DETECT" --root "$D/android")" 'Android  app/src/main/AndroidManifest.xml'

assert_eq "tags: single platform"   "Android,Docs,Infra|" "$(tags "$D/android" | sed 's/|QA,Admin$//')"
assert_eq "tags: two platforms get + rows" "Android,IOS,Android+,IOS+,Docs,Infra" "$(tags "$D/multi" | cut -d'|' -f1)"
assert_eq "tags: web brings browsers" "Web,MobileWeb,Chrome,Safari,Firefox,Edge,Docs,Infra" "$(tags "$D/web" | cut -d'|' -f1)"
assert_eq "tags: nothing detected"  "Docs,Infra"   "$(tags "$D/empty" | cut -d'|' -f1)"
assert_eq "tags: no default, ignore rows" "|QA,Admin" "$(tags "$D/android" | cut -d'|' -f2-)"
assert_eq "tags: by hand"           "Android,Backend,Android+,Backend+,Docs,Infra" "$(prompt_todo_py "$DETECT" --tags Android Backend | prompt_todo_py -c 'import json,sys; print(",".join(r["tag"] for r in json.load(sys.stdin)["list"]))')"
if prompt_todo_py "$DETECT" --tags Foo >/dev/null 2>&1; then fail "unknown platform accepted"; else pass "unknown platform refused"; fi
out="$(prompt_todo_py "$DETECT" --root "$D/android" --tags)"
assert_not_contains "no All tag"    "$out" '"All"'

# the tag object is what render_rules.py accepts
prompt_todo_py - "$ROOT/template/.claude/prompt-todo/config.example.json" "$D/cfg.json" "$out" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); c["tags"]=json.loads(sys.argv[3]); json.dump(c,open(sys.argv[2],"w"))
PY
if prompt_todo_py "$ROOT/template/.claude/prompt-todo/bin/render_rules.py" --config "$D/cfg.json" --check >/dev/null 2>&1; then pass "tag object validates"; else fail "tag object validates"; fi
report detect
