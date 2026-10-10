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

1. A Commands card, a reference of the commands you type, each with when to use it. It starts collapsed behind a `▸ Commands` button (`▾ Commands` when open; the choice is kept), on the desktop and the terminal. Open, it draws a table with the header `Command | Use` and one row per command, each command in code style: `/mentat` (open this pane), `/mentat pr <n>` (follow a pull request), `/mentat:come-again` (restate the last message), `/mentat:retro` (look back at a session that went badly), `/mentat:codex-review-off` and `/mentat:codex-review-on` (turn Codex reviews off or back on for the session), and `mentat check` (in a terminal: check what Mentat needs). The table is a markdown block, with no background. Nothing in the card runs a command. The list is the `COMMANDS` constant in `progress.tsx`, and `tests/run` checks that each `/mentat:<skill>` in it has a `skills/<skill>/SKILL.md`. The card stays when the desktop pane says `Nothing waiting on you.`
2. The open items, in this order: alerts, then questions, then check warnings, then actions, and in the order opened within each kind. The agent records each one itself with `open_decision` (nothing forces it to) and closes it with `close_decision`; a call without a `kind` is a question, and a `kind` other than `question`, `action` or `alert` is refused (the `warning` kind below is only for the mod).
   - A question (amber, `QUESTION FOR YOU`) has a button for its recommended answer when it has one, a text field and Dismiss. An answer goes to chat as a message. While Claude Code is in a turn the message waits for it to end, so after the first press the card shows a "Sent" line in place of the answer buttons and field (it says so while the message waits), keeps Dismiss, and ignores further presses.
   - An action (blue, `WAITING ON YOU`) is something only you can do: a merge, a manual test, a plugin update after a merge, rotating a secret. An alert (red, `ALERT`) is a failure the agent could not resolve, a blocking disagreement on a review finding, or an exposed secret. Neither has answer buttons; each has Dismiss.
   - An action or an alert may carry a link (the issue or pull request that holds the steps), drawn as a link beside Dismiss, under the card on the desktop. Only an `https` URL is drawn; any other value is ignored. A question draws no link.
3. On the terminal only, the session's pull request, as facts read directly from GitHub: state, CI, Codex's review and the number of other open pull requests in this repository. The desktop pane no longer draws a pull request card: the app already shows its own chip with the pull request's number, branch, diff size and CI, and the log (next) says when the pull request opened and merged. The pane still reads the followed pull request on the desktop, and the band still raises it once its final check is posted.
4. The log, under the open items and, on the terminal, under the pull request card. One line per event the pane saw, newest first, in plain text rows with no background: the time (12-hour with AM or PM and no seconds, as `10:12 PM` or `9:05 AM`, right-aligned so the times line up, in the time zone the weekly reset uses), an icon for the kind of event and a line of at most 60 characters (longer ones are cut with `…`). The newest five show; a `Show all N` button shows the rest and `Show fewer` goes back (the choice is kept). The log keeps the last 200 entries, lasts for the session and survives a reload of the pane; a `/clear`, `/resume` or `/branch` empties it. With no entries the card is not drawn. No model writes it: each entry comes from an event the pane already sees, and an event equal to the entry just before it is not added again.
   - `↑ Opened PR #N: <title>`: a `gh pr create` in the main session printed the pull request's URL. The title is the one given with `--title` (or `-t`), without its `feat:` style prefix; without one the line is `Opened PR #N`.
   - `↑ PR #N ready for review`: a `gh pr ready` said the pull request is marked ready.
   - `✕ Closed PR #N: <title>`: a `gh pr close` said it closed the pull request.
   - `✓ Merged PR #N: <title>`: a read of the followed pull request found it merged, when the read before found it not merged.
   - `○ Opened issue #N: <title>` and `● Closed issue #N: <title>`: a `gh issue create` printed the issue's URL, or a `gh issue close` said it closed the issue.
   - `? <question> → <outcome>`: the agent settled a question with `close_decision`. An action settled that way has a `→` icon and an alert a `!`. The question is cut to leave room for the outcome; without an outcome the line is `Settled: <question>`.
   - `⊘ Codex reviews turned off` and `⊙ Codex reviews turned on`: `/mentat:codex-review-off` or `/mentat:codex-review-on` ran.
   - `▸ Builder started: <description>`, then `✓ Builder finished: <description>`, `✕ Builder failed: <description>` or `✕ Builder stopped: <description>`: a `builder` or `mentat:builder` agent spawned, then ended as completed, failed or killed. An agent that only disappears from the engine's list is not logged as finished.
   - A command that failed prints no URL or success line and logs nothing. Settings are not in the log.
5. The agents, in two groups: `Running · N` and `Finished · N`. A group with no agents is left out. A button above the finished rows hides and shows them (they start shown, and the choice is kept). Each row is one line. On the desktop it reads, left to right: an icon for the agent's role (a wrench for `builder` and `mentat:builder`, a magnifier for `Explore`, a compass for `Plan`, a dot for any other type, each in the role's color), the title (the agent's description, cut with `…` when it is long), the model and effort in a dimmer color, then at the right the tokens reported and the elapsed time (what is missing is left out) and, at the edge, the status: a dot while it runs, a check when it completed, a cross when it failed or was killed, and a ring when its end is not known. The role is not drawn as a word; it is in the alt text of the card (`Running agents: 2 (builder: <title>; explore: <title>)`). On the terminal the row has the same order, with a one-character mark for the role instead of the icon (`◆` builder, `◎` Explore, `◇` Plan, `·` other), the title cut with `…` to keep the line one line, and the status said in words as well (`waiting`, `idle`, `failed`, `killed`, `ended`) before the elapsed time when the mark alone does not say it; below 48 columns the effort and the tokens are left out. Finished agents are dimmed.

The pane shows no usage on either surface: no context window or rate-limit meters. The app's own usage popover shows them, and the band warns when a rate limit reaches 80%. With no open item, no log entry and no agent, the desktop pane says `Nothing waiting on you.`

The terminal pane draws no background colors (a terminal shows the alpha tints the desktop uses as opaque grey): its cards are plain text, and the kind of an open item is marked by its colored heading. The desktop keeps its tinted answer field.

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

The session's pull request is the one named by a `gh pr create` or `mentat review` command in this session, or by `/mentat pr <number>`. It is not remembered across sessions, `/clear`, `/resume` or `/branch`. On the terminal, a line that says a read failed, or how old it is, appears in the pull request card when GitHub could not be read or the data is more than five minutes old; the desktop pane draws neither the card nor the line. The pane reads GitHub with `gh` and approves, denies or changes no tool call.

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
