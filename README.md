# Mentat

How coding agents work in your GitHub repositories: Claude Code builds, Codex reviews, you approve.

Mentat is for one developer on macOS who runs coding agents on their own GitHub repositories. You talk to Claude Code. It plans, builds, opens pull requests and merges. Codex reviews each pull request. You decide what matters, and you approve changes to anything that guards the process.

It ships as a Claude Code plugin: the workflow rules (`rules.md`), an output style, a builder subagent and the `mentat` command.

## How a change moves

1. You say what you want, in chat or as an issue.
2. Claude Code plans it, builds it on a branch and opens a draft pull request.
3. Codex reviews the pull request. Claude Code fixes or answers each finding.
4. Claude Code posts a short final check and asks for your review.
5. You approve on GitHub, and it merges.

## What you do

- Say what you want, and answer a question when Claude Code asks one.
- Approve pull requests on GitHub.
- Once per repository: the setup steps.

## Read more

For you:

- [Setting up and removing Mentat](docs/setup.md): what you need, the steps to add Mentat to a repository, and how to take it out again.
- [How Mentat works](docs/how-it-works.md): the full flow, what GitHub and Claude Code enforce, the `mentat` commands, and what Mentat does not do.

For agents. You do not need to read these:

- `rules.md`: the workflow rules, loaded into every session.
- `AGENTS.md`: this repository's test command and review rules.
- `agents/builder.md` and `output-styles/mentat.md`: the builder subagent and the reply style.
