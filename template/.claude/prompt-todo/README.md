# Prompt TODO

## 1. Summary

Think of your todo file as:

- a prompt manager and a prompt tracker;
- a learning loop for prompting: each finished item comes back as the prompt you should have
  written, with a `(N/5)` score for the one you did write;
- the layer between the code base and the project-management system (Jira and friends).

### Workspace

| What                | Where                             |
|---------------------|-----------------------------------|
| Your items          | `TODO.<your-git-name>.md`         |
| Archived done items | `TODO.<your-git-name>.archive.md` |

```markdown
# BestPizza — TODO                                  ← TODO.andy.md

- [x] #11 Backend: Fix the crash when the photo list is empty
- [ ] #12 Add a retry button to the upload error dialog
    - optional detail lines, indented
- [ ] #new MobileWeb+: Improve photo list performance
```

### Skills

| Skill                            | What it does                                                                                                                                                                    |
|----------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `/todoFromTicket PROJ-321`       | break a ticket (Jira or other) into 1-5 dev prompts, then 1-5 `QA:` prompts (the manual checks, yours to tick); with the `/appNavigation` skill implemented, a navigation prompt comes first |
| `/todoFromTicket PROJ-321 --deep` | the same, after a read-only subagent has studied the codebase for the ticket's surface, cause and constraints — sharper prompts, same block                                         |
| `/todoIdealPrompt #12 --replace` | rewrite item 12 to the short prompt that would have worked first try, with a `(N/5)` score for the original (`/todoScore on\|off`); `works` / `fixed` run it for you            |
| `/todoIdealPrompt #12 --score`   | score item 12's prompt only: the `(N/5)` goes on the line, your text stays — also while scores are off                                                                          |
| `/todoIdealAll`                  | the same for every item finished in this session                                                                                                                                |
| `/todoReverse [--open]`          | did a prompting in chat with no item? create the item after the fact, markers included; `--open` leaves it unticked for `works`                                                 |
| `/todoArchive`                   | move done items to the archive file                                                                                                                                             |
| `/todoMarkCode on\|off`                   | switch the `[<name>#N]` code markers on or off for the project; existing markers stay                                                                                  |
| `/todoScore on\|off`                      | switch the ` (N/5)` prompt scores on or off for the project; existing scores stay|
| `/todoNumber`                    | give every `#new` its id, start nothing — this runs by itself whenever Claude opens the file; the skill is for when you want the ids now                                        |
| `/todoSetup`                     | the configuration wizard: title and git name, tags, rules check, ticket tracker, app navigation, permissions; every step skippable and re-runnable (`/todoSetup tags`)          |
| `/todoHelp`                      | the one-screen cheat sheet: what to type to work an item, how to finish one, the skills                                                                                         |

Example: `/todoFromTicket PROJ-321` appends this block to your file.

```markdown
## PROJ-321 — Order total wrong after removing a topping

> Remove a topping from a pizza in the cart: the line price updates, the order total does not; a
restart fixes it. Attachments: todoAttachments/PROJ-321/cart.png

- [ ] #32 PROJ-321 /appNavigation
    - Server: stage
    - Account: qa.tester@bestpizza.test
    - Screen: Cart
    - Order: Large Margherita + extra cheese + olives
- [ ] #33 PROJ-321 Android+: Recompute the order total whenever a topping is removed from a cart
  item.
- [ ] #34 PROJ-321 Android+: Recompute the delivery fee when the order drops below the free-delivery
  threshold.
- [ ] #35 PROJ-321 Keep the total correct after the cart is restored from disk.
- [ ] #36 PROJ-321 QA: on the #32 screen, remove olives: the line price and the order total drop by
  the same amount
- [ ] #37 PROJ-321 QA: on the #32 screen, remove extra cheese so the order goes under 20 €: the
  delivery fee reappears in the total
- [ ] #38 PROJ-321 QA: remove a topping, kill the app, reopen the cart: the total matches the line
  prices
```

