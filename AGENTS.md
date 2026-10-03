# This repository

This repository is Mentat itself: a Claude Code plugin (`.claude-plugin/`), its workflow rules (`rules.md`, loaded at session start by `hooks/session-start`), its output style (`output-styles/`), its builder subagent (`agents/`) and the `mentat` command (`bin/mentat`). Its committed `.claude/settings.json` turns the plugin on here, so sessions in this repository follow `rules.md`.

- The one test command is `scripts/test`. It runs on macOS and in CI on Linux.
- Every file here is Mentat's own, so every pull request waits for the maintainer's Approve (`.github/CODEOWNERS`).
- Keep scripts plain bash that also runs on macOS's bash 3.2.

## Code Review Rules
- The requirements are in the pull request description and any linked issue. Flag code that does not do what they say, or a test result that does not match the final commit.
- Flag any secret, token or credential added to the repository, including in tests, fixtures and workflow files. Placeholder values that are clearly fake are fine.
- Flag workflow changes that give a job secrets, write permissions or deploy access it does not need. Workflows should declare `permissions` explicitly and pin third-party actions to a commit SHA.
- Flag changes that weaken a guardrail: removing or narrowing `.github/CODEOWNERS`, skipping or loosening `scripts/test`, or instructions that let an agent deploy, publish, release or merge without required review.
- Flag shell scripts that break on paths with spaces, ignore a failing command, or behave differently on macOS and Linux without saying so.
- Do not flag wording or style in Markdown instructions unless it changes what an agent is told to do.
