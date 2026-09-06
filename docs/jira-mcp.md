# Tickets: Jira through the Atlassian MCP server, or GitHub Issues

`/todoFromTicket` turns a ticket into numbered first prompts in your todo file — and, when an
app-navigation skill is connected, into the item that opens the app where the bug lives. To
read tickets Claude needs a connection to your tracker. Nothing else in the flow needs it:
without one, `/todoFromTicket` still works with the ticket text pasted after the key, and the
rest of the flow is unaffected.

## The worked example

The sample app in these docs is **BestPizza** (web, Android, iOS; screens Restaurant → Pizza →
Topping). Ticket PROJ-321, "Order total wrong after removing a topping":

> Add a Margherita, add olives, remove olives: the total still includes the topping.
>
> Server: stage
> Restaurant: Downtown
> Pizza: Margherita
> Topping: Olives
>
> Attachment: order.log

```
/todoFromTicket PROJ-321
```

Claude fetches the ticket, saves `order.log` to `todoAttachments/PROJ-321/`, and appends to
`TODO.jd.md`:

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

The `#32` item exists only when an app-navigation skill is connected (`/todoSetup
appNavigation`); otherwise the four locator lines become sub-bullets of `#33`. Then:

```
#32            open the app at Downtown → Margherita → Olives on the device
#33            work the first dev item
works          tick #33, rewrite #33 to its ideal prompt
#35            yours: run the check on the device, tick the row by hand
```

## Jira: the Atlassian MCP server

Atlassian hosts a remote MCP server; Claude Code connects to it over HTTP with OAuth, so no
token is stored in the project. `/todoSetup tracker` runs these steps for you; by hand:

```bash
claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2
claude mcp list          # atlassian should be listed
```

Then, inside Claude Code, run `/mcp`, pick `atlassian`, and log in in the browser. Once.
`--scope user` stores the server in your user config, not in the project, so every project on
the machine can use it and nothing about it is committed.

The skill uses two tools: `getJiraIssue` (the ticket as markdown) and `fetch` (the
attachments). In `config.json`:

```json
"tracker": {"kind": "jira", "jira": {"host": "yourcompany.atlassian.net", "projectKeys": ["PROJ"]}}
```

`host` is accepted in ticket URLs; `projectKeys` are the keys recognised bare (`PROJ-321`).

## GitHub Issues: the `gh` CLI

```bash
brew install gh          # or the GitHub CLI page for other platforms
gh auth login
gh issue list --repo owner/repo --limit 1
```

```json
"tracker": {"kind": "github", "github": {"repo": "owner/repo"}}
```

Issues are keyed `GH-42` on the items and in the heading, so the key never collides with the
item ids. Images linked from the issue body are downloaded as the attachments.

## Paste mode

With `tracker.kind = "none"`, or when a fetch fails, paste the ticket after the key:

```
/todoFromTicket PROJ-321
Order total wrong after removing a topping
Add a Margherita, add olives, remove olives: the total still includes the topping.
Server: stage
Restaurant: Downtown
…
```

Everything else is the same; only the attachment download is skipped.

## Attachments

`attachmentsDir` (default `todoAttachments`) is added to `.gitignore` by `install.sh`. Files
land in `<attachmentsDir>/<KEY>/<original name>`; a second file with the same name gets a
`(2)` suffix.
