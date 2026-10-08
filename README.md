# Mentat

How coding agents work in your GitHub repositories: you decide, Claude Code builds, Codex reviews, you merge (or let the agent merge, where you opt in).

Mentat is for one developer on macOS who runs coding agents on their own GitHub repositories. You and Claude Code work out what to build: it reads the code, asks what it needs, pushes back where it should, and brings you the decisions that are yours. Then it builds and opens pull requests, Codex reviews each one, and you merge.

Mentat requires nothing of your repository's GitHub settings. It works within your rules, approvals and CI, and your AGENTS.md wins on preferences such as commit format and branch flow. One command turns it on or off.

It ships as a Claude Code plugin: the workflow rules (`rules.md`), an optional output style, a hook that asks you before the agent merges a pull request, unless you opted the repository in, or turns on auto-merge, a builder subagent, skills for planning, writing pull request descriptions, the review loop and session retrospectives, a decisions pane that lists the questions waiting on you, and the `mentat` command.

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
- To skip Codex for a session, run `/mentat:no-review`: no pull request reviews and no plan challenges, and you merge every pull request. Say so in chat to turn Codex back on.
- Once per repository: turn Mentat on.

## Read more

For you:

- [Turning Mentat on and off](docs/setup.md): what you need, turning it on for a repository, turning it off, and optionally having GitHub enforce the rules.
- [How Mentat works](docs/how-it-works.md): the full flow, what holds and how, the `mentat` commands, and what Mentat does not do.

For agents. You do not need to read these:

- `rules.md`: the workflow rules, loaded into every session.
- `AGENTS.md`: this repository's test command and review rules.
- `skills/`: one skill per workflow step (plan, pr, review), called from `rules.md`, and `retro` and `no-review`, which you start.
- `agents/builder.md` and `output-styles/mentat.md`: the builder subagent and the reply style.
