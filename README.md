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

Left alone, AI agents drift from requests, review their own work and merge mistakes. With Mentat, work follows a spec you plan with Claude, fresh reviewers check it, and only you merge.

## Main ideas

- Orchestrator (`mentat-lead`): the one session you talk to (`/mentat-lead:orchestrate`), handing agreed items to implementation sessions where its host can start and message them.
- Implementation session: one pull request per agreed item.
- Handover (`mentat-lead`): an item with its spec's fingerprint, taken only if unchanged.
- Grill (`mentat-lead`): an interview on your open decisions.
- Plan check: a fresh agent checks most plans before agreement.
- [Fast track](skills/review/SKILL.md#fast-track): if you agree, only a diff that clearly cannot alter code behavior or agents' instructions skips review.
- Review rounds: fresh Claude reviews each head, within a limit; outside reviewers (`mentat-reviewers`) review heads with nothing left to push.
- Safety nets: a hook blocks agents' merges; [opt-in](docs/setup.md#git-hooks) git hooks refuse likely secrets and non-local default-branch pushes. `mentat-public-text` blocks listed GitHub writes holding home paths or private words.
- `mentat-linear`: the Linear adapter and any backlog's Inbox triage ([`/mentat-linear:triage`](docs/settings.md#module-commands)).

[Architecture](docs/architecture.md).

## Requirements

- macOS, Claude Code 2.1.295 or later, `git`, `jq`, and `gh` signed in.
- For `mentat-reviewers`: each listed reviewer's command, signed in: Codex CLI, [outside the home folder](docs/setup.md#codex-outside-the-home-folder).
- For the git hooks: `gitleaks` ([setup](docs/setup.md#git-hooks)).

## Install

Per repository:

```bash
claude plugin install mentat --marketplace ericfurspan/mentat --scope project
```

This writes `.claude/settings.json`, turning Mentat on for everyone there (`--scope local`: only you; `--scope user`: every folder).

- Update: `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <install-scope>` (re-copy any [git hooks](docs/setup.md#git-hooks)).
- Remove: `claude plugin uninstall mentat@mentat --scope <install-scope>`.

Where pull requests need approval, give the agent a separate GitHub account.

Optional modules install as `<module>@mentat`: `mentat-reviewers`, `mentat-public-text`, `mentat-lead` and `mentat-linear`.

## Usage

Ask for a change in chat; agreeing to its spec commits it to Todo, [to implement now or later](skills/plan/SKILL.md#starting-implementation). Filed ideas wait in Inbox or Backlog.

- `/mentat:plan [item id]`: plan an item together.
- `/mentat:build [item id ...]`: implement committed items.

[`rules.md`](rules.md) holds core rules, `skills/` step details.

## Configuration

[docs/settings.md](docs/settings.md) lists [the AGENTS.md lines Mentat reads](docs/settings.md#agentsmd-lines), every setting, review tools included, and [breaking changes](docs/settings.md#breaking-changes).

## Credits

Skills' `CREDITS.md` files credit sources; some hold third-party licenses.
