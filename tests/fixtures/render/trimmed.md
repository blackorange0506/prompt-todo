# Todo workflow

<!-- Generated from .claude/prompt-todo/config.json by .claude/prompt-todo/bin/render_rules.py.
     Do not edit by hand: change the config and re-run `/todoSetup rules`
     (or `python3 .claude/prompt-todo/bin/render_rules.py`). Rules that are specific to your
     project belong in your own CLAUDE.md, next to the line that imports this file. -->

The human explanation of this flow is `.claude/prompt-todo/README.md`; this file is the
executable version — the rules Claude follows. If the two disagree, this file wins and the
readme needs fixing.

**The user's todo file.** Each person has their own file, `TODO.<name>.md` at the repo root,
where `<name>` is the output of `git config user.name` (e.g. `jd` →
`TODO.jd.md`). Resolve it once per session. If the file does not exist, say so
and ask before creating it (template: the `# BestPizza — TODO` header, nothing else).
Other people's `TODO.*.md` files are never read, edited or worked — they are on the same
footing as personal (ignored) rows below. Every edit to the todo file goes through the Edit tool,
never the shell (the IDE only reloads tabs it is told about). "The todo file" everywhere below
means the current user's file.

A prompt is a todo work item — treat it as a task, not as markdown to discuss — when its
trimmed text matches either form (be tolerant of whitespace differences around the markers):

- `- [ ] #N …` or `- [x] #N …` — the item pasted whole (also accept sloppy spacing like
  `-[ ]#16` or `- [x]  #16`);
- a bare id: `#N` alone, or `#N` followed by extra words — look the item up in the todo file
  by its id and work on that item (the extra words are addenda to it);
- `#new` or `#new<suffix>` — a new item the user typed into the todo file with that placeholder
  instead of an id (see **Autoincrement** below). Ids are assigned first; then the token names
  the item. Extra words after it are addenda, as with `#N`.

In all cases `#N` is the item's id and the item's text is the task. Investigate/implement it.
- When the user confirms the result works, mark exactly that item `[x]` in the todo file (find
  it by `#N`). Never renumber or reuse ids.
- **Trigger: `prompt.trim()` is exactly `"works"`, `"fixed"` or `"works, fixed"`, optionally followed by an item id —
  `works #39`** — the whole message, trimmed, is one of those words, with or without
  ` #N` after it. Without an id it confirms the item most recently worked in this session; with
  one it confirms exactly `#N` — no guessing, no candidate question, an id wins over a `#wait`
  hold; if `#N` is not in the file or is a personal (ignored) row, say so and touch nothing. Either
  way: mark it `[x]` **and run `/todoIdealPrompt #N --replace`** for it in the same turn,
  without asking. If more than one item is plausibly "the one", ask which — at most 3
  candidates — before touching anything. Any other confirmation still only ticks. The same
  trigger is also injected by the `UserPromptSubmit` hook `.claude/hooks/todo-confirm.sh`
  (wired in `.claude/settings.json`), so it fires whether or not this file is in context; the
  hook reads the same words from `config.json`, and this bullet is the rule when they differ.
- A pasted item with no `#N` is new: append it to the todo file as `- [ ] #(next id) …` (see
  **Ids**), then start the work. If the pasted text matches a placeholder line already in the
  file (see Autoincrement), assign that line its id instead of appending a duplicate.

**Wait keywords — hold the item, start on `#go`.** A work-item prompt whose trimmed text
**ends** with `#wait` or `#more` (either form, same meaning; also honoured when the item's text
in the todo file ends with one) is resolved but not started: assign ids as usual, name the held
item in one line (`Holding #35 — say #go to start`), and stop. The keyword is not part of the
task — strip it from the addenda, and `/todoIdealPrompt --replace` drops it from the file
along with the rest of the old text. While an item is held, every following prompt feeds it
instead of starting work: a skill call (a screenshot skill, a log-analysis skill, any skill)
runs normally and its result belongs to the held item; plain text is an addendum,
acknowledged in one line. **`#go`** — the prompt trimmed is `#go` or exactly `go`, or starts
with `#go` followed by extra words, which are the last addenda — starts the work with
everything gathered. A new `#N` / `#new…` / pasted-item prompt drops the hold and works that
item instead; a confirm word while holding refers to the item worked before the hold, as
usual — `works #N` names one outright. Nothing is ticked or edited by holding or by
`#go` beyond the Autoincrement pass.

Todo file format: a `# BestPizza — TODO` header, then bullet task-list entries
`- [ ] #N description` with optional indented sub-bullets for detail. There is no counter line.

**Ids.** The next id is the highest `#N` present in the todo file and in its archive
(`TODO.<name>.archive.md`, if it exists) plus one. That only stays safe if ids can never
disappear, so **done items are never deleted**: when the file gets long, `[x]` items are moved
to the archive file, in the same format, and nothing else — `/todoArchive` does that; it makes
no git checks and no commits, the move lands in git with the user's next commit. Ids typed by
hand are kept as written. Ids are scoped to the user — `#19` in `TODO.jd.md` and
`#19` in another user's file are unrelated items.

**Autoincrement.** The user may add an item without an id: `- [ ] #new text`, `- [ ] #newCam
text` (any suffix, no spaces, makes the token unique), or a top-level `- [ ]` line with no `#`
token at all (treated as bare `#new`). Whenever Claude resolves the todo file for any reason —
a `#N` or `#new…` prompt, a confirm word, `/todoIdealPrompt`, `/todoIdealAll` — first assign
ids: walk the file top to bottom, replace each placeholder with the next id (inserting `#N `
after `- [ ] ` when there was no token), normalise `- []` to `- [ ]`, and tell the user which
tokens became which ids. Edit tool only. Remember the token→id map for the rest of the
session, so `#newCam` still resolves after it became `#27`. Resolving a `#new…` prompt: a
suffixed token names its item; bare `#new` names the only bare-new item, or, if there are
several (or a suffix is duplicated), lists them with their fresh ids and asks which — at most
3 shown. A numeric suffix with no such token in the file, `#new2`, is positional: the 2nd
placeholder counting from the top. A placeholder indented under another item is a new item
that landed in the wrong place (the IDE continued the indentation): lift it to top level, its
trailing detail lines as its own sub-bullets. `/todoNumber` runs this assignment on demand
without starting any work.

