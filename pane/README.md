# The Mentat band and pane

The Mentat band and pane (desktop app and terminal) show what needs you and what is going on. They are a Claude Code mod, and everything that belongs to them is in this folder.

## The band

The band above the prompt is always there, on the desktop and the terminal, in one line. What it shows on its left is the first that applies, in this order:

1. An item that waits on you, the most urgent: an alert (a red `!` on the desktop), then a question (an amber `?`), then the check warning from a `mentat check` that passed with warnings (an amber `!`), then an action (a blue arrow); the newest within a kind. The agent records items with `open_decision` (nothing forces it to) and closes them with `close_decision`; a call without a `kind` is a question, and a `kind` other than `question`, `action` or `alert` is refused (the `warning` kind is only for the mod). When more than one item is open, `+N more` follows the text, N being the others.
   - A question with a recommended answer has a button for it, which sends it to chat as a message. While Claude Code is in a turn the message waits for it to end, so after the first press the button gives way to a `Sent: <answer> · queued` line (`Sent: <answer>` once the message has entered the session), and further presses do nothing. There is no free-text field: to answer otherwise, answer in chat.
   - Every item has a Dismiss button.
   - An action or an alert may carry a link (the issue or pull request that holds the steps), drawn beside Dismiss. Only an `https` URL is drawn; any other value is ignored. A question draws no link.
   - The band shows one line, so the recommendation, and the PROBLEM or WARN lines of a `mentat check`, are not drawn anywhere.
