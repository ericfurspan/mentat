# This repository

*Read by agents. For people: `README.md` and `docs/`.*

This repository is Mentat itself: a Claude Code plugin (`.claude-plugin/`), its workflow rules (`rules.md`, loaded at session start by `hooks/session-start`), its skills (`skills/`, one per workflow step, named from `rules.md`), its builder subagent (`prompts/builder.md`) and the `mentat` command (`bin/mentat`, which loads `lib/*.sh`: `shared.sh`, `publish.sh`, `codex.sh`, `grok.sh`, `parallel.sh`, `weigh.sh`, `consult.sh`, `check.sh`). Mentat is on here through the maintainer's user-scope install, so sessions in this repository follow `rules.md`.

- The one test command is `tests/run`. It takes about 80 seconds, so run it once with its output saved to a file and read the last line ("All checks passed" or "N check(s) failed"). It runs locally on macOS, and on GitHub Actions (macOS) for every pull request.
- The external backlog is the Linear project `Mentat`, in team `Work`.
- Working files (plans, audits, trial kits) go in `work/`, which git ignores; finished ones move to `work/done/`. Nothing there is part of the plugin.
- Every file here is Mentat's own. This repository's own choices, which Mentat inherits like any other: the maintainer merges every pull request (the agent account cannot approve its own pull requests).
- Keep scripts plain bash that also runs on macOS's bash 3.2.
- Weigh a change to Mentat on its value against its cost, whether the idea comes from a real session or from others' work, and keep it simple to describe.
- After the maintainer merges a pull request here, run `claude plugin marketplace update mentat` and `claude plugin update mentat@mentat --scope user`, so the next session here loads the merged plugin. The maintainer gave standing permission for these two commands. A running session keeps the version it loaded until it restarts. Other checkouts update whenever they next update their plugins; nothing here depends on it.

## Code Review Rules
- The requirements are in the pull request description and any linked issue. Flag code that does not do what they say, or a test result that does not match the final commit.
- Flag any secret, token or credential added to the repository, including in tests, fixtures and workflow files. Placeholder values that are clearly fake are fine.
- Flag workflow changes that give a job secrets, write permissions or deploy access it does not need. Workflows should declare `permissions` explicitly and pin third-party actions to a commit SHA.
- Flag changes that weaken a guardrail: skipping or loosening `tests/run`, narrowing the merge hook (`hooks/no-merge`) so a merge command prompts less (`gh pr merge`, the merge API through `gh api` and auto-merge always prompt), or instructions that let an agent deploy, publish or release, or merge at all, including through auto-merge or `--admin`; narrowing the push hook (`hooks/no-default-push`) so a push to the default branch prompts less; narrowing the private text hook (`hooks/no-private-text`) so a listed `gh` write with a hit prompts less.
- Flag shell scripts that break on paths with spaces or ignore a failing command.
- Do not flag wording or style in Markdown instructions unless it changes what an agent is told to do.
- The merge, push and private text hooks are nets for mistakes, not security boundaries: another command form that would merge, push to the default branch or publish a hit without a prompt is not a finding.
- Flag only problems with a realistic trigger. A check that fails closed is not a finding, and neither is input that needs a broken or hostile setup on the maintainer's own machine. Prefer removing code to adding guards.
