<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

<p align="center"><a href="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml"><img src="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml/badge.svg" alt="tests"></a></p>

Mentat is a Claude Code plugin for building software with multiple AI agents.

Claude Code plans and builds each change, Codex and Grok give second opinions and review code, and you decide what gets built and merge every pull request. Hooks ask you before risky commands, such as a merge or a push to the default branch.

`rules.md` loads at session start, skills guide each step, and a builder subagent edits on a branch.

## Requirements

- macOS, with Claude Code, `git`, `jq`, and `gh` signed in.
- For reviews: the Codex CLI, signed in, installed outside the home folder.
- Optional: Grok Build (`grok`), signed in with `grok login`, for a second review.
- Optional: `gitleaks`, to catch secrets before a commit.

The builder subagent runs on Opus, which costs more.

## Install

In each repository:

```bash
claude plugin install mentat --marketplace ericfurspan/mentat --scope project
```

This writes `.claude/settings.json`, turning Mentat on for everyone there. Use `--scope local` for only you, or `--scope user` for every folder.

- Update: `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <install scope>`.
- Remove: `claude plugin uninstall mentat@mentat --scope <install scope>`.

Where pull requests need approval, give the agent its own GitHub account.

## Usage

Ask for a change in chat and Mentat runs the workflow. Work goes Inbox, Backlog, Todo; agreeing to an item's spec commits it, to build now or later. Commands:

- `/mentat:status [project ... | all]`: what waits on you, what is next and your unanswered asks.
- `/mentat:triage [project ... | all] | brainstorm <text or link>`: go through the Inbox with you.
- `/mentat:plan [item id]`: plan with you and start building what you commit.
- `/mentat:build [item id ...]`: build committed items, one pull request each.
- `/mentat:retro`: propose improvements from a session.
- `/mentat:claude-review`: turn Codex and Grok off; Claude reviews instead.

[`rules.md`](rules.md) has the full workflow.

## Configuration

Mentat reads these from AGENTS.md:

- Where the backlog lives: ``The external backlog is the Linear project `<name>`, in team `<team>`.`` (else GitHub issues)
- The one test command: ``The one test command is `<command>`.``
- A `## Code Review Rules` section, the rules reviewers apply.

Moving a repository's backlog to Linear is a hand step: [steps](skills/backlog/linear.md#moving-to-linear).

## Review tools

`mentat second-opinion` runs Codex and Grok on an idea, or with `--web` on a question alone. `--link <item id> <idea file>` records an item as reviewed, so its branch's pull requests skip the second-opinion prompt. `mentat check` reports each tool.

## Credits

Third-party licenses are in `skills/*/CREDITS.md`.
