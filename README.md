# Mentat

## How a change moves

1. I ask, in chat or as an issue. Claude Code reads the code and writes down what it will build, what it will leave alone and how the result will be checked. When the approach is uncertain, it writes a plan and has Codex challenge it first.
2. A builder subagent makes the change on a branch and runs the repository's test command. Claude Code opens a draft pull request with evidence and the merge risk.
3. `mentat review` waits for CI, then Codex reviews that exact commit, through OpenAI's Codex GitHub app or local Codex. Claude Code fixes findings that have a realistic trigger, answers the rest with a reason, and reviews again until the loop is clean. Five rounds is a hard stop.
4. Claude Code posts a final check and tells me the pull request is ready. If I said to hold the change, it stays a draft and nothing reviews it until I say it goes to main.
5. I merge. A hook asks me before any command that would merge or turn on auto-merge.

The full flow, what holds and how, the `mentat` commands and what Mentat does not do: [docs/how-it-works.md](docs/how-it-works.md). What my machine and repositories need, and the plugin commands I run: [docs/setup.md](docs/setup.md).

## What is in this repository

| Path | What it is |
| --- | --- |
| `rules.md` | The workflow rules, put into every session by a SessionStart hook. |
| `skills/` | One skill per workflow step (`plan`, `pr`, `review`), called from `rules.md`, and three I start by hand (below). |
| `agents/builder.md` | The builder subagent: one change on the current branch, then the test command, then a report. |
| `output-styles/mentat.md` | The reply style: result first, about 100 words, decisions as prompts when the answers fit a few options, otherwise ❓/💡 pairs at the end. |
| `hooks/` | The SessionStart hook that loads the rules, and the PreToolUse hook that asks before a merge. |
| `bin/mentat` | `mentat review`, `review --local`, `ci`, `challenge` and `check`, available to Claude Code's Bash tool. |
| `tests/run` | The one test command. It runs locally on macOS; there is no CI. |
| `docs/` | How it works, and setup. |

## What I start by hand

- `/mentat:zoom-out`: the whole picture, once. The goal, what is done, what I raised that is still unanswered, what looks like over-engineering, and the next step. Changes nothing.
- `/mentat:come-again`: the last message again, in at most three short lines.
- `/mentat:codex-review-off`: Codex off for the session. One Claude `code-review` per pull request replaces the Codex loop, with no plan challenges; the final check says so. Weaker than a cross-model review, which is why it is a switch and not the default. I turn Codex back on in chat.
- `/grilling` (Matt Pocock's) and `/the-fool` (Jeffallan's) are other people's skills I keep installed; Mentat offers them when a request leaves decisions open or a plan deserves a skeptic.

## Credits

The pull request body format comes from Matt Pocock's `pr` skill, the ❓/💡 decision format from his `grilling`, and zoom-out's reframing question from team-attention's `step-back` and the BMAD Method. Each `CREDITS.md` under `skills/` has the details and licenses.
