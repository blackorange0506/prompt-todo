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
| `Android:` / `IOS:`        | one mobile platform only                                   |
| `Frontend:` / `Backend:`   | one side of the web stack only                             |
| `All:`                     | every platform — the default when there is no tag          |
| `IOS+:` / `Android+:`      | seen on one platform, fix all, verify that one first       |
| `Bug:` `Feature:` `Refactor:` `Docs:` `Infra:` | the kind of change, when that matters more than the platform |
| `QA:` / `Admin:`           | your own row — Claude never works, edits or ticks it       |

A ticket key goes right after the id. It is the durable link: it survives the rewrite and the
archive, and `grep PROJ-321` finds the ticket's items in both files.

## 3a. From a ticket

```
/todoFromTicket PROJ-321                                             the key
/todoFromTicket https://yourcompany.atlassian.net/browse/PROJ-321    or its URL
/todoFromTicket 42                                                   a GitHub issue
/todoFromTicket PROJ-321 --no-attachments                            skip the attachment download
```

Claude fetches the ticket (Jira through the Atlassian MCP server, GitHub Issues through `gh`;
`/todoSetup tracker` connects one — or paste the ticket text after the key), saves its
attachments under `todoAttachments/PROJ-321/`, and appends a ticket block to your file — draft
first prompts, nothing started:

```markdown
## PROJ-321 — Order total wrong after removing a topping
> Add a Margherita, add olives, remove olives: the total still includes the topping. Attachments: todoAttachments/PROJ-321/order.log
- [ ] #32 PROJ-321 /appNavigation
  - Server: stage
  - Restaurant: Downtown
  - Pizza: Margherita
  - Topping: Olives
- [ ] #33 PROJ-321 Android+: Recompute the order total from the current toppings whenever one is removed.
  - [ ] QA: on the #32 screen, add olives, remove them: the total goes back to the pizza price
- [ ] #34 PROJ-321 Show the topping's price next to its remove button so a wrong total is visible at once.
  - [ ] QA: on the #32 screen, add olives: the olives row shows its price, the total is pizza + that price
```

- The heading and the `> ` excerpt are for reading; they are not items. `/todoArchive` drops the
  heading once every item under it is gone.
- The **`/appNavigation` item** comes first when the ticket says where in the app the bug
  lives — and only when an app-navigation skill is connected (`/todoSetup appNavigation`;
  optional). Its text is just the skill's name, and the ticket's lines are its sub-bullets.
  Typing its `#N` runs that skill, which opens the app at that screen on a device; what it
  does to get there is the app's business and lives in its own skill, not here. It has no
  `QA:` sub-check of its own, and the dev items' checks say "on the #32 screen" instead of
  repeating the place. Without such a skill the lines stay as plain sub-bullets of the first
  dev item.
- Each **dev item** is one deliverable in your own words, tagged only when the ticket names a
  platform, with one `QA:` sub-check: the thing you do on the device to see that item is done.
- A ticket that is one task gets one item. Nothing is invented beyond the ticket.

Then it is the ordinary flow:

```
#32                          open the app at the ticket's screen
#33                          work the first dev item
works                        tick #33 and its QA: sub-check, rewrite #33 to its ideal prompt
/todoFromTicket PROJ-321     later, after the ticket changed: only items that are not there yet are added
```

## 4. Working an item

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
/screenshot                  any skill you call now attaches its result to #12
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

## 5. Markers in code

Every change made for `#12` carries `[<name>#12]` in a comment at the change site:

```kotlin
// Retry re-enqueues the same order id, see OrderQueue. [jd#12]
```

```python
# The total is recomputed from the toppings left, not decremented. [jd#33]
```

```
grep -rn "\[jd#12\]" src     # finds the code behind item 12
```

Several items on one spot: `[jd#12 jd#15]`. The marker joins a comment the change deserves
anyway, never a comment that exists only to hold it.

## 6. Skills

| Skill                              | What it does                                                                                   |
|------------------------------------|------------------------------------------------------------------------------------------------|
| `/todoSetup`                       | the configuration wizard: title and git name, tags, rules, tracker, app navigation, permissions; every step skippable and re-runnable (`/todoSetup tags`) |
| `/todoIdealPrompt #12 --replace`   | rewrite item 12 to the short prompt that would have worked first try, with feedback on the original. `works` / `fixed` run it for you |
| `/todoIdealize`                    | the same for every item finished in this session                                               |
| `/todoNumber`                      | give every `#new` its id, start nothing                                                        |
| `/todoFromTicket PROJ-321`         | draft items from a ticket, each with its `QA:` sub-check; an app-navigation item first when the ticket says where in the app the bug lives and a navigation skill is connected (section 3a) |
| `/appNavigation PROJ-321`          | open the app on a device at the ticket's screen — a carcass you fill for your app, see `.claude/skills/appNavigation/README.md` |
| `/todoReverse [--open]`            | did a hotfix in chat with no item? create the item after the fact, markers included. `--open` leaves it unticked for `works` |
| `/todoArchive`                     | move done items to the archive file                                                            |

## 7. Where things live

| What                       | Where                                                    |
|----------------------------|----------------------------------------------------------|
| Your items                 | `TODO.<name>.md`                                         |
| Archived done items        | `TODO.<name>.archive.md`                                 |
| The rules Claude executes  | `.claude/todo-flow/RULES.md` (generated; imported by `CLAUDE.md`) |
| The configuration          | `.claude/todo-flow/config.json` (edit with `/todoSetup`) |
| The skills                 | `.claude/skills/todo*`, `.claude/skills/appNavigation`   |
| The `works` / `fixed` hook | `.claude/hooks/todo-confirm.sh`, `.claude/settings.json` |
| Ticket attachments         | `todoAttachments/<KEY>/` (gitignored)                    |

Commit `config.json`, the skills, the hook and `RULES.md` with the project so the whole team
shares one flow; only `credentials.json` and the attachments directory stay out of git.
