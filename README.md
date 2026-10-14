<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

Mentat is a Claude Code plugin for a multi-agent coding workflow with the maintainer in the loop: a change is worked out in an interactive session, with Codex and Grok on call for independent second opinions, built and tested by a builder subagent on its own branch, reviewed by Codex and Grok, and merged by the maintainer.

## Install

```bash
claude plugin install mentat --marketplace ericfurspan/mentat
```

This adds the marketplace and installs the plugin. It needs macOS and Claude Code 2.1.292 or later (older versions: `claude plugin marketplace add ericfurspan/mentat`, then `claude plugin install mentat@mentat`), plus `git`, `jq` and `gh` signed in. For reviews it needs OpenAI's Codex GitHub app on the repository (a ChatGPT plan with Codex code review) or the Codex CLI signed in; Grok Build is optional. [Setup](docs/setup.md) covers scopes and updates.

## How a change moves

1. A change starts from a request in chat or a GitHub issue. Claude Code reads the code and gives the maintainer its view of the request; for a new feature or workflow idea, Codex and Grok also weigh it (`mentat weigh`) and their verdicts come beside its own. Once the maintainer agrees, it records what it will build, what it will leave alone, and how the result will be checked. When the approach is uncertain, it writes a plan and has the reviewer challenge it first.
2. A builder subagent, given a written brief (what to build, what to leave alone, how it is checked), makes the change on a branch and runs the repository's test command. Claude Code opens a pull request with the evidence and the merge danger.
3. `mentat review` waits for CI, then has the reviewer check that exact commit (its head). The reviewer today is OpenAI's Codex, through its GitHub app or CLI; where Grok is installed, it reviews the first head too. Claude Code fixes findings with a realistic trigger and answers the rest with a reason, and reviews again; the loop ends ready when a round is clean or every finding is fixed or answered, and stops after at most five rounds. Both reviewers see only the change: see [How it works](docs/how-it-works.md).
4. Claude Code posts a final check on the pull request and reports that it is ready.
5. The maintainer merges. A hook asks for confirmation before any merge or auto-merge command.

See [How it works](docs/how-it-works.md) for the full flow and the `mentat` commands, and [Setup](docs/setup.md) for requirements and installation.

## Repository layout

| Path | Contents |
| --- | --- |
| `rules.md`, `rules-records.md` | The workflow rules in two files, both loaded into every session by SessionStart hooks. |
| `skills/` | One skill per workflow step (`plan`, `pr`, `review`), plus four commands the maintainer runs by hand. |
| `prompts/` | The builder subagent (`builder.md`: one change on the current branch, then the test command, then a report) and the reply style (`output-style.md`: result first, short, one decision at a time). `plugin.json` points at both. |
| `hooks/` | The SessionStart hook, and hooks that ask before a merge and before a push to the default branch. |
| `bin/mentat` | The `mentat` command: `review`, `review --local`, `review --grok`, `ci`, `challenge`, `weigh` and `check`. It only parses the command and loads `lib/`. |
| `lib/` | The command's code: `shared.sh` (CI wait, pull request and issue reading, review criteria), `codex.sh`, `grok.sh`, `weigh.sh` (`mentat weigh`) and `check.sh`. |
| `tests/run` | The test suite. It runs locally on macOS. |
| `docs/` | How it works, setup, the design decisions and their evidence (`design.md`), and the logo images. |

## Commands

- `/mentat:zoom-out`: a one-time summary of the goal, progress, open questions and the next step. Changes nothing.
- `/mentat:come-again`: restates the last reply in three short lines or fewer.
- `/mentat:retro`: reviews a session and proposes improvements one at a time, with evidence. Agreed ones are filed as issues.
- `/mentat:codex-review-off`: turns the reviewer off for the session. One Claude code review replaces the review loop, and plans are not challenged or ideas weighed.

Third-party credits and licenses are in the `CREDITS.md` files under `skills/`.
