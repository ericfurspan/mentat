<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

<p align="center"><a href="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml"><img src="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml/badge.svg" alt="tests"></a></p>

Mentat is a Claude Code plugin for building software with multiple AI agents.

Claude Code plans, builds and reviews each change; you decide what gets built and merge every pull request. With `mentat-reviewers` on, the outside reviewers a repository lists review each head Claude finds clean. A hook blocks an agent's merge; where set up, git hooks refuse its default-branch pushes and likely secrets.

## Requirements

- macOS, with Claude Code, `git`, `jq`, and `gh` signed in.
- For `mentat-reviewers`: each listed reviewer's command, signed in: the Codex CLI, outside the home folder; Grok Build (`grok login`).
- For the git hooks: `gitleaks`.

## Install

In each repository:

```bash
claude plugin install mentat --marketplace ericfurspan/mentat --scope project
```

This writes `.claude/settings.json`, turning Mentat on for everyone there (`--scope local`: only you; `--scope user`: every folder).

- Update: `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <install scope>`.
- Remove: `claude plugin uninstall mentat@mentat --scope <install scope>`.

Where pull requests need approval, give the agent its own GitHub account.

Optional modules install as `<module>@mentat`:

- `mentat-reviewers`: outside reviewers; Codex and Grok ship.
- `mentat-public-text`: blocks GitHub text holding a home path or a word from `~/.config/mentat/private-words`.
- `mentat-linear`: the Linear adapter, and any backlog's Inbox triage: `/mentat-linear:triage [project ... | all] | brainstorm <text or link>`.
- `mentat-lead`: grill, an interview on open decisions, `/mentat-lead:retro`, improvements from a session, and `/mentat-lead:orchestrate`, which plans work and hands each batch to a fresh build session.

## Usage

Ask for a change in chat; Mentat runs the workflow. Work goes Inbox, Backlog, Todo; agreeing to an item's spec commits it, to build now or later. Commands:

- `/mentat:plan [item id]`: plan with you and start building what you commit.
- `/mentat:build [item id ...]`: build committed items, one pull request each.

[`rules.md`](rules.md) holds the core rules, `skills/` each step's detail.

## Configuration

Mentat reads from AGENTS.md:

- Where the backlog lives: ``The external backlog is the Linear project `<name>`, in team `<team>`.`` (needs `mentat-linear`; else GitHub issues)
- The one test command: ``The one test command is `<command>`.``
- A `## Code Review Rules` section, the rules reviewers apply.

[docs/settings.md](docs/settings.md) lists every setting, with its default and where to set it.

Moving a backlog to Linear is manual: [steps](plugins/mentat-linear/skills/linear/SKILL.md#moving-to-linear).

## Review tools

Breaking: `mentat-reviewers` needs a list: `"env": {"MENTAT_REVIEWERS": "codex,grok"}`, read only from the default branch's `.claude/settings.json`. `MENTAT_REVIEW_TIMEOUT_SECONDS` (1800; a whole number from 1, never empty) limits every reviewer; `mentat check` warns while the unread `MENTAT_GROK_TIMEOUT_SECONDS` is set. `mentat second-opinion` runs the list on an idea.

## Git hooks

The hooks in `git-hooks/` refuse likely secrets and non-local default-branch pushes, then run the repository's own except `reference-transaction` and `post-index-change`. Both guards hold only where agents' `core.hooksPath` in `GIT_CONFIG_*` names a copy; `mentat check` reports their state.

## Credits

Skills' `CREDITS.md` files credit their sources, and only some hold third-party licenses.
