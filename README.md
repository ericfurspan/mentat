# Mentat

How coding agents work in your GitHub repositories: you decide, Claude Code builds, Codex reviews, you merge (or let the agent merge, where you opt in).

Mentat is for one developer on macOS who runs coding agents on their own GitHub repositories. You and Claude Code work out what to build: it reads the code, asks what it needs, pushes back where it should, and brings you the decisions that are yours. Then it builds and opens pull requests, Codex reviews each one, and you merge.

Mentat requires nothing of your repository's GitHub settings. It works within your rules, approvals and CI, and your AGENTS.md wins on preferences such as commit format and branch flow. One command turns it on or off.

It ships as a Claude Code plugin: the workflow rules (`rules.md`), an optional output style, a hook that asks you before the agent merges a pull request or turns on auto-merge (with one narrow exception in a repository you opted in; see [Letting agents merge](docs/setup.md#letting-agents-merge)), a builder subagent, skills for planning, writing pull request descriptions, the review loop and session retrospectives, and the `mentat` command.

## How a change moves

1. You say what you want, in chat or as an issue. Claude Code reads the code, asks what it needs and writes down what it will build.
2. Claude Code builds it on a branch and opens a draft pull request.
3. Codex reviews the pull request. Claude Code fixes or answers each finding.
4. Claude Code posts a short final check and tells you it is ready.
5. You merge it, or, in a repository you opted in, Claude Code merges it.

## What you do

- Decide what to build and what matters, with Claude Code advising.
- Merge pull requests on GitHub.
- When a session went badly, run `/mentat:retro` in Claude Code: it reads the session and proposes fixes to the setup, and changes nothing until you approve.
- When a message loses you, run `/mentat:come-again` in Claude Code: it says the last message again in three short lines, or the part you typed after the command, and changes nothing.
- When you want the whole picture, run `/mentat:zoom-out` in Claude Code: it steps back once and says the goal, what is done, what you raised that is still unanswered, what looks like over-engineering, and the next step, and changes nothing.
- When you want to settle a plan before work starts, run `/grilling` in Claude Code: it is Matt Pocock's skill, installed separately (see `docs/setup.md`), and it interviews you about a plan until you agree on it.
- To skip Codex for a session, run `/mentat:codex-review-off`: one Claude `code-review`, asked for at medium effort, per pull request (at most two rounds), no plan challenges, a final check marked reviewed by Claude, not Codex, and you still merge every pull request. If `code-review` cannot run, the final check says "Not reviewed" and why. Claude is the same model family as the builder, so this review is weaker than a cross-model one. Run `/mentat:codex-review-on`, or say so in chat, to turn Codex back on.
- Once per repository: turn Mentat on.

## Plugin commands

Run these in a terminal, in the checkout. Pick one scope: `local` is only you in this checkout (it writes `.claude/settings.local.json`, which git ignores), `project` is everyone who clones it (it writes `.claude/settings.json`, which you commit), `user` is every folder you open, so Mentat then runs in every repository.

| What you want | Command |
| --- | --- |
| Add the marketplace (once per machine) | `claude plugin marketplace add ericfurspan/mentat` |
| Turn Mentat on for you, in this checkout | `claude plugin install mentat@mentat --scope local` |
| Turn it on in the repository (each clone installs it once) | `claude plugin install mentat@mentat --scope project` |
| Turn it on in every folder | `claude plugin install mentat@mentat --scope user` |
| Update | `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <scope>`, then `/reload-plugins` in a running session; the updated rules load at the next session start, resume, `/clear` or compaction |
| Turn it off | `claude plugin disable mentat@mentat` |
| Turn it back on | `claude plugin enable mentat@mentat` |
| Remove it | `claude plugin uninstall mentat@mentat --scope <scope>` |
| See where Mentat is installed, and at which scope | `claude plugin list` |

Details, and what each command leaves behind, are in [Turning Mentat on and off](docs/setup.md).

## Read more

For you:

- [Turning Mentat on and off](docs/setup.md): what you need, turning it on for a repository, turning it off, and optionally having GitHub enforce the rules.
- [How Mentat works](docs/how-it-works.md): the full flow, what holds and how, the `mentat` commands, and what Mentat does not do.

For agents. You do not need to read these:

- `rules.md`: the workflow rules, loaded into every session.
- `AGENTS.md`: this repository's test command and review rules.
- `skills/`: one skill per workflow step (plan, pr, review), called from `rules.md`, and `retro`, `codex-review-off`, `codex-review-on`, `come-again` and `zoom-out`, which you start.
- `agents/builder.md` and `output-styles/mentat.md`: the builder subagent and the reply style.
