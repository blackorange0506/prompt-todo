# App navigation: from a ticket to the screen

`/appNavigation` (alias `/openApp`) is the optional half of the flow: `/todoFromTicket` writes
a `/appNavigation` item when a ticket ends in a context block and a navigation skill is
connected, and typing that item's `#N` opens the app there, so the dev items' `QA:` checks
can start from the right screen.

```markdown
- [ ] #32 PROJ-321 /appNavigation
  - Server: stage
  - Restaurant: Downtown
  - Pizza: Margherita
  - Topping: Olives
- [ ] #33 PROJ-321 Android+: Recompute the order total from the current toppings whenever one is removed.
  - [ ] QA: on the #32 screen, add olives, remove them: the total goes back to the pizza price
```

## The package ships a description, not an implementation

`.claude/skills/appNavigation/SKILL.md` says what the skill should do — take the locator, put
the right build for `Server:` on a device, simulator or browser, log in, walk to the screen
the spec names, ask when a step is ambiguous, report the screen reached — and states that it
is not implemented yet. Everything that would make it work is specific to your app: the build
system and environments, the login, the screen names and test ids, and the automation tool
(Maestro, XCUITest, Playwright, adb, …). Write the steps into that file, put any scripts next
to it, and keep credentials in a file that stays out of git.

## Connecting it

`/todoSetup appNavigation` → *Connect an existing skill*. Any skill that takes the spec lines
as sub-bullets qualifies: the shipped placeholder once you have implemented it, or a skill you
already had under another name. The rules then gain the **App-navigation items** paragraph and
`/todoFromTicket` starts writing the item; until then a ticket's context block stays as plain
sub-bullets of the first dev item, so nothing is lost.
