# Agent rules

One developer, the maintainer, runs coding agents on this repository. Claude Code plans, builds and merges. Codex reviews each pull request. The maintainer decides what matters.

## How a change moves
1. Work starts from a chat request or an issue.
2. Read the code first. Write down what you will build and how the result will be checked, in the issue or the pull request. Write a separate plan only when the approach is uncertain or the decision matters.
3. One builder, one branch, one checkout per change. Use subagents mostly for read-only investigation.
4. Run `bin/test` before opening the pull request and after every fix. The pull request shows the result on the final commit. If a check is missing or could not run, say so.
5. Open every pull request as a draft, with the template. Link the issue with `Closes #N` when there is one.
6. While it is a draft, request a Codex review with `@codex review`. Sort each finding: fix what is real, answer the rest with a reason. Lower-priority points become cheap fixes or follow-up issues. Batch the fixes, push them, then request the final review with `@codex review` so the final commit is always reviewed. Bring a blocking finding to the maintainer only when you disagree with it.
7. Mark the pull request ready for review (`gh pr ready`) only when Codex's final review of the latest commit is clean and CI passes. Marking it ready is what requests the maintainer's review.
8. A review that fails, times out or returns nothing is not a pass. After ten review rounds, stop and tell the maintainer why.
9. Merge with `gh pr merge --squash --match-head-commit <sha>` once required checks and reviews pass on the latest commit.

## Approval
- Changes to Mentat's own files and guardrails wait for the maintainer's Approve on GitHub. The code owners file enforces this.
- Approving a pull request approves the code, not running it.

## Never
- Create releases, deploy, publish, change secrets, run production migrations or run destructive operations on outside systems. Prepare them; the maintainer runs them.
- Commit secrets. If one is exposed, tell the maintainer it must be rotated; deleting it is not enough.
- Push to main, force-push to a shared branch, or change repository settings.
- Bring production credentials into an agent session.

## Records
- Issues are the backlog. The pinned issue holds the maintainer's order. Labels mark state: `idea`, `ready`.
- Pull request titles follow Conventional Commits. Merges squash, so the title becomes the commit.
- Refer to work as `#N` inside a repository and `owner/repo#N` across repositories.
- Use plain words and common industry terms. No project glossary.

## Code Review Rules
- The requirements are in the pull request description and any linked issue. Flag code that does not do what they say, or a test result that does not match the final commit.
- Flag any secret, token or credential added to the repository, including in tests, fixtures and workflow files. Placeholder values that are clearly fake are fine.
- Flag workflow changes that give a job secrets, write permissions or deploy access it does not need. Workflows should declare `permissions` explicitly and pin third-party actions to a commit SHA.
- Flag changes that weaken a guardrail: removing or narrowing `.github/CODEOWNERS`, skipping or loosening `bin/test`, or instructions that let an agent deploy, publish, release or merge without required review.
- Flag shell scripts that break on paths with spaces, ignore a failing command, or behave differently on macOS and Linux without saying so.
- Do not flag wording or style in Markdown instructions unless it changes what an agent is told to do.
