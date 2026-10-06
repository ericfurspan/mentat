# Mentat

How coding agents work in your GitHub repositories: Claude Code builds, Codex reviews, you merge.

Mentat is for one developer on macOS who runs coding agents on their own GitHub repositories. You talk to Claude Code. It plans, builds and opens pull requests. Codex reviews each pull request. You decide what matters, and you merge.

Mentat requires nothing of your repository's GitHub settings. It works within your rules, approvals and CI, and your AGENTS.md wins where it differs. One command turns it on or off.

It ships as a Claude Code plugin: the workflow rules (`rules.md`), an optional output style, a hook that asks you before any merge, a builder subagent and the `mentat` command.

## How a change moves

1. You say what you want, in chat or as an issue.
2. Claude Code plans it, builds it on a branch and opens a draft pull request.
3. Codex reviews the pull request. Claude Code fixes or answers each finding.
4. Claude Code posts a short final check and tells you it is ready.
5. You merge it.

## What you do

- Say what you want, and answer a question when Claude Code asks one.
- Merge pull requests on GitHub.
- Once per repository: turn Mentat on.

## Read more

For you:

- [Turning Mentat on and off](docs/setup.md): what you need, turning it on for a repository, turning it off, and optionally having GitHub enforce the rules.
- [How Mentat works](docs/how-it-works.md): the full flow, what holds and how, the `mentat` commands, and what Mentat does not do.

For agents. You do not need to read these:

- `rules.md`: the workflow rules, loaded into every session.
- `AGENTS.md`: this repository's test command and review rules.
- `agents/builder.md` and `output-styles/mentat.md`: the builder subagent and the reply style.
