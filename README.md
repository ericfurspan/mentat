<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

<p align="center"><a href="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml"><img src="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml/badge.svg" alt="tests"></a></p>

Mentat is a Claude Code plugin for building software with multiple AI agents.

<!-- flow picture -->
<!-- demo -->

## Why

Left alone, AI agents drift from your request, review their own work and merge mistakes. With Mentat you plan with Claude and agree each spec, fresh reviewers check the work, and only you merge.

## Main ideas

- Orchestrator (`mentat-lead`): the one session you talk to (`/mentat-lead:orchestrate`), handing agreed items to implementation sessions.
- Implementation session: implements agreed items, one pull request each.
- Handover: an item passed on with its spec's fingerprint, taken only if unchanged.
- Grill (`mentat-lead`): an interview on your open decisions.
- Plan check: a fresh agent checks most plans before agreement.
- Fast track: changes that cannot alter what code does or agents are told skip review, if you agree.
- Review rounds: fresh Claude reviews each head, up to a round limit, then outside reviewers (`mentat-reviewers`).
- Safety nets: a hook blocks agents' merges; git hooks ([setup](docs/setup.md#git-hooks)) refuse likely secrets and non-local default-branch pushes. `mentat-public-text` blocks GitHub text holding a home path or private word.

[How it works](docs/architecture.md).

## Requirements

- macOS, with Claude Code 2.1.295 or later, `git`, `jq`, and `gh` signed in.
- For `mentat-reviewers`: each listed reviewer's command, signed in: the Codex CLI, [outside the home folder](docs/setup.md#codex-outside-the-home-folder); Grok Build (`grok login`).
- For the git hooks: `gitleaks` ([setup](docs/setup.md#git-hooks)).

## Install

In each repository:

```bash
claude plugin install mentat --marketplace ericfurspan/mentat --scope project
```

This writes `.claude/settings.json`, turning Mentat on for everyone there (`--scope local`: only you; `--scope user`: every folder).

- Update: `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <install scope>` (and re-copy [git hooks](docs/setup.md#git-hooks) if used).
- Remove: `claude plugin uninstall mentat@mentat --scope <install scope>`.

Where pull requests need approval, give the agent its own GitHub account.

Optional modules install as `<module>@mentat`: `mentat-reviewers`, `mentat-public-text`, `mentat-lead` and `mentat-linear` (the Linear adapter and any backlog's Inbox triage, [`/mentat-linear:triage`](docs/settings.md#module-commands)).

## Usage

Ask for a change in chat. Work goes Inbox, Backlog, Todo; agreeing to an item's spec commits it, to implement now or later.

- `/mentat:plan [item id]`: plan together and start implementing what you commit.
- `/mentat:build [item id ...]`: implement committed items.

[`rules.md`](rules.md) holds the core rules, `skills/` each step's detail.

## Configuration

[docs/settings.md](docs/settings.md) lists [the AGENTS.md lines Mentat reads](docs/settings.md#agentsmd-lines), every setting and [breaking changes](docs/settings.md#breaking-changes).

## Credits

Skills' `CREDITS.md` files credit their sources; some hold third-party licenses.
