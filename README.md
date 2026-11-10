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

<p align="center">
  <img src="docs/images/mentat-checks.svg" alt="A change moves from request to plan, build, review and merge, with Codex and Grok checking along the way and you approving and merging." width="680" height="320">
</p>

<p align="center">
  <img src="docs/images/mentat-parts.svg" alt="Mentat's parts: rules, skills, a builder subagent and hooks inside Claude Code, and the mentat command that runs Codex and Grok." width="680" height="400">
</p>

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
- `/mentat:setup [first-run]`: show and change settings; start with `first-run`.
- `/mentat:linear [project name] [team name]`: move planning from GitHub issues to Linear.
- `/mentat:claude-review`: turn Codex and Grok off; Claude reviews instead.

[`rules.md`](rules.md) has the full workflow.

## Review tools

`mentat second-opinion` runs Codex and Grok on an idea, or with `--web` on a question alone. `--link <item id> <idea file>` records an item as reviewed, so its branch's pull requests skip the second-opinion prompt. A `~/.config/mentat/reviewers` list (`claude`, `codex`, `grok`) replaces them. Claude gets read-only file tools on an idea, web search only with `--web`, and the model in `~/.config/mentat/claude-model`, else the most capable outside the builder's family. `/mentat:setup` changes both files; `mentat check` reports each tool in effect.

## Credits

Third-party licenses are in `skills/*/CREDITS.md`.
