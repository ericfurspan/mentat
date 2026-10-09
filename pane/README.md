# The Mentat band and pane

The Mentat band and pane (desktop app and terminal) show what needs you and what is going on. They are a Claude Code mod, and everything that belongs to them is in this folder.

## The band

The band above the prompt appears only for something you own. What it shows on its left is the first that applies, in this order:

1. The newest open alert (a red `!` on the desktop).
2. The newest open question (an amber `?`).
3. This session's pull request, once Claude Code has posted its final check on the current head commit (a comment starting `Final check on <sha>`).
4. A 5-hour or weekly rate limit at 80% or more (the context window never raises it). The budget band is read each time the band is drawn, so it can lag a change in usage by up to a minute.
5. The newest open action (a blue arrow), so that an action waiting on you is not hidden when nothing else raises the band.

The count at the right counts all open items: `N questions` when every one is a question, otherwise `N items`. It is colored by the most urgent item (red for an alert, amber for a question, blue for an action). On the desktop it is left out when the one open item is the one shown.

## The pane

The band's Details button opens the pane, as does `/mentat`. When there is no open item, no followed pull request and no agent, `/mentat` instead answers with one line of the session budget, such as `Context 10% · 5-hour 12% (1h 29m) · Week 8% (6d)`.

The pane shows, in this order:

1. The open items, in this order: alerts, then questions, then actions, and in the order opened within each kind. The agent records each one itself with `open_decision` (nothing forces it to) and closes it with `close_decision`; a call without a `kind` is a question, and a `kind` other than `question`, `action` or `alert` is refused.
   - A question (amber, `QUESTION FOR YOU`) has a button for its recommended answer when it has one, a text field and Dismiss. An answer goes to chat as a message. While Claude Code is in a turn the message waits for it to end, so after the first press the card shows a "Sent" line in place of the answer buttons and field (it says so while the message waits), keeps Dismiss, and ignores further presses.
   - An action (blue, `WAITING ON YOU`) is something only you can do: a merge, a manual test, a plugin update after a merge, rotating a secret. An alert (red, `ALERT`) is a failure the agent could not resolve, a blocking disagreement on a review finding, or an exposed secret. Neither has answer buttons; each has Dismiss.
   - An action or an alert may carry a link (the issue or pull request that holds the steps), drawn as a link beside Dismiss, under the card on the desktop. Only an `https` URL is drawn; any other value is ignored. A question draws no link.
2. The session's pull request, as facts read directly from GitHub. The desktop app already shows its own chip with the pull request's number, branch, diff size and CI, so the desktop card adds only what that chip lacks: GitHub's approval state, Codex's review of the current head, and whether the final check is posted on it (CI appears only when checks failed). The terminal has no such chip, so the terminal card shows the full set: state, CI, Codex's review and the number of other open pull requests in this repository.
3. The agents, in two groups: `Running · N` and `Finished · N`. A group with no agents is left out. A button above the finished rows hides and shows them (they start shown, and the choice is kept). Each row has an icon for the agent's role on the left (a wrench for `builder` and `mentat:builder`, a magnifier for `Explore`, a compass for `Plan`, a dot for any other type), and its status on the right edge: a dot while it runs, a check when it completed, a cross when it failed or was killed, and a ring when its end is not known. The row's title is the agent's description. Under it come the role in the role's color, then the model and effort. On the desktop a third line at the right has the tokens reported and the elapsed time, and leaves out what is missing; the terminal keeps its facts on one line. Finished agents are dimmed.
4. The context window and rate limits.

## The `mentat check` signal

The mod reads the Bash commands of the main session (not a subagent's) for `mentat check`. A Bash result has no exit code, so it reads the check's final line.

- `Check failed: N problem(s)` pins one alert with that line and each `PROBLEM:` line under it (at most six lines; with more problems the sixth line says `+N more`). The alert has the fixed id `check`: the next failed run replaces it, so there is never more than one, and Dismiss removes it.
- `Check OK (N warning(s))` removes that alert and shows a short toast, `Mentat engaged`, followed by ` · N warnings` when the check printed warnings. Nothing stays in the band.
- A run with neither final line (an interrupted run, a usage error, output cut by a pipe) changes nothing.

Open items belong to the conversation: a `/clear`, `/resume` or `/branch` drops them all, the check alert included.

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
