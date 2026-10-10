# The Mentat band and pane

The Mentat band and pane (desktop app and terminal) show what needs you and what is going on. They are a Claude Code mod, and everything that belongs to them is in this folder.

## The band

The band above the prompt appears only for something you own. What it shows on its left is the first that applies, in this order:

1. The newest open alert (a red `!` on the desktop).
2. The newest open question (an amber `?`).
3. The open check warning, when a `mentat check` passed with warnings (an amber `!`).
4. This session's pull request, once Claude Code has posted its final check on the current head commit (a comment starting `Final check on <sha>`).
5. A 5-hour or weekly rate limit at 80% or more (the context window never raises it). It names when the limit resets: a countdown for the 5-hour limit (`5-hour limit 91% · resets in 1h 29m`), the weekday and local time for the weekly one (`Week limit 91% · resets Thu 7:00 PM`, as the desktop app's usage popover words it). The budget band is read each time the band is drawn, so it can lag a change in usage by up to a minute.
6. The newest open action (a blue arrow), so that an action waiting on you is not hidden when nothing else raises the band.

The count at the right counts all open items: `N questions` when every one is a question, otherwise `N items`. It is colored by the most urgent item (red for an alert, amber for a question or a check warning, blue for an action). On the desktop it is left out when the one open item is the one shown.

## The pane

The band's Details button opens the pane, as does `/mentat`. With nothing else to show, the pane still opens, with the Commands card.

The pane shows, in this order:

1. A Commands card, a reference of the commands you type, each with when to use it. It starts collapsed behind a `▸ Commands` button (`▾ Commands` when open; the choice is kept), on the desktop and the terminal. Open, it lists one line per command: `/mentat` and `/mentat pr <n>` (open this pane, or follow a pull request), `/mentat:come-again` (restate the last message), `/mentat:retro` (look back at a session that went badly), `/mentat:codex-review-off` and `/mentat:codex-review-on` (Codex reviews off or back on for the session), and `mentat check` in a terminal (check what Mentat needs). It is plain text: nothing in the card runs a command. The list is the `COMMANDS` constant in `progress.tsx`, and `tests/run` checks that each `/mentat:<skill>` in it has a `skills/<skill>/SKILL.md`. The card stays when the desktop pane says `Nothing waiting on you.`
2. The open items, in this order: alerts, then questions, then check warnings, then actions, and in the order opened within each kind. The agent records each one itself with `open_decision` (nothing forces it to) and closes it with `close_decision`; a call without a `kind` is a question, and a `kind` other than `question`, `action` or `alert` is refused (the `warning` kind below is only for the mod).
   - A question (amber, `QUESTION FOR YOU`) has a button for its recommended answer when it has one, a text field and Dismiss. An answer goes to chat as a message. While Claude Code is in a turn the message waits for it to end, so after the first press the card shows a "Sent" line in place of the answer buttons and field (it says so while the message waits), keeps Dismiss, and ignores further presses.
   - An action (blue, `WAITING ON YOU`) is something only you can do: a merge, a manual test, a plugin update after a merge, rotating a secret. An alert (red, `ALERT`) is a failure the agent could not resolve, a blocking disagreement on a review finding, or an exposed secret. Neither has answer buttons; each has Dismiss.
   - An action or an alert may carry a link (the issue or pull request that holds the steps), drawn as a link beside Dismiss, under the card on the desktop. Only an `https` URL is drawn; any other value is ignored. A question draws no link.
3. The session's pull request, as facts read directly from GitHub. The desktop app already shows its own chip with the pull request's number, branch, diff size and CI, so the desktop card adds only what that chip lacks: GitHub's approval state, Codex's review of the current head, and whether the final check is posted on it (CI appears only when checks failed). The terminal has no such chip, so the terminal card shows the full set: state, CI, Codex's review and the number of other open pull requests in this repository.
4. The agents, in two groups: `Running · N` and `Finished · N`. A group with no agents is left out. A button above the finished rows hides and shows them (they start shown, and the choice is kept). Each row has an icon for the agent's role on the left (a wrench for `builder` and `mentat:builder`, a magnifier for `Explore`, a compass for `Plan`, a dot for any other type), and its status on the right edge: a dot while it runs, a check when it completed, a cross when it failed or was killed, and a ring when its end is not known. The row's title is the agent's description. Under it come the role in the role's color, then the model and effort. On the desktop a third line at the right has the tokens reported and the elapsed time, and leaves out what is missing; the terminal keeps its facts on one line. Finished agents are dimmed.
5. On the terminal only, the context window and rate limits as text meters, each with its reset (`resets in 1h 29m` for the 5-hour limit, `resets Thu 7:00 PM` for the weekly one). The desktop pane leaves them out: the app's own usage popover shows them. With nothing else to show, the desktop pane says `Nothing waiting on you.`

The weekly reset is shown in the time zone of the `TZ` environment variable when it is set, otherwise in the zone Claude Code runs in.

## The `mentat check` signal

The mod reads the Bash commands of the main session (not a subagent's) for `mentat check`. A Bash result has no exit code, so it reads the check's final line.

The footer label shows the last result. It sits in the prompt footer, at the left of the engine's own mode labels (which stay after it, dimmed), on the terminal and the desktop:

- `● Mentat`, dim, before any check has run in this conversation.
- `● Mentat`, green, after a check that passed with no warnings.
- `● Mentat · N warning(s)`, amber, after a check that passed with warnings.
- `● Mentat check failed`, red, after a check that failed.

- `Check failed: N problem(s)` pins one alert with that line and each `PROBLEM:` line under it (at most six lines; with more problems the sixth line says `+N more`). The alert has the fixed id `check`: the next failed run replaces it, so there is never more than one, and Dismiss removes it.
- `Check OK (N warning(s))` with warnings removes that alert and pins one warning card (amber, `CHECK WARNINGS`) with each `WARN:` line under it (at most six lines, cut the same way). It has the fixed id `check` too, so the next run replaces it, it has Dismiss only and no link, and it raises the band as shown above. With no warnings, `Check OK (0 warning(s))` removes the alert and the warning card, and nothing stays in the band.
- A run with neither final line (an interrupted run, a usage error, output cut by a pipe) changes nothing.

Open items belong to the conversation: a `/clear`, `/resume` or `/branch` drops them all, the check alert and the warning card included, and the footer label goes back to dim. A mod reload keeps both.

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
