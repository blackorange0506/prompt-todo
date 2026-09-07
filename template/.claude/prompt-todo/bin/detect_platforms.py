#!/usr/bin/env python3
"""Detect which platforms a repository contains and build the matching tag table.

Usage:
  detect_platforms.py                 # one line per platform: "Android  app/src/main/AndroidManifest.xml"
  detect_platforms.py --json          # {"platforms": [...], "evidence": {...}}
  detect_platforms.py --tags          # the "tags" object for config.json, built from the detection
  detect_platforms.py --tags Android IOS   # the "tags" object for the platforms given by hand
  detect_platforms.py --root DIR      # scan DIR instead of the git top level / cwd

Platforms: Android, IOS, Web, Backend, Desktop. Detection looks at build and manifest files up
to DEPTH levels deep, skipping build output and dependency directories. Desktop from plain
C/C++/Makefile sources counts only when nothing else matched.

Tag-set rule (the single source of truth for /todoSetup step 2):
  - one row per detected platform; Web also brings MobileWeb and the four browser rows;
  - "<P>+" rows only when two or more platforms are detected;
  - Docs and Infra always; ignore rows QA and Admin; no "All" tag and no default tag.
Exit code is 0 whether or not something was detected.
"""
import argparse
import json
import os
import re
import subprocess
import sys

DEPTH = 3
SKIP_DIRS = {".git", "node_modules", "build", ".gradle", "Pods", "target", "dist", ".idea",
             "out", "bin", "obj", "vendor", ".venv", "venv", "__pycache__", "DerivedData"}
ORDER = ["Android", "IOS", "Web", "Backend", "Desktop"]

MEANING = {
    "Android": "Android app only",
    "IOS": "iOS app only",
    "Web": "web frontend in a desktop browser",
    "MobileWeb": "web frontend in a phone browser",
    "Backend": "backend / API only",
    "Desktop": "desktop app (macOS / Windows / Linux)",
    "Docs": "documentation only",
    "Infra": "build, CI, tooling",
}
PLUS_NAME = {"Android": "Android", "IOS": "iOS", "Web": "the desktop browser",
             "Backend": "the backend", "Desktop": "the desktop app"}
BROWSERS = ["Chrome", "Safari", "Firefox", "Edge"]

WEB_DEPS = ("react", "vue", "@angular/core", "svelte", "next", "nuxt", "vite", "astro", "solid-js")
NODE_BACKEND_DEPS = ("express", "fastify", "@nestjs/core", "koa", "hono")
DESKTOP_DEPS = ("electron", "@tauri-apps/api", "@tauri-apps/cli")
PY_BACKEND = ("django", "fastapi", "flask")


def repo_root():
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except OSError:
        pass
    return os.getcwd()


def walk(root):
    """Yield (relative path, filename) for every file up to DEPTH levels deep."""
    root = os.path.abspath(root)
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")] if depth < DEPTH else []
        for name in filenames:
            yield (name if rel == "." else os.path.join(rel, name)), name
        for d in list(dirnames):
            # bundles that are directories: keep the name visible, do not descend
            if d.endswith((".xcodeproj", ".xcworkspace")):
                yield (d if rel == "." else os.path.join(rel, d)), d
                dirnames.remove(d)


def read(root, rel, limit=200000):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="ignore") as f:
            return f.read(limit)
    except OSError:
        return ""


def package_deps(text):
    try:
        data = json.loads(text)
    except ValueError:
        return set()
    deps = set()
    for key in ("dependencies", "devDependencies"):
        d = data.get(key)
        if isinstance(d, dict):
            deps.update(d.keys())
    return deps


