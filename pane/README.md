# The Mentat band and pane

The Mentat band and pane (desktop app and terminal) show what needs you and what is going on. They are a Claude Code mod, and everything that belongs to them is in this folder.

## The band

The band above the prompt appears only for something you own: an open question, or this session's pull request once Claude Code has posted its final check on the current head commit (a comment starting `Final check on <sha>`), or, when neither applies, a 5-hour or weekly rate limit at 80% or more (the context window never raises it). The budget band is read each time the band is drawn, so it can lag a change in usage by up to a minute.

## The pane

The band's Details button opens the pane, as does `/mentat`. When there is no open question, no followed pull request and no agent, `/mentat` instead answers with one line of the session budget, such as `Context 10% · 5-hour 12% (1h 29m) · Week 8% (6d)`.

The pane shows, in this order:

1. The open questions (the agent records each one itself; nothing forces it to), with a button for its recommended answer when it has one, a text field and Dismiss. An answer goes to chat as a message. While Claude Code is in a turn the message waits for it to end, so after the first press the card shows a "Sent" line in place of the answer buttons and field (it says so while the message waits), keeps Dismiss, and ignores further presses.
2. The session's pull request, as facts read directly from GitHub: its state, CI, Codex's review of the current head, and the number of other open pull requests in this repository.
3. The agents, with their status and elapsed time.
4. The context window and rate limits.

## The session's pull request

The session's pull request is the one named by a `gh pr create` or `mentat review` command in this session, or by `/mentat pr <number>`. It is not remembered across sessions, `/clear`, `/resume` or `/branch`. A line that says a read failed, or how old it is, appears when GitHub could not be read or the data is more than five minutes old. The pane reads GitHub with `gh` and approves, denies or changes no tool call.

## What is in this folder

- `progress.tsx`: the mod.
- `progress.test.tsx`: its tests, run by `claude plugin test .`.
- `types.d.ts`: the shape of the mod's state, named by `types` in `.claude-plugin/plugin.json`.

## Removing it

1. Delete this folder, `pane/`.
2. In `hooks/hooks.json`, delete the `"modules": ["../pane/progress.tsx"],` line.
3. In `.claude-plugin/plugin.json`, delete the `"types": "./pane/types.d.ts"` line, and the comma after the line above it.
4. In `tests/run`, delete the block that runs `claude plugin validate .` and `claude plugin test .` (it starts at the comment "The Mentat band and pane is a Claude Code mod"). If you want the plugin still validated, keep the `validate` step.
5. Delete the one-line links to this folder: the clause in `README.md` (the plugin's list, line 9), the bullet in `docs/how-it-works.md`, and the two mentions in `AGENTS.md` (the list in the first paragraph, and the sentence "The band and pane ... is the one TypeScript file", which no longer holds).
