#!/usr/bin/env python3
"""Read app.json for the shell scripts (bash 3.2 has no JSON and no associative arrays).

  appcfg.py <app.json> get <dotted.path> [default]   one scalar (dicts/lists → JSON)
  appcfg.py <app.json> levels                        KEY<TAB>aliases,csv<TAB>search<TAB>row<TAB>ready   per level
  appcfg.py <app.json> environments                  NAME<TAB>aliases,csv<TAB>allow(1|0)                per environment
  appcfg.py <app.json> env <name-or-alias>           the canonical environment name, exit 2 when unknown,
                                                     exit 3 when automation is not allowed for it
  appcfg.py <app.json> expand <template> env=<e> ... substitute {env} {Env} {ENV} and any k=v given
  appcfg.py <app.json> check                         validate; print problems; exit 1 on any

A missing file is an error for every command except `levels`/`environments`, which then print
nothing (the parser falls back to accepting any `Key:` line).
"""
import json
import os
import sys


def die(msg, code=1):
    sys.stderr.write("[appcfg] %s\n" % msg)
    sys.exit(code)


def load(path, required=True):
    if not os.path.exists(path):
        if required:
            die("app config not found: %s (copy app.example.json to app.json and fill it in)" % path, 3)
        return None
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        die("%s is not valid JSON: %s" % (path, e))


def walk(cfg, dotted):
    cur = cfg
    for part in [p for p in dotted.split(".") if p]:
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        elif isinstance(cur, list) and part.isdigit() and int(part) < len(cur):
            cur = cur[int(part)]
        else:
            return None
    return cur


def envs(cfg):
    out = []
    for name, spec in (cfg.get("environments") or {}).items():
        spec = spec or {}
        aliases = [a for a in (spec.get("aliases") or []) if a]
        allow = spec.get("allowAutomation")
        if allow is None:
            allow = name.lower() not in ("prod", "production")
        out.append((name, aliases, bool(allow)))
    return out


def canonical_env(cfg, name):
    q = name.strip().lower()
    for n, aliases, allow in envs(cfg):
        if q == n.lower() or q in [a.lower() for a in aliases]:
            return n, allow
    return None, False


def check(cfg, path):
    problems = []
    if cfg.get("platform") not in ("android", "ios", "frontend"):
        problems.append("platform must be android, ios or frontend")
    if not envs(cfg):
        problems.append("environments must list at least one environment")
    d = cfg.get("defaultEnvironment")
    if d and canonical_env(cfg, d)[0] is None:
        problems.append("defaultEnvironment %r is not in environments" % d)
    p = cfg.get("platform")
    if p == "android":
        a = cfg.get("android") or {}
        for k in ("package", "launchActivity", "build"):
            if not a.get(k):
                problems.append("android.%s is required" % k)
    elif p == "ios":
        i = cfg.get("ios") or {}
        for k in ("bundleId", "appName", "build"):
            if not i.get(k):
                problems.append("ios.%s is required" % k)
    elif p == "frontend":
        f = cfg.get("frontend") or {}
        if not isinstance(f.get("baseUrl"), dict) or not f["baseUrl"]:
            problems.append("frontend.baseUrl must map environment → URL")
    login = cfg.get("login") or {}
    if login.get("kind", "none") not in ("web-form", "native", "none"):
        problems.append("login.kind must be web-form, native or none")
    if login.get("kind", "none") != "none":
        sel = login.get("selectors") or {}
        for k in ("username", "password"):
            if not sel.get(k):
                problems.append("login.selectors.%s is required for login.kind=%s (submit may be empty: Enter)" % (k, login.get("kind")))
    levels = cfg.get("levels")
    if not isinstance(levels, list) or not levels:
        problems.append("levels must list at least one screen")
    else:
        seen = set()
        for i, lv in enumerate(levels):
            key = (lv or {}).get("key")
            if not key or not key.replace("_", "").isalnum():
                problems.append("levels[%d].key must be a single word" % i)
                continue
            for n in [key] + list((lv.get("aliases") or [])):
                if n.lower() in seen:
                    problems.append("level name %r used twice" % n)
                seen.add(n.lower())
            scr = lv.get("screen") or {}
            for k in ("row", "ready"):
                if not scr.get(k):
                    problems.append("levels[%d].screen.%s is required" % (i, k))
    for pr in problems:
        print("[appcfg] %s: %s" % (path, pr))
    return not problems


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    path, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd in ("levels", "environments"):
        cfg = load(path, required=False)
        if cfg is None:
            return
        if cmd == "levels":
            for lv in cfg.get("levels") or []:
                scr = lv.get("screen") or {}
                print("\t".join([lv.get("key", ""), ",".join(lv.get("aliases") or []),
                                 scr.get("search", "") or "", scr.get("row", "") or "", scr.get("ready", "") or ""]))
        else:
            for n, aliases, allow in envs(cfg):
                print("\t".join([n, ",".join(aliases), "1" if allow else "0"]))
        return
    cfg = load(path)
    if cmd == "get":
        if not args:
            die("get needs a path", 2)
        v = walk(cfg, args[0])
        if v is None:
            if len(args) > 1:
                print(args[1])
            return
        if isinstance(v, bool):
            print("true" if v else "false")
        elif isinstance(v, (dict, list)):
            print(json.dumps(v))
        else:
            print(v)
    elif cmd == "env":
        if not args:
            die("env needs a name", 2)
        n, allow = canonical_env(cfg, args[0])
        if n is None:
            die("unknown environment %r; app.json knows: %s" % (args[0], ", ".join(e[0] for e in envs(cfg))), 2)
        if not allow:
            die("environment %r is not allowed for automation (set environments.%s.allowAutomation to true to override)" % (n, n), 3)
        print(n)
    elif cmd == "expand":
        if not args:
            die("expand needs a template", 2)
        tpl = args[0]
        subs = {}
        for kv in args[1:]:
            if "=" in kv:
                k, v = kv.split("=", 1)
                subs[k] = v
        env = subs.get("env", "")
        subs.setdefault("Env", env[:1].upper() + env[1:])
        subs.setdefault("ENV", env.upper())
        for k, v in subs.items():
            tpl = tpl.replace("{%s}" % k, v)
        print(tpl)
    elif cmd == "check":
        sys.exit(0 if check(cfg, path) else 1)
    else:
        die("unknown command %r" % cmd, 2)


if __name__ == "__main__":
    main()
