# This repository

*Read by agents. For people: `README.md` and `docs/`.*

This repository is Mentat itself: a Claude Code plugin (`.claude-plugin/`), its workflow rules (`rules.md`, loaded at session start by `hooks/session-start`), its output style (`output-styles/`), its builder subagent (`agents/`) and the `mentat` command (`bin/mentat`). Its committed `.claude/settings.json` turns the plugin on here, so sessions in this repository follow `rules.md`.

- The one test command is `tests/run`. It runs on macOS and in CI on Linux.
- Every file here is Mentat's own. This repository's own choices, which Mentat inherits like any other: every pull request needs the maintainer's Approve (a ruleset on `main` requiring one approval; the agent account cannot approve its own pull requests), CI runs `tests/run`, and `.claude/settings.json` chooses the Mentat output style.
- Keep scripts plain bash that also runs on macOS's bash 3.2.
- After the maintainer merges a pull request here, run `claude plugin marketplace update mentat` and `claude plugin update mentat@mentat --scope project`, so the next session loads the merged plugin. Then, in every other checkout that has Mentat installed, run `claude plugin update mentat@mentat --scope <scope>` with the scope `~/.claude/plugins/installed_plugins.json` lists for it under `mentat@mentat` (`local`, `project` or `user`; run `user` once, from any directory). Skip a project-scope checkout that is not on its default branch and say so: there the command can leave an untracked settings file. The maintainer gave standing permission for these commands. A running session keeps the version it loaded until it restarts.

## Code Review Rules
- The requirements are in the pull request description and any linked issue. Flag code that does not do what they say, or a test result that does not match the final commit.
- Flag any secret, token or credential added to the repository, including in tests, fixtures and workflow files. Placeholder values that are clearly fake are fine.
- Flag workflow changes that give a job secrets, write permissions or deploy access it does not need. Workflows should declare `permissions` explicitly and pin third-party actions to a commit SHA.
- Flag changes that weaken a guardrail: skipping or loosening `tests/run`, narrowing the merge hook (`hooks/no-merge`) so a plain `gh pr merge` no longer prompts, or instructions that let an agent deploy, publish, release or merge without required review.
- Flag shell scripts that break on paths with spaces, ignore a failing command, or behave differently on macOS and Linux without saying so.
- Do not flag wording or style in Markdown instructions unless it changes what an agent is told to do.
- The merge hook is a net for mistakes, not a security boundary: another command form that would merge without a prompt is not a finding.
- Flag only problems with a realistic trigger. A check that fails closed is not a finding, and neither is input that needs a broken or hostile setup on the maintainer's own machine. Prefer removing code to adding guards.
