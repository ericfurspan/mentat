<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

Mentat is a Claude Code plugin for shipping AI-written code changes through a fixed workflow: Claude Code plans and builds each change on its own branch, a second AI model reviews every pull request, and you merge.

## How a change moves

1. A change starts from a request in chat or a GitHub issue. Claude Code reads the code and records what it will build, what it will leave alone, and how the result will be checked. When the approach is uncertain, it writes a plan and has the reviewer challenge it first.
2. A builder subagent makes the change on a branch and runs the repository's test command. Claude Code opens a pull request with the evidence and the merge risk.
3. `mentat review` waits for CI, then has the reviewer check that exact commit. The reviewer today is OpenAI's Codex, through its GitHub app or CLI; where Grok is installed, it reviews the first head too. Claude Code fixes findings with a realistic trigger, answers the rest with a reason, and repeats until a round comes back clean, up to five rounds.
4. Claude Code posts a final check on the pull request and reports that it is ready.
5. You merge. A hook asks for confirmation before any merge or auto-merge command.

See [How it works](docs/how-it-works.md) for the full flow and the `mentat` commands, and [Setup](docs/setup.md) for requirements and installation.

## Repository layout

| Path | Contents |
| --- | --- |
| `rules.md` | The workflow rules, loaded into every session by a SessionStart hook. |
| `skills/` | One skill per workflow step (`plan`, `pr`, `review`), plus four commands you run by hand. |
| `prompts/` | The builder subagent (`builder.md`: one change on the current branch, then the test command, then a report) and the reply style (`output-style.md`: result first, short, one decision at a time). `plugin.json` points at both. |
| `hooks/` | The SessionStart hook, and hooks that ask before a merge and before a push to the default branch. |
| `bin/mentat` | The `mentat` command: `review`, `review --local`, `review --grok`, `ci`, `challenge` and `check`. It only parses the command and loads `lib/`. |
| `lib/` | The command's code: `shared.sh` (CI wait, pull request and issue reading, review criteria), `codex.sh`, `grok.sh` and `check.sh`. |
| `tests/run` | The test suite. It runs locally on macOS. |
| `docs/` | How it works, setup, and the logo images. |

## Commands

- `/mentat:zoom-out`: a one-time summary of the goal, progress, open questions and the next step. Changes nothing.
- `/mentat:come-again`: restates the last reply in three short lines or fewer.
- `/mentat:retro`: reviews a session and proposes improvements one at a time, with evidence. Agreed ones are filed as issues.
- `/mentat:codex-review-off`: turns the reviewer off for the session. One Claude code review replaces the review loop, and plans are not challenged.

Third-party credits and licenses are in the `CREDITS.md` files under `skills/`.