### Markers in code

Every change made for an item carries `[<name>#N]` in a comment at the change site — the
comment the change deserves anyway, never one that exists only to hold the marker:

```kotlin
// Retry re-enqueues the same upload id, see UploadQueue. [jd#12]

// The total is recomputed from the toppings left, not decremented. [jd#33]
```

`grep -rn "\[jd#33\]"` leads from the code to item 33, and the item carries the ticket key, so
the ticket is one hop away. Several items on one spot: `[jd#12 jd#15]`.

A project that does not want the trace in its code runs `/todoMarkCode off`: from then on
changes carry no marker and `/todoReverse` records items without marking code. Markers already
written stay, and `/todoMarkCode on` starts them again — new work only, nothing retroactive.

## 2. Your file

One file per person, at the repo root, named after your git user name:

```
git config user.name jd        # → TODO.jd.md
```

You only touch your own file. Claude never reads anyone else's. Ids are per file, so `#12` in
`TODO.jd.md` and `#12` in `TODO.al.md` are unrelated.

## 3. Format

```markdown
# TODO

- [ ] #12 Add a retry button to the upload error dialog
    - optional detail lines, indented
- [x] #11 Fix the crash when the photo list is empty
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

## 4. Tags and tickets

```markdown
- [ ] #13 IOS: Status bar overlaps the camera preview
- [ ] #14 PROJ-321 Android+: Sync stalls after login
- [ ] #15 QA: Test release 2.4 on the tablet
```

| Tag                                    | Meaning                                                                            |
|----------------------------------------|------------------------------------------------------------------------------------|
| `Android:` / `IOS:`                    | one mobile app only                                                                |
| `Web:` / `MobileWeb:`                  | the web frontend in a desktop browser / in a phone browser                         |
| `Backend:`                             | backend / API only                                                                 |
| `Desktop:`                             | the desktop app (macOS / Windows / Linux)                                          |
| `Android+:` `IOS+:` `Web+:` …          | seen on one platform, almost certainly elsewhere too: fix all, verify that one first |
| `Chrome:` `Safari:` `Firefox:` `Edge:` | the web frontend in that browser only                                              |
| `Docs:` / `Infra:`                     | documentation only / build, CI, tooling                                            |
| `QA:` / `Admin:`                       | your own row — Claude never works, edits or ticks it                               |

One tag per item, right after the id (or after the ticket key). Tags exist to tell platforms
apart inside one repo, so `/todoSetup tags` looks at the repo (Gradle, Xcode, `package.json`,
Maven, CMake …) and keeps only the rows that apply: an Android-only app gets `Android:`,
`Docs:`, `Infra:`; the `+` rows appear only when two or more platforms are found, the browser
rows only with a web frontend. There is no `All:` tag and no default: an item without a tag is
simply about this project. `/todoSetup tags add|remove` changes a row by hand.

A ticket key goes right after the id. It is the durable link: it survives the rewrite and the
archive, and `grep PROJ-321` finds the ticket's items in both files.

## 5. From a ticket

```
/todoFromTicket PROJ-321                                            the key
/todoFromTicket https://yourcompany.atlassian.net/browse/PROJ-321   or its URL
/todoFromTicket PROJ-321 --no-attachments                           skip the attachment download
/todoFromTicket PROJ-321 --deep                                     study the codebase first, then draft
```

Claude fetches the ticket (Jira through the Atlassian MCP server, GitHub Issues through `gh`;
`/todoSetup tracker` connects one — or paste the ticket text after the key), saves its
attachments under `todoAttachments/PROJ-321/`,
and appends a ticket block to your file — draft first prompts, nothing started (the block in
section 1 is what it looks like):

- The heading and the `> ` excerpt are for reading; they are not items. `/todoArchive` drops
  the heading once every item under it is gone.
- The **`/appNavigation` item** comes first when the ticket says where in the app the bug
  lives. Its text is just `/appNavigation`, and the ticket's lines are its sub-bullets. Typing
  its `#N` opens the app at that screen on a device; how it gets there is the app's business
  and lives in that skill. The `QA:` items say "on the #32 screen" instead of repeating the
  place.
