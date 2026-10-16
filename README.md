<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

<p align="center"><a href="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml"><img src="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml/badge.svg" alt="tests"></a></p>

Mentat is a Claude Code plugin that runs a multi-agent coding workflow on a GitHub repository. The repository's maintainer requests a change. Claude Code proposes a plan, with Codex and Grok weighing in on new ideas, and a builder makes the change once the maintainer agrees. Codex reviews the pull request after every fix, Grok adds a second review where it is installed, and a hook asks the maintainer before any merge. Along the way, the maintainer can step back with `/mentat:zoom-out`, put one question to several models with `/mentat:consult`, and review a session for improvements with `/mentat:retro`.

<p align="center">
  <img src="docs/images/mentat-checks.svg" alt="A change moves from request to plan, build, review and merge. Codex and Grok give a second opinion on the request, Codex critiques the plan, and both review the code. The maintainer asks for the change, approves the plan and merges." width="680" height="320">
</p>

## What you get

- Other vendors' models on every change: Codex is the main reviewer, reviewing every pull request after each fix and challenging an uncertain plan. Grok, where installed, gives a second view: it weighs new ideas beside Codex and reviews each pull request once.
- One builder per change, on its own branch: the chat shows plans and reports, not diffs.
- Hooks that ask before a merge or a push to the default branch. The maintainer merges.

## How a change moves

1. A request in chat or an issue. Claude Code reads the code and gives its view; for a new feature or a workflow change, Codex and Grok weigh it too (`mentat weigh`). The maintainer agrees on what gets built.
2. A builder subagent makes the change on a branch and runs the test command.
3. Claude Code opens a pull request. `mentat review` waits for CI, then Codex reviews the head commit, and Grok the first one. Findings with a realistic trigger are fixed, the rest answered with a reason, for at most five rounds.
4. Claude Code posts a final check on the pull request and reports it ready.
5. The maintainer merges.

[How it works](docs/how-it-works.md) has the full flow.

## Requirements

- macOS, Claude Code, `git`, `jq`, and `gh` signed in.
- For reviews: OpenAI's Codex GitHub app on the repository, or the Codex CLI signed in.
- Optional: Grok Build (`grok`), for a second review and a second view in `mentat weigh`.

## Install

```bash
claude plugin install mentat --marketplace ericfurspan/mentat
```

[Setup](docs/setup.md) has the plugin commands and the review setup.

## Commands

The `mentat` command (`review`, `challenge`, `weigh`, `consult`, `check`) runs from Claude Code's shell; [How it works](docs/how-it-works.md) lists each with its exit codes.

- `/mentat:zoom-out`: a one-time summary of the goal, progress, open questions and the next step. Changes nothing.
- `/mentat:come-again`: restates the last reply in three short lines or fewer.
- `/mentat:retro`: reviews a session and proposes improvements one at a time, with evidence. Agreed ones are filed as issues.
- `/mentat:consult <question>`: consults Codex, Grok and Claude Code on any question, with the web, and answers in five short lines at most: the consensus first, then what each model adds. Runs anywhere, no repository needed.
- `/mentat:codex-review-off`: turns Codex off for the session, and Grok's review with it. One Claude code review replaces the review loop, and plans are not challenged or ideas weighed.

## Docs and credits

- [How it works](docs/how-it-works.md): the full flow, the hooks, the commands.
- [Setup](docs/setup.md): what a machine needs, the plugin commands, the review setup.
- Third-party credits and licenses: the `CREDITS.md` files under `skills/`.
