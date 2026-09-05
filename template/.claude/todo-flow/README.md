# Todo-driven development

Think of your todo file as a prompt manager and a prompt tracker. It sits between the code base
on one side and the project-management system (Jira, GitHub Issues) on the other, and every
piece of work enters through it.

Every task starts as a numbered line in it, the back-and-forth happens in the chat, and when
you confirm the result Claude rewrites the line into the prompt that would have got there in
one go. Over time the file is three things: your task list, your prompt-writing training log,
and the link between a ticket and the code that closed it.

`.claude/todo-flow/RULES.md` holds the exact rules Claude follows (generated from
`config.json`, imported by your `CLAUDE.md`). This file explains them for people; when the two
disagree, the rules file wins.

The examples below use a sample app, **BestPizza** — a pizza-ordering app with a web
frontend, an Android app and an iOS app, whose screens go Restaurant → Pizza → Topping.

## 1. Your file

One file per person, at the repo root, named after your git user name:

```
git config user.name jd        # → TODO.jd.md
```

You only touch your own file. Claude never reads anyone else's. Ids are per file, so `#12` in
`TODO.jd.md` and `#12` in `TODO.al.md` are unrelated.

## 2. Format

```markdown
# BestPizza — TODO

- [ ] #12 Add a retry button to the order-failed dialog
  - optional detail lines, indented
- [x] #11 Fix the crash when the topping list is empty
- [ ] #new Something I just thought of
- [ ] #newCam A camera idea I want to refer to by name
- [ ] A line with no id at all — also counts as #new
```

- `- [ ]` is open, `- [x]` is done, `#N` is the id.
- No id yet? Write `#new`, or `#newName` so you can refer to it. Claude numbers it the next
  time it opens the file: highest id in the file and its archive, plus one. Ids are never
  renumbered or reused.
- Done items are never deleted. When the file gets long, `/todoArchive` moves them to
  `TODO.jd.archive.md`.

## 3. Tags and tickets

```markdown
- [ ] #13 IOS: Status bar overlaps the pizza photo
- [ ] #14 PROJ-321 Android+: Order total wrong after removing a topping
- [ ] #15 QA: Test release 2.4 on the tablet
```

The tag table is yours: `/todoSetup tags` starts from a default set and lets you trim or
extend it. The defaults:

| Tag                        | Meaning                                                    |
|----------------------------|------------------------------------------------------------|
| `Android:` / `IOS:`        | one mobile app only                                        |
| `Web:` / `MobileWeb:`      | the web frontend in a desktop browser / in a phone browser |
| `Backend:`                 | backend / API only                                         |
| `Desktop:`                 | the desktop app (macOS / Windows / Linux)                  |
| `All:`                     | every platform — the default when there is no tag          |
| `IOS+:` / `Android+:`      | seen on one platform, fix all, verify that one first       |
| `Docs:` / `Infra:`         | documentation only / build, CI, tooling                    |
| `QA:` / `Admin:`           | your own row — Claude never works, edits or ticks it       |
