# The Mentat band and pane

The Mentat band and pane show what needs you and what is going on. They are a Claude Code mod, and everything that belongs to them is in this folder. The desktop app has a band above the prompt and a pane. The terminal has no band: its footer label counts what waits on you and opens the pane, which lists it.

The mod reads nothing from GitHub. It does not look up the session's pull request, CI or Codex review; the one thing it takes from a pull request is the `Opened PR #<number>` Feed line written when `gh pr create` prints the pull request's URL.

## Where an item that waits on you shows

The agent records items with `open_decision` (nothing forces it to) and closes them with `close_decision`. A call without a `kind` is a question, and a `kind` other than `question`, `action` or `alert` is refused (the `warning` kind is only for the mod). Items are ordered by urgency: an alert, then a question, then the check warning from a `mentat check` that passed with warnings, then an action; the newest first within a kind.

- A question with a recommended answer has a button for it, which sends it to chat as a message. While Claude Code is in a turn the message waits for it to end, so after the first press the button gives way to a `Sent: <answer> · queued` line (`Sent: <answer>` once the message has entered the session), and further presses do nothing. There is no free-text field: to answer otherwise, answer in chat.
- Every item has a Dismiss button.
- The pane keeps a short record, never drawn, of the last 50 items that left without `close_decision`: dismissed with this button, or dropped by a `/clear`, `/resume` or `/branch`. It survives a reload of the pane. `close_decision` on such an item succeeds and says so (`Decision d4 was already dismissed in the pane at 12:05 AM.`, or that it was already cleared when a new conversation started, with `/clear`, `/resume` or `/branch`); on an id with no record it is refused, with `No open decision with id d4, and no record of it being dismissed or cleared.`
- An action or an alert may carry a link (the issue or pull request that holds the steps), drawn beside Dismiss. Only an `https` URL is drawn; any other value is ignored. A question draws no link.

## The terminal

### The footer label

The label sits in the prompt footer, at the left of the engine's own mode labels (which stay after it, dimmed). It is a button: pressing it opens the pane, as does `/mentat` with no arguments.

- `● Mentat`, dim, before any `mentat check` has run in this conversation.
- `● Mentat`, green, after a check that passed with no warnings.
- `● Mentat · N warning(s)`, amber, after a check that passed with warnings.
- `● Mentat check failed`, red, after a check that failed.
- While items wait it reads `● Mentat · N waiting` instead: the dot in the check's color (dim, green, amber or red as above), `Mentat` plain, and `N waiting` in amber. N counts every open item, the check's warning item or alert included; the check's own words (`N warnings`, `check failed`) are left out, because that item in Waiting on you carries them.

### The pane

The pane has two sections, each a frame of dim rounded lines with its title and a count in the top edge (`╭─ WAITING ON YOU 3 ───╮`, `╭─ FEED 31 ───╮`). The width is the pane's body width:

- 60 columns and up: frames, with a side line on every row.
- 40 to 59: each section is headed by a rule (`── FEED 31 ───`) to the full width, with no side lines or bottom edge.
- Under 40: the same rules, and the item times, `Recommended:` lines and `WARN:` lines are left out.

