---
name: todoFromTicket
description: "Turn one ticket into draft prompt items in the user's todo file (TODO.<git user.name>.md, resolved as in the todo rules): fetch the ticket from the configured tracker (Jira via the Atlassian MCP server, GitHub Issues via gh, or the ticket text pasted after the key), download its attachments to <attachmentsDir>/<KEY>/, then append a `## KEY — summary` ticket block with 1–5 numbered dev items, each carrying the ticket key right after its id (`- [ ] #32 PROJ-123 prompt`), then 1–5 `QA:` items (`- [ ] #36 PROJ-123 QA: check …`) — the manual checks for the ticket, the user's own rows that Claude never works or ticks; their number does not follow the dev count. When the ticket ends in a context block (Server / App version / where-in-the-app lines) and an app-navigation skill is connected, that block becomes the ticket block's own first item. Starts no work. Also answers to the old name /todoFromJira. Use whenever the user wants a ticket turned into todo prompts — phrases like '/todoFromTicket PROJ-123', '/todoFromTicket <ticket-url>', '/todoFromTicket 42' (a GitHub issue), '/todoFromJira PROJ-123', 'make prompts from PROJ-123', 'add PROJ-123 to my todo', 'todo from ticket', 'draft prompts for this ticket'. This skill IS allowed to edit the user's todo file; that is its purpose."
argument-hint: "<KEY | issue-number | url> [--no-attachments] [pasted ticket text]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git config:*), Bash(gh:*), Bash(curl:*), Bash(mkdir:*), Bash(bash .claude/prompt-todo/bin/py.sh:*), Bash(jq:*), mcp__atlassian__getJiraIssue, mcp__atlassian__fetch, mcp__atlassian__search
---

# /todoFromTicket

The bridge from the project-management side to the todo file: one ticket becomes a ticket
block of draft first-prompts, numbered and keyed, ready for the user to edit and then work one
by one with `#N`. The output is prompts, nothing else — no work is started. The counterpart of
`/todoReverse`. `/todoFromJira` is the old name and still triggers it.

## Configuration

Read once per run from `.claude/prompt-todo/config.json`:

| key                    | use                                                                 |
|------------------------|---------------------------------------------------------------------|
| `tracker.kind`         | `jira`, `github` or `none` — selects the backend below              |
| `tracker.jira.host`    | accepted in ticket URLs; `projectKeys` are the keys recognised bare  |
| `tracker.github.repo`  | `owner/repo` for `gh issue view`                                    |
| `attachmentsDir`       | where attachments go: `<attachmentsDir>/<KEY>/<filename>`           |
| `appNavigation.mode`   | `existing` → the context block becomes a `/<skill>` item (step 5)   |
| `appNavigation.skill`  | the skill's name                                                     |

## Argument forms

```
/todoFromTicket PROJ-123                                          # Jira key
/todoFromTicket https://yourcompany.atlassian.net/browse/PROJ-123 # Jira URL
/todoFromTicket 42                                                # GitHub issue number
/todoFromTicket https://github.com/owner/repo/issues/42           # GitHub issue URL
/todoFromTicket PROJ-123 --no-attachments                         # skip the download
/todoFromTicket PROJ-123                                          # paste mode: the ticket text
<pasted title, description, acceptance criteria …>                #   follows on the next lines
```

## What Claude does

1. **Resolve the ticket key** — a Jira key `[A-Z][A-Z0-9]+-\d+`, a GitHub issue number, or
   the key/number taken from a URL (`/browse/KEY`, `/issues/N`). No key → say so and stop;
   this skill has no free-form mode without a key.

2. **Fetch the ticket** with the backend `tracker.kind` selects:
   - **`jira`** — `mcp__atlassian__getJiraIssue` (`contentFormat: "markdown"`): summary,
     description, issue type, labels/components, status, and the attachment list. If the MCP
     server is not connected, say so and point to `/mcp` (login) or `/todoSetup tracker`.
   - **`github`** — `gh issue view <N> --repo <tracker.github.repo> --json number,title,body,labels,state,comments`.
     If `gh` is missing or not logged in (`gh auth status`), say so and point to
     `/todoSetup tracker`.
   - **`none`** — no fetch. If ticket text was pasted after the key, use it as the ticket
     (**paste mode**, also available with the other backends when the fetch fails). Otherwise
     stop with: "no ticket tracker is configured — run `/todoSetup tracker`, or paste the
     ticket text after the key."

