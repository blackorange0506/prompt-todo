# From a ticket to prompts: `/todoFromTicket`

`/todoFromTicket` is the bridge from the project-management side to your todo file: one ticket
becomes a **ticket block** of draft first prompts — numbered, keyed with the ticket, ready to
edit and then work one by one with `#N`. It writes prompts and nothing else; no work is
started. `/todoReverse` is its counterpart in the other direction, and `/todoFromJira` is the
old name, still accepted.

## What you type

```
/todoFromTicket PROJ-321                                            a Jira key
/todoFromTicket https://yourcompany.atlassian.net/browse/PROJ-321   or its URL
/todoFromTicket 42                                                  a GitHub issue number
/todoFromTicket https://github.com/owner/repo/issues/42             or its URL
/todoFromTicket PROJ-321 --no-attachments                           skip the attachment download
/todoFromTicket PROJ-321 --deep                                     study the codebase first, then draft
/todoFromTicket PROJ-321                                            paste mode: the ticket text
<title, description, acceptance criteria …>                          follows on the next lines
```

A key is required; there is no free-form mode. Which backend reads the ticket is
`tracker.kind` in `.claude/prompt-todo/config.json` (`/todoSetup tracker` sets it):

| `tracker.kind` | Reads the ticket with                                    | Without it                           |
|----------------|-----------------------------------------------------------|--------------------------------------|
| `jira`         | the Atlassian MCP server (`/mcp` to log in)               | paste mode still works               |
| `github`       | `gh issue view` on `tracker.github.repo`                  | paste mode still works               |
| `none`         | nothing — paste the ticket text after the key             | stops and says how to connect one    |

[docs/jira-mcp.md](jira-mcp.md) covers connecting either tracker.

## What Claude does

1. **Resolves the key** — `PROJ-321`, an issue number, or the key taken from a URL.
2. **Fetches the ticket**: summary, description, type, labels, status, attachment list. If the
   fetch fails it reports the error and writes nothing (or offers paste mode).
3. **Downloads the attachments** to `<attachmentsDir>/<KEY>/<original-filename>` (default
   `todoAttachments/PROJ-321/`, gitignored; a name collision gets a `(2)`, `(3)` suffix). Images
   and logs are read when they change what the prompts should say. `--no-attachments` and
   paste mode skip this step.
4. **With `--deep`, studies the codebase first**: a read-only subagent gets the ticket and
   reports where the surface lives, the likely cause or touch points, the constraints the
   code imposes and the natural split of the work; the prompts are then drafted from that
   report. The block in the file is the same — only the prompts are sharper. Without a
   codebase at hand it says so and drafts as usual.
5. **Opens your todo file** — `TODO.<git user.name>.md` — and runs the usual `#new` numbering
   pass first, as on any touch.
6. **Drafts the block** (below) and appends it at the end of the file.
7. **Replies** with the block, the attachment paths, and one line saying nothing was started;
   with `--deep`, a few lines first on what the analysis found.

## The ticket block

```markdown
## PROJ-321 — Order total wrong after removing a topping
> Add a Margherita, add olives, remove olives: the total still includes the topping. Attachments: todoAttachments/PROJ-321/order.log
- [ ] #32 PROJ-321 /appNavigation
  - Server: stage
  - Restaurant: Downtown
  - Pizza: Margherita
  - Topping: Olives
- [ ] #33 PROJ-321 Android+: Recompute the order total from the current toppings whenever one is removed.
- [ ] #34 PROJ-321 Show the topping's price next to its remove button so a wrong total is visible at once.
- [ ] #35 PROJ-321 QA: on the #32 screen, add olives, remove them: the total goes back to the pizza price
- [ ] #36 PROJ-321 QA: on the #32 screen, add olives: the olives row shows its price, the total is pizza + that price
```

Top to bottom:

- **The heading and the `> ` excerpt** are for reading. They are not items, and `/todoArchive`
  drops the heading once every item under it is gone. The ticket key on each item is the
  durable link: `grep PROJ-321` finds the ticket's prompts in the todo file and in the archive.
- **The `/appNavigation` item** (`#32`) exists only when the ticket ends in a context block —
  `Server:` / `Environment:`, `App version:`, and lines naming where in the app the bug lives —
  *and* an app-navigation skill is connected (`appNavigation.mode = existing`). Its text is the
  skill's name, the locator lines are its sub-bullets, copied as written. Typing `#32` opens the
  app there; see [docs/app-navigation.md](app-navigation.md). Without a connected skill the
  locator lines stay as plain sub-bullets of the first dev item, so nothing from the ticket is
  lost. A ticket without such a block never gets this item — no spec is invented from prose.
- **The dev items** (`#33`, `#34`): 1–5 of them, each the *first prompt* for one piece of work
  in your own style — imperative, one or two lines, naming the surface the way you would, one
  deliverable per item. A tag (`IOS:`, `Android+:` …) only when the ticket names the platform.
  A sub-bullet only for a constraint the ticket states. A ticket that is one task gets one
  item; nothing beyond the ticket is invented. With `--deep` the items name the real surface,
  the split follows the code, and a constraint found in the code may be a sub-bullet — the
  scope is still the ticket's.
- **The QA items** (`#35`, `#36`): after the dev items, 1–5 top-level `QA:` rows — the manual
  checks for the ticket: which screen, what to do, what must be seen, derived from the
  acceptance criteria or, failing those, from the dev items. Their number is independent of the
  dev count — fewer, more, or the same, whatever the ticket needs; there is no one-to-one rule.
  They are your rows in the sense of the tag table: Claude never works, rewrites or ticks them;
  you tick one once the check passes. A ticket whose status is already done gets no QA items,
  and Claude says so.

The ids run in that order — navigation, dev, QA — from the next free id in the file and its
archive. For a GitHub issue the key is written `GH-42` (heading `## GH-42 — <title>`), so it
never collides with the `#N` item ids.

## Then

```
#32            open the app at the ticket's screen
#33            work the first dev item
works          tick #33 and rewrite it to its ideal prompt
#35            yours: run the check on the device, tick the row by hand
```

## Running it again

`/todoFromTicket PROJ-321` on a ticket that already has a `## PROJ-321` heading appends only
the items that are not there yet, comparing intent rather than wording, and says which were
skipped as duplicates. Ids already given are never renumbered or reused.

## What it never does

- Never starts work, ticks, rewrites or archives anything.
- Never touches another user's `TODO.*.md`.
- Never writes when the fetch failed.
- Never invents scope, a navigation spec, or a platform tag the ticket does not contain.
- Never writes the `--deep` analysis, or the word deep, into the file — only the prompts.
