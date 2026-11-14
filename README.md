<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

<p align="center"><a href="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml"><img src="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml/badge.svg" alt="tests"></a></p>

Mentat is a Claude Code plugin for building software with multiple AI agents.

Claude Code plans, builds and reviews each change, and you decide what gets built and merge every pull request. With `mentat-reviewers` on in committed settings, Codex reviews every round, Grok the first head. Hooks block an agent's merge and ask you before other risky commands, such as a default-branch push.

## Requirements

- macOS, with Claude Code, `git`, `jq`, and `gh` signed in.
- For `mentat-reviewers`: the Codex CLI, signed in, outside the home folder, and Grok Build (`grok`), signed in with `grok login`.
- Optional: `gitleaks`, to catch secrets before a commit.

## Install

In each repository:

```bash
claude plugin install mentat --marketplace ericfurspan/mentat --scope project
```

This writes `.claude/settings.json`, turning Mentat on for everyone there. Use `--scope local` for only you, or `--scope user` for every folder.

- Update: `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <install scope>`.
- Remove: `claude plugin uninstall mentat@mentat --scope <install scope>`.

Where pull requests need approval, give the agent its own GitHub account.

Optional modules install as `<module>@mentat`:

- `mentat-reviewers`: the Codex and Grok commands.
- `mentat-public-text`: blocks GitHub text holding a home path or a word from `~/.config/mentat/private-words`.
- `mentat-linear`: the Linear backlog adapter and `/mentat-linear:triage [project ... | all] | brainstorm <text or link>`, Inbox triage.
- `mentat-extras`: grill, an interview on open decisions, and `/mentat-extras:retro`, improvements from a session.

## Usage

Ask for a change in chat; Mentat runs the workflow. Work goes Inbox, Backlog, Todo; agreeing to an item's spec commits it, to build now or later. Commands:

- `/mentat:waiting [project ... | all]`: what waits on you, what is next and your unanswered asks.
- `/mentat:propose [item id]`: plan with you and start building what you commit.
- `/mentat:build [item id ...]`: build committed items, one pull request each.
- `/mentat:claude-review`: turn Codex and Grok off; Claude reviews instead.

Moved from core: `status` became `/mentat:waiting` and `plan` became `/mentat:propose`; `triage` went to `mentat-linear`, `grill` and `retro` to `mentat-extras`.

[`rules.md`](rules.md) has the full workflow.

## Configuration

Mentat reads these from AGENTS.md:

- Where the backlog lives: ``The external backlog is the Linear project `<name>`, in team `<team>`.`` (needs `mentat-linear`; else GitHub issues)
- The one test command: ``The one test command is `<command>`.``
- A `## Code Review Rules` section, the rules reviewers apply.

Moving a repository's backlog to Linear is a hand step: [steps](plugins/mentat-linear/skills/linear/SKILL.md#moving-to-linear).

## Review tools

`mentat second-opinion` runs Codex and Grok on an idea, or with `--web` on a question alone. `--link <item id> <idea file>` records an item as reviewed, so its branch's pull requests skip the second-opinion prompt.

## Git hook templates

`git-templates/` hooks refuse likely secrets and non-local default-branch pushes, then run the repository's own except `reference-transaction` and `post-index-change`. Agents' `core.hooksPath` in `GIT_CONFIG_*` names a copy.

## Credits

Skills' `CREDITS.md` files hold third-party licenses.