A rate limit at 80% or more (the 5-hour or the weekly one; the context window never raises it) is warned at the top of the pane in one amber line, above the sections: `5-hour limit 91% · resets in 1h 29m`, or `Week limit 91% · resets Thu 7:00 PM` (the weekday and local time, as the desktop app's usage popover words it). The budget is read each time the pane is drawn, and a timer asks for a redraw every minute, so an idle session shows the warning within a minute of the usage crossing the line.

**Waiting on you** lists every open item, most urgent first, and is left out when nothing is open. The first line of an item has its mark (`?` dim for a question, `!` red for an alert, `!` amber for the check warning, `→` blue for an action), its text cut with `…`, and at the end its buttons: the answer of a question that has one and has not been sent (bold), then the link of an action or alert, then Dismiss. The link is drawn short and opens the whole address: `#160` for a GitHub issue or pull request (the bare number, whichever repository it is in, since the pane reads nothing to tell), else the host (`example.com`). The mark keeps a space after it and the text is what is cut when the row is tight. Every unsent question with an answer has its own button. Under the text, dim and indented, is `Recommended: <text> · <time>` when the item has a recommendation, else just the time (12-hour with AM or PM, in the time zone the weekly reset uses). The check's warning item shows the `WARN:` lines of the last `mentat check` under it, one line each. The `PROBLEM:` lines of a failed check are not drawn: run `mentat check` to read them.

**Feed** lists what is going on and is left out when there is nothing to list:

1. The agents that have not ended, pinned on top, one line each: a one-character mark for the role (`◆` builder, `◎` Explore, `◇` Plan, `·` other), the description in bold, cut with `…`, then its state as the engine reports it (`running`, `waiting`, `idle`, `pending`) and, when the start is known, the time it has run, dim. An agent whose start the pane never saw (it was listed at a reload) has no time. Ended agents are not shown: their end is a line in the log.
2. A blank row, when log lines follow.
3. The log, newest first: the time (dropped under 40 columns), the icon in the color of the line's kind, and the line cut with `…`. Notes are in plain text and event lines dim. The newest ten show; `Show all N` shows the rest and `Show fewer` goes back (the choice is kept).

With no open item, no live agent and no log line the pane says `Nothing waiting on you.`

## The desktop

### The band

The band above the prompt is always there, in one line. What it shows on its left is the first that applies, in this order:

1. The item that waits on you, the most urgent (see above); when more than one item is open, `+N more` follows the text, N being the others. Its buttons are in one row at the right: the answer button of a question with a recommended answer (the `Sent:` line once pressed), Dismiss, the link of an action or alert, then Details.
2. Otherwise, a 5-hour or weekly rate limit at 80% or more, worded as above.
3. Otherwise, the newest note in the Log (see below): the kind's icon and the text.
4. Otherwise, a quiet `Mentat` line.

The band shows one line, so the recommendation, and the WARN lines of a `mentat check`, are not drawn on the desktop. Details is there in every state and opens the pane, as does `/mentat`. The band is hidden only while the app shows a survey.

### The pane

The pane opens from the band's Details button and with `/mentat`. It does not hold what waits on you: the band is where that is. With nothing else to show, the pane still opens and says `Nothing waiting on you.`

It shows, in this order:

1. The Log, in plain text rows with no background: the time, right-aligned so the times line up, the icon in the color of the line's kind and the line. An event line is drawn dim. The newest five show; a `Show all N` button shows the rest and `Show fewer` goes back (the choice is kept, and is shared with the terminal's Feed). With no lines the card is not drawn.
2. The agents, in two groups: `Running · N` and `Finished · N`. A group with no agents is left out. A button above the finished rows hides and shows them (they start shown, and the choice is kept). Each row is one line: an icon for the agent's role (a wrench for `builder` and `mentat:builder`, a magnifier for `Explore`, a compass for `Plan`, a dot for any other type, each in the role's color), the title (the agent's description, cut with `…` when it is long), the model and effort in a dimmer color, then at the right the tokens reported and the elapsed time (what is missing is left out) and, at the edge, the status: a dot while it runs, a check when it completed, a cross when it failed or was killed, and a ring when its end is not known. The role is not drawn as a word; it is in the alt text of the card (`Running agents: 2 (builder: <title>; explore: <title>)`).

The pane shows no usage on the desktop: no context window or rate-limit meters. The app's own usage popover shows them, and the band warns when a rate limit reaches 80%.

## The Log

The Log holds the notes the agent adds with the `note` tool and the event lines the pane writes itself, newest first. It keeps the last 200 lines, lasts for the session and survives a reload of the pane; a `/clear`, `/resume` or `/branch` empties it. A note equal to the note just before it is not added again; an event line is always added, so two agents or two questions that read alike each get a line. The desktop band's line (when nothing else is to be shown) is the newest note only, never an event line. A line stored without a source is a note.

- `note` takes `text` (required, one line, cut at 80 characters with `…`) and an optional `kind`, which is `plan` when left out. A call without text, or with a `kind` that is not one of these five, is refused and adds nothing. It answers `Noted.`
- The kinds: `decision` (`◆`, a decision the maintainer made), `plan` (`▸`, a change of plan or what comes next), `surprise` (`!`, amber, something surprising found), `waiting` (`◌`, dim, what the agent now waits on) and `done` (`✓`, green, a piece of work finished).
- The event lines, one per real state change, each cut to one line like a note, with a mark in the color shown:
  - An agent ends: `✓ <Role> finished: <description> · <elapsed>` (green, the elapsed time left out when unknown), `✕ <Role> failed: <description>` or `✕ <Role> stopped: <description>` (red, for a failed or a killed agent). The role is `Builder` (for `builder` and `mentat:builder`), `Explore`, `Plan` or the type as given. An agent whose end is not known, or one the pane first sees already ended, adds no line.
  - `Asked you: <question>` when `open_decision` opens an item, marked like the item: `?` amber for a question, `→` blue for an action, `!` red for an alert.
  - `✓ You answered "<text>": <question>` when the answer button's message has entered the session (not while it waits, and not when it is dropped).
  - `✓ Closed: <question>`, with ` · <outcome>` when one is given, when `close_decision` closes an open item (none for an item that was already dismissed or cleared).
  - `· You dismissed: <question>` when Dismiss removes an open item.
  - A recorded `mentat check`, when its result changes (a first result in the conversation, a different state or a different warning count; a repeat or a reload that leaves it as it was adds none): `✓ mentat check passed`, `! mentat check passed with N warning(s)` or `✕ mentat check failed: N problem(s)`.
  - `↗ Opened PR #<number>` when a `gh pr create` prints a pull request URL (blue).
- An answer whose message enters the session after a `/clear`, `/resume` or `/branch` writes no line into the new log. `note` takes only its five kinds; it refuses an event kind.
- The tool's description tells the agent to add a note only at such a moment, a few an hour at most and never for routine steps, and `rules.md` says the same. Nothing forces it to.

The terminal pane draws no background colors (a terminal shows the alpha tints the desktop uses as opaque grey): its sections are plain text.

The weekly reset is shown in the time zone of the `TZ` environment variable when it is set, otherwise in the zone Claude Code runs in.

## The `mentat check` signal

The mod reads the Bash commands of the main session (not a subagent's) for `mentat check`. A Bash result has no exit code, so it reads the check's final line.

The pane also runs `mentat check` itself, once at session start (a startup or a mod reload, and after `/clear`, `/resume` and a fork, once the label has gone back to dim), in the session's directory and without waiting for a message, so the footer label is current before the agent has run anything. It runs only when that directory is inside a git work tree (`git rev-parse --is-inside-work-tree` prints `true`); elsewhere, such as a folder that is not a repository, it does nothing. A failing check exits 1 and still prints its `Check failed:` line, so its output is read whatever the exit code. If `mentat` cannot be run (it is not on the `PATH`), nothing is recorded and the label stays dim. The result is recorded exactly as the agent's own run is, and the agent's run, which `rules.md` asks for before change work, still updates the label: the later result wins, so a slow startup run never overwrites an agent's run that landed first.

The footer label shows the last result (see above); it is on the terminal and the desktop.

- `Check failed: N problem(s)` pins one alert with that line. The alert has the fixed id `check`: the next failed run replaces it, so there is never more than one, and Dismiss removes it. The `PROBLEM:` lines are not drawn: run `mentat check` to read them.
- `Check OK (N warning(s))` with warnings removes that alert and pins one warning item (amber, `Check passed with N warnings`). It has the fixed id `check` too, so the next run replaces it, it has Dismiss only and no link, and it comes in its place in the order above. The terminal pane draws its `WARN:` lines under it; the desktop band does not. With no warnings, `Check OK (0 warning(s))` removes the alert and the warning item.
- A run with neither final line (an interrupted run, a usage error, output cut by a pipe) changes nothing.

Open items belong to the conversation: a `/clear`, `/resume` or `/branch` drops them all, the check alert and the warning item included, and the footer label goes back to dim. A mod reload keeps both.

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