**Ticket blocks.** An item may carry a ticket key right after its id, before any tag —
`- [ ] #32 PROJ-123 IOS: description` — and the file may group a ticket's items under
a `## PROJ-123 — <summary>` heading with an optional `> ` excerpt line beneath it.
The key on the item is the durable link (it survives `/todoArchive` and
`/todoIdealPrompt --replace`, whose preserved prefix is `- [state] #N KEY TAG: `); the heading
is for reading only and is dropped by `/todoArchive` once every item under it is gone.
Headings and `> ` lines are never items. The `QA:` rows a ticket block ends with (what
`/todoFromTicket` writes after the dev items) are the ticket's manual checks — ignore rows like
any other `QA:` row, ticked by the user, never by Claude.
<!-- prompt-todo:tracker -->
No ticket tracker is connected: `/todoFromTicket` only works in paste mode (the ticket text pasted after the key). `/todoSetup tracker` connects Jira or GitHub Issues.
<!-- /prompt-todo:tracker -->
<!-- prompt-todo:appNavigation -->
No app-navigation skill is connected: when a ticket ends in a context block (the `Server:` / environment / screen lines a bug report carries), `/todoFromTicket` keeps those lines as plain sub-bullets of the first dev item. `/todoSetup appNavigation` connects a skill that opens the app at that screen.
<!-- /prompt-todo:appNavigation -->

**Tags.** An item may carry one tag right after its id (or after its ticket key, when it has
one) — `- [ ] #19 IOS: description`:

<!-- prompt-todo:tags -->
| Tag        | Meaning |
|------------|---------|
| `Bug:`     | defect  |
| `Feature:` | new     |

There is no default tag: an item without a tag simply has no tag.
<!-- /prompt-todo:tags -->

Ignoring a personal (ignored) row means: never work it, rewrite it, tag it, or check it off — if
one is pasted as a prompt, say it's the user's own task and stop. When `/todoIdealPrompt --replace` or
`/todoIdealAll` rewrites an item, the preserved prefix is `- [state] #N KEY TAG: ` — the ticket
key and the tag survive the rewrite.

<!-- prompt-todo:codeMarkers -->
**Code markers — prompt history.** Every code change implementing todo item `#N` carries the marker `[<name>#N]` — the file owner's `<name>` plus the id, e.g. `[jd#19]` — inside a comment at each principal change site, appended to the comment the change already warrants (never as a bare marker-only comment where none is justified): `// Pinned to the physical top strip … [jd#16]`. A site shaped by several items lists them all: `[jd#16 jd#21]`. This is how code is traced back to the prompt that caused it — `grep -rn "\[jd#16\]"` finds that user's item 16. Applies to new work; no retroactive tagging. `/todoMarkCode off` turns the markers off.
<!-- /prompt-todo:codeMarkers -->

<!-- prompt-todo:promptScores -->
**Prompt scores.** Whenever an item is rewritten to its ideal prompt (a confirm word, `/todoIdealPrompt --replace`, `/todoIdealAll`, `/todoReverse`), the original prompt gets a score for how close it was to the ideal one, appended to the end of the item line as ` (N/5)` — after the ideal prompt's first line, sub-bullets untouched: `- [x] #12 PROJ-123 IOS: Rotate the owner label with the device (3/5)`. 5: the original already was the ideal prompt. 4: one small addition. 3: a constraint or two only surfaced through corrections. 2: the intent was there, most constraints came from corrections. 1: a bare pointer ("fix it"); the result came from the dialog. Discovery no prompt could have skipped (a real bug hunt) does not lower the score. A rewrite replaces an existing ` (N/5)`, never adds a second; never on a personal (ignored) row. `/todoIdealPrompt` prints the score with one clause of why as the first Feedback bullet, with or without `--replace`. `/todoScore off` turns the scores off.
<!-- /prompt-todo:promptScores -->

**/todoIdealPrompt.** After a task is confirmed fixed, the `/todoIdealPrompt` skill distills
the dialog into the prompt that would have produced the result in one try. That skill may edit
the todo file **only** when invoked with `--replace` (replacing the item's text with the ideal
prompt); without the flag it prints only.

**/todoIdealAll.** The batch pass: rewrites every session-worked `[x]` item's text to its ideal
prompt. It may edit the todo file by design; it never renumbers ids (assigning placeholder ids
is the Autoincrement rule, which runs on every touch), and never touches done items whose
dialog is not in the current session.

**/todoReverse.** The reverse direction, for hotfixes done straight through the terminal with
no `#N`: takes the most recent untracked dialog of the session (or the one a hint argument
names), distills it into its ideal prompt with the `/todoIdealPrompt` rules, appends it to the
todo file as `- [x] #N KEY TAG: …` with the next id (`- [ ]` with `--open`, which makes it the
item a confirm word then refers to), and — while code markers are on — adds the `[<name>#N]`
markers at that dialog's change sites. Never duplicates an item that already exists for the
dialog, never commits. It may edit the todo file and add markers in code by design.

**/todoSetup.** The configuration wizard for this flow; runs only when the user invokes it.
It edits `.claude/prompt-todo/config.json` and re-renders this file. Never suggest editing this
file by hand.
