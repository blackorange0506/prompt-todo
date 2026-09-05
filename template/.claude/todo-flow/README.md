# Smart TODO

## 1. Summary

Think of your todo file as:

- a prompt manager and a prompt tracker;
- a learning loop for prompting: each finished item comes back as the prompt you should have
  written;
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

| Skill                            | What it does                                                                                                                                         |
|----------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| `/todoSetup`                     | the configuration wizard: title and git name, tags, rules check, ticket tracker, app navigation, permissions; every step skippable and re-runnable (`/todoSetup tags`) |
| `/todoIdealPrompt #12 --replace` | rewrite item 12 to the short prompt that would have worked first try, with feedback on the original; `works` / `fixed` run it for you                |
| `/todoIdealize`                  | the same for every item finished in this session                                                                                                     |
| `/todoNumber`                    | give every `#new` its id, start nothing                                                                                                              |
| `/todoFromTicket PROJ-321`       | break a ticket (Jira or other) into 1-5 dev prompts, each with its QA sub-check; with the `/appNavigation` skill implemented, a navigation prompt comes first |
| `/appNavigation PROJ-321`        | open the app on a device at the screen the ticket describes — app-specific, lives in its own skill (formerly `/openApp`)                            |
| `/todoReverse [--open]`          | did a prompting in chat with no item? create the item after the fact, markers included; `--open` leaves it unticked for `works`                      |
| `/todoArchive`                   | move done items to the archive file                                                                                                                  |

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
    - [ ] QA: on the #32 screen, remove olives: the line price and the order total drop by the same
      amount
- [ ] #34 PROJ-321 Android+: Recompute the delivery fee when the order drops below the free-delivery
  threshold.
    - [ ] QA: on the #32 screen, remove extra cheese so the order goes under 20 €: the delivery fee
      reappears in the total
- [ ] #35 PROJ-321 All: Keep the total correct after the cart is restored from disk.
    - [ ] QA: remove a topping, kill the app, reopen the cart: the total matches the line prices
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

| Tag                                        | Meaning                                                                            |
|--------------------------------------------|------------------------------------------------------------------------------------|
| `Android:` / `IOS:`                        | one mobile app only                                                                |
| `Web:` / `MobileWeb:`                      | the web frontend in a desktop browser / in a phone browser                         |
| `Backend:`                                 | backend / API only                                                                 |
| `Desktop:`                                 | the desktop app (macOS / Windows / Linux)                                          |
| `All:`                                     | every platform — the default when there is no tag                                  |
| `IOS+:` / `Android+:`                      | seen on one platform, fix all, verify that one first                               |
| `Web+:` / `MobileWeb+:`                    | seen in one browser, fix both web fronts, verify that one first                    |
| `Chrome:` `Safari:` `Firefox:` `Edge:`     | the web frontend in that browser only                                              |
| `Chrome+:` `Safari+:` `Firefox+:` `Edge+:` | seen in that browser, almost certainly in the others too: fix all, verify it first |
| `Docs:` / `Infra:`                         | documentation only / build, CI, tooling                                            |
| `QA:` / `Admin:`                           | your own row — Claude never works, edits or ticks it                               |

One tag per item, right after the id (or after the ticket key). The table is a default: trim
it or add your own rows per project.

A ticket key goes right after the id. It is the durable link: it survives the rewrite and the
archive, and `grep PROJ-321` finds the ticket's items in both files.

## 5. From a ticket

```
/todoFromTicket PROJ-321                                            the key
/todoFromTicket https://yourcompany.atlassian.net/browse/PROJ-321   or its URL
/todoFromTicket PROJ-321 --no-attachments                           skip the attachment download
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
  and lives in that skill. It has no `QA:` sub-check of its own; the dev items' checks say
  "on the #32 screen" instead of repeating the place.
- Each **dev item** is one deliverable in your own words, tagged only when the ticket names a
  platform, with one `QA:` sub-check: the thing you do on the device to see that item is done.
  The confirm word ticks the item and its check together.
- A ticket that is one task gets one item. Nothing is invented beyond the ticket.

Then it is the ordinary flow:

```
#32                          open the app at the ticket's screen
#33                          work the first dev item
works                        tick #33 and its QA: sub-check, rewrite #33 to its ideal prompt
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

`.claude/todo-flow/RULES.md` holds the exact rules Claude follows, generated from
`config.json`; this file explains them for people. When the two disagree, the rules file wins.
Commit `config.json`, the skills, the hook and `RULES.md` with the project so the whole team
shares one flow; only `credentials.json` and the attachments directory stay out of git.