- Each **dev item** is one deliverable in your own words, tagged only when the ticket names a
  platform.
- The **`QA:` items** come after the dev items: 1-5 rows, one manual check each — what you do
  on the device and what you must see — covering the ticket as a whole, not one per dev item.
  They are your rows: Claude never works or ticks them, you tick them once a check passes.
- A ticket that is one task gets one item. Nothing is invented beyond the ticket.
- `--deep`: a read-only subagent studies the codebase first; the prompts name the real surface
  and split where the code splits. The file gets the same block, only better prompts.

The whole skill, step by step: `docs/todo-from-ticket.md` in the prompt-todo repository.

Then it is the ordinary flow:

```
#32                          open the app at the ticket's screen
#33                          work the first dev item
works                        tick #33, rewrite #33 to its ideal prompt
#36                          yours: run the check on the device, tick the row by hand
/todoFromTicket PROJ-321     later, after the ticket changed: only items that are not there yet are added
```

## 6. Working an item

```
#12                          work item 12
#12 only on the iOS side     work it, with an addendum
#newCam                      number it, then work it
- [ ] #12 Add a retry…       the whole line pasted works too
- [ ] Add a retry button     no id: appended as the next id, then worked
```

Not ready to start? Hold it and feed it first:

```
#12 #wait                    Claude: "Holding #12 — #go to start"
<logs file>                  the capture attaches to #12
the button should be red     so does plain text
#go                          start with all of it
```

Confirm the result:

```
works                        tick the item just worked and rewrite it to its ideal prompt
fixed                        same
works #12                    the same, naming the item — no guessing when several were touched
ok / looks good              tick only
```

The exact confirm words (`works`, `fixed`, `works, fixed` by default; `config.json`
`confirmWords`), with or without a ` #N` after them, are also caught by a hook, so the rewrite
never depends on Claude remembering the rule.

The rewrite also scores the original prompt: ` (3/5)` at the end of the item line, 5 when your
first prompt already was the ideal one, 1 when the result came from the corrections. Watch the
numbers climb; `/todoScore off` drops them. To keep your own wording and still see the number,
`/todoIdealPrompt #12 --score` writes just the score — with the scores on or off.

The rewrite never leaves you a 300-character line: every line Claude writes to the file stays
within `maxLineLength` characters (`config.json`, 120 by default, 0 for no limit), prefix and
score included — a longer prompt continues as `  - ` sub-bullets, split at a clause boundary.
Your own lines are never re-wrapped. After changing the value, re-render the rules with
`bash .claude/prompt-todo/bin/py.sh render_rules.py`.

## 7. Where things live

| What                       | Where                                                    |
|----------------------------|----------------------------------------------------------|
| Your items                 | `TODO.<name>.md`                                         |
| Archived done items        | `TODO.<name>.archive.md`                                 |
| The rules Claude executes  | `.claude/prompt-todo/RULES.md` (generated; imported by `CLAUDE.md`) |
| The configuration          | `.claude/prompt-todo/config.json` (edit with `/todoSetup`; `maxLineLength` by hand, then re-render) |
| The skills                 | `.claude/skills/todo*`, `.claude/skills/appNavigation`   |
| The `works` / `fixed` hook | `.claude/hooks/todo-confirm.sh`, `.claude/settings.json` |
| Ticket attachments         | `todoAttachments/<KEY>/` (gitignored)                    |

`.claude/prompt-todo/RULES.md` holds the exact rules Claude follows, generated from
`config.json`; this file explains them for people. When the two disagree, the rules file wins.
Commit `config.json`, the skills, the hook and `RULES.md` with the project so the whole team
shares one flow; only `credentials.json` and the attachments directory stay out of git.