3. **Download attachments** (unless `--no-attachments` or paste mode) to
   `<attachmentsDir>/<KEY>/<original-filename>` (suffix `(2)`, `(3)`, … on collision): Jira
   attachments via `mcp__atlassian__fetch` on each `content` URL; for GitHub, the image and
   file links in the issue body and comments via `curl -L`. Create the directory. Read image
   and log attachments if they change what the prompts should say.

4. **Resolve the user's todo file** — `TODO.<name>.md`, `<name>` from `git config user.name`
   (the rule in `.claude/prompt-todo/RULES.md`). Run Autoincrement first, as on any touch. Edit
   tool only.

5. **Draft the prompts.** From the description and attachments, write 1–5 items, each the
   *first prompt* for one piece of work, in the user's style: imperative, short (one or two
   lines), naming the surface the way the user would ("the checkout button on iOS", not a
   class name), one deliverable per item. Add a tag from the rules' tag table only when the
   ticket says so (`IOS:`, `Android:`, `Web:` …; unspecified → no tag). A sub-bullet only
   for a constraint the ticket states explicitly. Do not invent scope the ticket does not
   contain; a ticket that is one task gets one item.

   **The context block.** Many bug templates end in a block of locator lines — `Server:` (or
   `Environment:`), `App version:`, and lines naming where in the app the bug lives (for the
   sample BestPizza app: `Restaurant:`, `Pizza:`, `Topping:`; for yours, whatever its screens
   are called). What happens to it depends on `appNavigation.mode`:
   - **`existing`** — the block gets one extra item **before** the dev items, taking the
     block's first id: the text `/<appNavigation.skill>`, and the locator lines as its
     sub-bullets, one per line, values as the ticket wrote them:

     ```markdown
     - [ ] #42 PROJ-321 /appNavigation
       - Server: stage
       - Restaurant: Downtown
       - Pizza: Margherita
       - Topping: Olives
     ```

     Typing its `#N` runs that skill with the sub-bullets as the spec, copied as written (see the
     **App-navigation items** paragraph of the rules). It carries no tag; the QA items say
     "on the #42 screen" instead of repeating the place. A ticket without such a block gets no
     such item — never invent a spec from prose.
   - **`none`** — no extra item: the locator lines stay as plain `  - ` sub-bullets of the
     first dev item, so nothing from the ticket is lost, and the QA items name the screen
     themselves.

   **Then the QA items** — after the dev items, 1–5 top-level items `- [ ] #N KEY QA: <check>`,
   each one verification the user performs by hand — which screen, what to do, what must be
   seen. Derived from the ticket's acceptance criteria or, failing those, from the dev items.
   Their number is independent of the dev count — **no one-to-one rule**: fewer, more, or the
   same, whatever the ticket needs (a one-line ticket may get one QA item; never more than
   five). They are `QA:` rows in the sense of the rules' tag table: Claude never works,
   rewrites or ticks them; the user ticks them once the check passes. Write them complete
   the first time. Skip them for a ticket whose status is already done, and say so.

6. **Write the ticket block** at the end of the todo file (Ids rule for the numbers):

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

   The ids run in that order: the app-navigation item, the dev items, the QA items. The `#32`
   item exists only with `appNavigation.mode = existing` and a context block in the ticket;
   without one the block starts at the first dev item. For a GitHub issue the key is
   `#<number>`-free: write it as `GH-42` on the items and `## GH-42 — <title>` on the heading,
   so it never collides with the item ids.

   If a `## KEY` heading already exists, append only items that are not already there
   (compare intent, not wording) under that heading, and say which were skipped as duplicates.

7. **Reply**: the heading line, the app-navigation item first when there is one, each dev item
   with its id, then the QA items with theirs, the attachment paths, and one line saying
   nothing was started — the user works a dev item by typing its `#N`, closes it with a
   confirm word (`works` / `fixed`), and ticks the QA rows by hand once they pass.

## Notes

- The ticket key on every item is the durable link (grep `PROJ-321` finds a ticket's prompts in
  the todo file *and* the archive); the heading is only for reading. Both formats are defined
  in the todo rules, **Ticket blocks**.
- Never ticks, rewrites or archives anything; never touches other users' files.
- If the fetch fails, report the error and write nothing (or offer paste mode).