2. Otherwise, a 5-hour or weekly rate limit at 80% or more (the context window never raises it). It names when the limit resets: a countdown for the 5-hour limit (`5-hour limit 91% · resets in 1h 29m`), the weekday and local time for the weekly one (`Week limit 91% · resets Thu 7:00 PM`, as the desktop app's usage popover words it). The budget is read each time the band is drawn, so it can lag a change in usage by up to a minute.
3. Otherwise, the newest note in the Log (see below): the kind's icon and the text.
4. Otherwise, a quiet `Mentat` line.

The band is one row on both surfaces: the icon and the text, cut with `…` to fit, then in one row at the right the answer button, Dismiss, the link and the Details button. Details is there in every state and opens the pane, as does `/mentat`. The band reads nothing from GitHub: a pull request with a final check posted no longer raises it. The `Final check on <sha>` comment the review skills ask for is still posted; the band does not look for it.

The band is hidden only while the app shows a survey.

## The pane

The pane opens from the band's Details button and with `/mentat`. It no longer holds what waits on you: the question, action, alert and check warning cards, and the free-text answer field, are gone from both surfaces, and the band is where those are. With nothing else to show, the pane still opens, with the Commands card.

The pane shows, in this order:

1. A Commands card, a reference of the commands you type, each with when to use it. It starts collapsed behind a `▸ Commands` button (`▾ Commands` when open; the choice is kept), on the desktop and the terminal. Open, it draws a table with the header `Command | Use` and one row per command, each command in code style: `/mentat` (open this pane), `/mentat pr <n>` (follow a pull request), `/mentat:come-again` (restate the last message), `/mentat:retro` (look back at a session that went badly), `/mentat:codex-review-off` and `/mentat:codex-review-on` (turn Codex reviews off or back on for the session), and `mentat check` (in a terminal: check what Mentat needs). The table is a markdown block, with no background. Nothing in the card runs a command. The list is the `COMMANDS` constant in `progress.tsx`, and `tests/run` checks that each `/mentat:<skill>` in it has a `skills/<skill>/SKILL.md`. The card stays when the desktop pane says `Nothing waiting on you.`
2. On the terminal only, the session's pull request, as facts read directly from GitHub: state, CI, Codex's review and the number of other open pull requests in this repository. The desktop pane does not draw a pull request card: the app already shows its own chip with the pull request's number, branch, diff size and CI. The pane still reads the followed pull request on the desktop.
3. The log, under the pull request card on the terminal. It shows the notes the agent adds with the `note` tool, newest first, in plain text rows with no background: the time (12-hour with AM or PM and no seconds, as `10:12 PM` or `9:05 AM`, right-aligned so the times line up, in the time zone the weekly reset uses), an icon in the color of the note's kind and the line. The newest five show; a `Show all N` button shows the rest and `Show fewer` goes back (the choice is kept). The log keeps the last 200 notes, lasts for the session and survives a reload of the pane; a `/clear`, `/resume` or `/branch` empties it. With no notes the card is not drawn. The pane writes nothing to it: a pull request opened or merged, an issue closed, a question settled, a Codex command or a builder finishing adds no line, and a note equal to the one just before it is not added again. The newest note is also the band's line when nothing else is to be shown.
   - `note` takes `text` (required, one line, cut at 80 characters with `…`) and an optional `kind`, which is `plan` when left out. A call without text, or with a `kind` that is not one of these five, is refused and adds nothing. It answers `Noted.`
   - The kinds: `decision` (`◆`, a decision the maintainer made), `plan` (`▸`, a change of plan or what comes next), `surprise` (`!`, amber, something surprising found), `waiting` (`◌`, dim, what the agent now waits on) and `done` (`✓`, green, a piece of work finished).
   - The tool's description tells the agent to add a note only at such a moment, a few an hour at most and never for routine steps, and `rules.md` says the same. Nothing forces it to.
4. The agents, in two groups: `Running · N` and `Finished · N`. A group with no agents is left out. A button above the finished rows hides and shows them (they start shown, and the choice is kept). Each row is one line. On the desktop it reads, left to right: an icon for the agent's role (a wrench for `builder` and `mentat:builder`, a magnifier for `Explore`, a compass for `Plan`, a dot for any other type, each in the role's color), the title (the agent's description, cut with `…` when it is long), the model and effort in a dimmer color, then at the right the tokens reported and the elapsed time (what is missing is left out) and, at the edge, the status: a dot while it runs, a check when it completed, a cross when it failed or was killed, and a ring when its end is not known. The role is not drawn as a word; it is in the alt text of the card (`Running agents: 2 (builder: <title>; explore: <title>)`). On the terminal the row has the same order, with a one-character mark for the role instead of the icon (`◆` builder, `◎` Explore, `◇` Plan, `·` other), the title cut with `…` to keep the line one line, and the status said in words as well (`waiting`, `idle`, `failed`, `killed`, `ended`) before the elapsed time when the mark alone does not say it; below 48 columns the effort and the tokens are left out. Finished agents are dimmed.

The pane shows no usage on either surface: no context window or rate-limit meters. The app's own usage popover shows them, and the band warns when a rate limit reaches 80%. With no open item, no note and no agent, the desktop pane says `Nothing waiting on you.`; while an item is open the pane does not say it, because the band shows what waits.

The terminal pane draws no background colors (a terminal shows the alpha tints the desktop uses as opaque grey): its cards are plain text.

The weekly reset is shown in the time zone of the `TZ` environment variable when it is set, otherwise in the zone Claude Code runs in.

## The `mentat check` signal

The mod reads the Bash commands of the main session (not a subagent's) for `mentat check`. A Bash result has no exit code, so it reads the check's final line.

The pane also runs `mentat check` itself, once at session start (a startup or a mod reload, and after `/clear`, `/resume` and a fork, once the label has gone back to dim), in the session's directory and without waiting for a message, so the footer label is current before the agent has run anything. It runs only when that directory is inside a git work tree (`git rev-parse --is-inside-work-tree` prints `true`); elsewhere, such as a folder that is not a repository, it does nothing. A failing check exits 1 and still prints its `Check failed:` line, so its output is read whatever the exit code. If `mentat` cannot be run (it is not on the `PATH`), nothing is recorded and the label stays dim. The result is recorded exactly as the agent's own run is, and the agent's run, which `rules.md` asks for before change work, still updates the label: the later result wins, so a slow startup run never overwrites an agent's run that landed first.

The footer label shows the last result. It sits in the prompt footer, at the left of the engine's own mode labels (which stay after it, dimmed), on the terminal and the desktop:

- `● Mentat`, dim, before any check has run in this conversation.
- `● Mentat`, green, after a check that passed with no warnings.
- `● Mentat · N warning(s)`, amber, after a check that passed with warnings.
- `● Mentat check failed`, red, after a check that failed.

- `Check failed: N problem(s)` pins one alert with that line. The alert has the fixed id `check`: the next failed run replaces it, so there is never more than one, and Dismiss removes it. The `PROBLEM:` lines are not drawn: run `mentat check` to read them.
- `Check OK (N warning(s))` with warnings removes that alert and pins one warning item (amber, `Check passed with N warnings`). It has the fixed id `check` too, so the next run replaces it, it has Dismiss only and no link, and it shows in the band in its place in the order above. The `WARN:` lines are counted (the footer label shows the count) but not drawn. With no warnings, `Check OK (0 warning(s))` removes the alert and the warning item, and the band shows what comes next.
- A run with neither final line (an interrupted run, a usage error, output cut by a pipe) changes nothing.

Open items belong to the conversation: a `/clear`, `/resume` or `/branch` drops them all, the check alert and the warning item included, and the footer label goes back to dim. A mod reload keeps both.

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