def detect(root):
    found = {}          # platform -> evidence path
    native = None       # C/C++ evidence, used only as a fallback
    has_c_sources = False
    files = list(walk(root))

    def hit(platform, rel):
        if platform not in found:
            found[platform] = rel.replace(os.sep, "/")   # the same evidence path on Windows

    for rel, name in files:
        low = name.lower()
        # Android
        if name == "AndroidManifest.xml":
            hit("Android", rel)
        elif name in ("build.gradle", "build.gradle.kts"):
            text = read(root, rel)
            if re.search(r"com\.android\.(application|library)|android\.application|android\.library|^\s*android\s*\{", text, re.M):
                hit("Android", rel)
            if re.search(r"compose\.desktop|org\.jetbrains\.compose", text):
                hit("Desktop", rel)
            if re.search(r"org\.springframework|io\.ktor|ktor|micronaut|quarkus", text):
                hit("Backend", rel)
        # iOS
        if low.endswith((".xcodeproj", ".xcworkspace")) or name == "Podfile":
            hit("IOS", rel)
        elif name == "Package.swift" and re.search(r"\.iOS\(", read(root, rel)):
            hit("IOS", rel)
        elif name == "Info.plist":
            d = os.path.dirname(os.path.join(root, rel))
            try:
                if any(f.endswith(".swift") for f in os.listdir(d)):
                    hit("IOS", rel)
            except OSError:
                pass
        # Web / node backend / electron
        if name == "package.json":
            deps = package_deps(read(root, rel))
            if any(d in deps for d in WEB_DEPS):
                hit("Web", rel)
            if any(d in deps for d in NODE_BACKEND_DEPS):
                hit("Backend", rel)
            if any(d in deps for d in DESKTOP_DEPS):
                hit("Desktop", rel)
        elif name == "index.html" and os.sep not in rel:
            hit("Web", rel)
        # Backend
        if name == "pom.xml" or name == "go.mod" or name == "composer.json":
            hit("Backend", rel)
        elif name in ("requirements.txt", "pyproject.toml"):
            text = read(root, rel).lower()
            if any(p in text for p in PY_BACKEND):
                hit("Backend", rel)
        elif name == "Gemfile" and "rails" in read(root, rel):
            hit("Backend", rel)
        # Desktop
        if low.endswith((".sln", ".pro")):
            hit("Desktop", rel)
        elif low.endswith(".csproj"):
            text = read(root, rel)
            if re.search(r"UseWPF|UseWindowsForms|Microsoft\.NET\.Sdk\.WindowsDesktop|Avalonia|Microsoft\.Maui", text):
                hit("Desktop", rel)
            elif "Microsoft.NET.Sdk.Web" in text:
                hit("Backend", rel)
        if name in ("CMakeLists.txt", "Makefile", "meson.build") and native is None:
            native = rel
        if low.endswith((".c", ".cc", ".cpp", ".cxx")):
            has_c_sources = True

    # Maven / plain Gradle without an Android plugin: a JVM build is a backend
    if "Backend" not in found and "Android" not in found and "Desktop" not in found:
        for rel, name in files:
            if name in ("build.gradle", "build.gradle.kts") and re.search(r"java-library|application|kotlin\(\"jvm\"\)|org\.jetbrains\.kotlin\.jvm", read(root, rel)):
                hit("Backend", rel)
                break

    if not found and native and has_c_sources:
        found["Desktop"] = native

    platforms = [p for p in ORDER if p in found]
    return platforms, {p: found[p] for p in platforms}


def tag_set(platforms):
    platforms = [p for p in ORDER if p in platforms]
    rows = []
    for p in platforms:
        rows.append({"tag": p, "meaning": MEANING[p]})
        if p == "Web":
            rows.append({"tag": "MobileWeb", "meaning": MEANING["MobileWeb"]})
    if len(platforms) >= 2:
        for p in platforms:
            rows.append({"tag": p + "+", "meaning": "seen on %s, almost certainly elsewhere too: fix all, verify %s first"
                         % (PLUS_NAME[p], PLUS_NAME[p])})
    if "Web" in platforms:
        for b in BROWSERS:
            rows.append({"tag": b, "meaning": "the web frontend in %s only" % b})
    rows.append({"tag": "Docs", "meaning": MEANING["Docs"]})
    rows.append({"tag": "Infra", "meaning": MEANING["Infra"]})
    return {"default": "", "list": rows, "ignore": ["QA", "Admin"]}


def dump_tags(tags):
    lines = ['{', '    "default": "",', '    "list": [']
    rows = ['      {"tag": %s, "meaning": %s}' % (json.dumps(r["tag"]), json.dumps(r["meaning"])) for r in tags["list"]]
    lines.append(",\n".join(rows))
    lines.append('    ],')
    lines.append('    "ignore": %s' % json.dumps(tags["ignore"]))
    lines.append('  }')
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=None)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--tags", nargs="*", metavar="PLATFORM",
                    help="print the tags object; with names, for those platforms instead of detecting")
    a = ap.parse_args()
    root = a.root or repo_root()

    if a.tags is not None and a.tags:
        bad = [p for p in a.tags if p not in ORDER]
        if bad:
            sys.stderr.write("[detect_platforms] unknown platform(s): %s (known: %s)\n" % (", ".join(bad), ", ".join(ORDER)))
            sys.exit(1)
        print(dump_tags(tag_set(a.tags)))
        return

    platforms, evidence = detect(root)
    if a.tags is not None:
        print(dump_tags(tag_set(platforms)))
        return
    if a.json:
        print(json.dumps({"platforms": platforms, "evidence": evidence}, indent=2))
        return
    if not platforms:
        print("no platform detected")
        return
    width = max(len(p) for p in platforms)
    for p in platforms:
        print("%s  %s" % (p.ljust(width), evidence[p]))


if __name__ == "__main__":
    main()
