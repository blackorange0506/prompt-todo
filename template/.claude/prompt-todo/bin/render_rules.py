#!/usr/bin/env python3
"""Render .claude/prompt-todo/RULES.md from config.json and RULES.template.md.

Usage:
  render_rules.py                       # config.json + RULES.template.md → RULES.md, next to this script
  render_rules.py --config C --template T --out O
  render_rules.py --stdout              # print instead of writing
  render_rules.py --check               # validate the config only, write nothing

Placeholders in the template: {{projectTitle}}, {{userExample}}, {{ticketExample}},
{{confirmWords}}, {{confirmFirst}}, {{ignoreRows}}.
Generated blocks: <!-- prompt-todo:NAME --> … <!-- /prompt-todo:NAME --> for NAME in
tags, tracker, appNavigation. Whatever sits between the markers is replaced.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FLOW_DIR = os.path.dirname(HERE)

DEFAULT_CONFIG = {
    "version": 1,
    "projectTitle": "My App",
    "tags": {"default": "", "list": [], "ignore": ["QA", "Admin"]},
    "confirmWords": ["works", "fixed", "works, fixed"],
    "tracker": {"kind": "none", "jira": {"host": "", "projectKeys": []}, "github": {"repo": ""}},
    "attachmentsDir": "todoAttachments",
    "appNavigation": {"mode": "none", "skill": "appNavigation"},
    "codeMarkers": "on",
    "promptScores": "on",
}


def fail(msg):
    sys.stderr.write("[render_rules] " + msg + "\n")
    sys.exit(1)


def load_config(path):
    try:
        with open(path, encoding="utf-8") as f:
            cfg = json.load(f)
    except FileNotFoundError:
        fail("config not found: %s (run install.sh, or copy config.example.json to config.json)" % path)
    except json.JSONDecodeError as e:
        fail("config is not valid JSON: %s: %s" % (path, e))
    return validate(cfg)


def validate(cfg):
    if not isinstance(cfg, dict):
        fail("config must be a JSON object")
    merged = json.loads(json.dumps(DEFAULT_CONFIG))
    for k, v in cfg.items():
        if isinstance(v, dict) and isinstance(merged.get(k), dict):
            merged[k].update(v)
        else:
            merged[k] = v
    cfg = merged
    tags = cfg["tags"]
    if not isinstance(tags.get("list"), list):
        fail("tags.list must be a list")
    names = []
    for row in tags["list"]:
        if not isinstance(row, dict) or not row.get("tag") or not row.get("meaning"):
            fail("every tags.list entry needs \"tag\" and \"meaning\": %r" % (row,))
        t = row["tag"]
        if not re.match(r"^[A-Za-z][A-Za-z0-9+]*$", t):
            fail("tag %r: letters, digits and + only, no colon" % t)
        if t in names:
            fail("tag %r listed twice" % t)
        names.append(t)
    ignore = tags.get("ignore") or []
    if not isinstance(ignore, list):
        fail("tags.ignore must be a list")
    for t in ignore:
        if t in names:
            fail("tag %r is both in tags.list and tags.ignore" % t)
    default = tags.get("default") or ""
    if default and default not in names:
        fail("tags.default %r is not in tags.list" % default)
    words = cfg.get("confirmWords")
    if not isinstance(words, list) or not words or not all(isinstance(w, str) and w.strip() for w in words):
        fail("confirmWords must be a non-empty list of words")
    if cfg["tracker"].get("kind") not in ("none", "jira", "github"):
        fail("tracker.kind must be none, jira or github")
    if cfg["appNavigation"].get("mode") not in ("none", "existing"):
        fail("appNavigation.mode must be none or existing")
    if not re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", cfg["appNavigation"].get("skill") or ""):
        fail("appNavigation.skill must be a skill name (letters, digits, - and _)")
    if cfg.get("codeMarkers") not in ("on", "off"):
        fail("codeMarkers must be on or off")
    if cfg.get("promptScores") not in ("on", "off"):
        fail("promptScores must be on or off")
    if not cfg.get("projectTitle"):
        fail("projectTitle must not be empty")
    return cfg


def quote_words(words):
    q = ['`"%s"`' % w for w in words]
    if len(q) == 1:
        return q[0]
    return ", ".join(q[:-1]) + " or " + q[-1]


def ignore_rows(cfg):
    ig = cfg["tags"]["ignore"]
    if not ig:
        return "personal (ignored)"
    return "/".join("`%s:`" % t for t in ig)


def tags_block(cfg):
    tags = cfg["tags"]
    rows = []
    default = tags.get("default") or ""
    for row in tags["list"]:
        meaning = row["meaning"]
        if row["tag"] == default:
            meaning += " — also the **default** when no tag is present"
        rows.append(("`%s:`" % row["tag"], meaning))
    for t in tags["ignore"]:
        rows.append(("`%s:`" % t, "the user's personal row — **Claude ignores it entirely**"))
    if not rows:
        return "No tags are configured: an item's text starts right after its id (or ticket key).\n"
    w1 = max(len(r[0]) for r in rows + [("Tag", "")])
    w2 = max(len(r[1]) for r in rows + [("", "Meaning")])
    out = ["| %s | %s |" % ("Tag".ljust(w1), "Meaning".ljust(w2)),
           "|%s|%s|" % ("-" * (w1 + 2), "-" * (w2 + 2))]
    for a, b in rows:
        out.append("| %s | %s |" % (a.ljust(w1), b.ljust(w2)))
    if not default:
        out.append("")
        out.append("There is no default tag: an item without a tag simply has no tag.")
    return "\n".join(out) + "\n"


def tracker_block(cfg):
    kind = cfg["tracker"]["kind"]
    att = cfg["attachmentsDir"]
    if kind == "none":
        return ("No ticket tracker is connected: `/todoFromTicket` only works in paste mode (the ticket "
                "text pasted after the key). `/todoSetup tracker` connects Jira or GitHub Issues.\n")
    if kind == "jira":
        host = cfg["tracker"]["jira"].get("host") or "your Jira host"
        keys = ", ".join(cfg["tracker"]["jira"].get("projectKeys") or []) or "any"
        return ("Tickets come from Jira (`%s`, project keys: %s) through the Atlassian MCP server; "
                "`/todoFromTicket <KEY>` writes a ticket block and saves the ticket's attachments under "
                "`%s/<KEY>/`.\n" % (host, keys, att))
    repo = cfg["tracker"]["github"].get("repo") or "the repository"
    return ("Tickets are GitHub Issues of `%s`, read with the `gh` CLI; `/todoFromTicket <N>` writes a "
            "ticket block and saves the images linked from the issue under `%s/<N>/`.\n" % (repo, att))


def app_nav_block(cfg):
    mode = cfg["appNavigation"]["mode"]
    skill = cfg["appNavigation"]["skill"]
    if mode == "none":
        return ("No app-navigation skill is connected: when a ticket ends in a context block (the "
                "`Server:` / environment / screen lines a bug report carries), `/todoFromTicket` keeps "
                "those lines as plain sub-bullets of the first dev item. `/todoSetup appNavigation` "
                "connects a skill that opens the app at that screen.\n")
    return ("**App-navigation items.** When a ticket ends in a context block — the `Server:` line and "
            "the lines naming where in the app the bug lives — `/todoFromTicket` writes it as the ticket "
            "block's own first item, before the dev items: the text `/%s` with the spec lines as "
            "sub-bullets. **An item whose text starts with `/%s` is worked by running the `/%s` skill "
            "with its sub-bullets as the spec**: it installs the right build, logs in and lands on the "
            "screen the ticket describes. It has no tag; the ticket's `QA:` items refer to it "
            "(\"on the #N screen\").\n" % (skill, skill, skill))


def code_markers_block(cfg):
    u = "jd"
    if cfg["codeMarkers"] == "off":
        return ("**Code markers — off.** Code changes carry no `[<name>#N]` marker: do not add one, and "
                "leave any existing marker as it is (`/todoReverse` records the item without marking the "
                "code). `/todoMarkCode on` turns the markers back on.\n")
    return ("**Code markers — prompt history.** Every code change implementing todo item `#N` carries the "
            "marker `[<name>#N]` — the file owner's `<name>` plus the id, e.g. `[%s#19]` — "
            "inside a comment at each principal change site, appended to the comment the change already "
            "warrants (never as a bare marker-only comment where none is justified): "
            "`// Pinned to the physical top strip … [%s#16]`. A site shaped by several items "
            "lists them all: `[%s#16 %s#21]`. This is how code is traced back to "
            "the prompt that caused it — `grep -rn \"\\[%s#16\\]\"` finds that user's item 16. "
            "Applies to new work; no retroactive tagging. `/todoMarkCode off` turns the markers off.\n"
            % (u, u, u, u, u))


def prompt_scores_block(cfg):
    if cfg["promptScores"] == "off":
        return ("**Prompt scores — off.** No ` (N/5)` score is written when an item is rewritten; scores "
                "already on item lines stay. `/todoScore on` turns them on.\n")
    return ("**Prompt scores.** Whenever an item is rewritten to its ideal prompt (a confirm word, "
            "`/todoIdealPrompt --replace`, `/todoIdealAll`, `/todoReverse`), the original prompt gets a "
            "score for how close it was to the ideal one, appended to the end of the item line as "
            "` (N/5)` — after the ideal prompt's first line, sub-bullets untouched: "
            "`- [x] #12 PROJ-123 IOS: Rotate the owner label with the device (3/5)`. "
            "5: the original already was the ideal prompt. 4: one small addition. 3: a constraint or "
            "two only surfaced through corrections. 2: the intent was there, most constraints came from "
            "corrections. 1: a bare pointer (\"fix it\"); the result came from the dialog. Discovery no "
            "prompt could have skipped (a real bug hunt) does not lower the score. A rewrite replaces an "
            "existing ` (N/5)`, never adds a second; never on a {{ignoreRows}} row. `/todoIdealPrompt` "
            "prints the score with one clause of why as the first Feedback bullet, with or without "
            "`--replace`. `/todoScore off` turns the scores off.\n".replace("{{ignoreRows}}", ignore_rows(cfg)))


def render(cfg, template):
    words = cfg["confirmWords"]
    subs = {
        "projectTitle": cfg["projectTitle"],
        "userExample": "jd",
        "ticketExample": "PROJ-123",
        "confirmWords": quote_words(words),
        "confirmFirst": words[0],
        "ignoreRows": ignore_rows(cfg),
    }
    out = template
    for k, v in subs.items():
        out = out.replace("{{%s}}" % k, v)
    leftover = re.findall(r"{{\w+}}", out)
    if leftover:
        fail("unknown placeholder(s) in template: %s" % ", ".join(sorted(set(leftover))))
    blocks = {"tags": tags_block, "tracker": tracker_block, "appNavigation": app_nav_block,
              "codeMarkers": code_markers_block, "promptScores": prompt_scores_block}
    for name, fn in blocks.items():
        pat = re.compile(r"<!-- prompt-todo:%s -->\n.*?<!-- /prompt-todo:%s -->" % (name, name), re.S)
        if not pat.search(out):
            fail("template has no <!-- prompt-todo:%s --> block" % name)
        body = fn(cfg)
        out = pat.sub(lambda m: "<!-- prompt-todo:%s -->\n%s<!-- /prompt-todo:%s -->" % (name, body, name), out, count=1)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=os.path.join(FLOW_DIR, "config.json"))
    ap.add_argument("--template", default=os.path.join(FLOW_DIR, "RULES.template.md"))
    ap.add_argument("--out", default=os.path.join(FLOW_DIR, "RULES.md"))
    ap.add_argument("--stdout", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.config)
    if a.check:
        print("[render_rules] config ok: %s" % a.config)
        return
    try:
        with open(a.template, encoding="utf-8") as f:
            template = f.read()
    except FileNotFoundError:
        fail("template not found: %s" % a.template)
    text = render(cfg, template)
    # Bytes / newline="\n": Windows Python would otherwise turn every \n into \r\n (pipes included),
    # and the tree is LF everywhere (.gitattributes, the render snapshots).
    if a.stdout:
        sys.stdout.buffer.write(text.encode("utf-8"))
        return
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("[render_rules] wrote %s" % a.out)


if __name__ == "__main__":
    main()
