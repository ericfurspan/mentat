# How work moves in this repository (Mentat)

The maintainer owns this repository. Claude Code plans, builds and merges. Codex reviews pull requests through `mentat review`, run on the maintainer's Mac. The maintainer decides what matters. The repository's AGENTS.md names its one test command and anything specific to it.

## A change
1. Work starts from a chat request or an issue.
2. Claude Code reads the code first, then writes down what it will build and how the result will be checked, in the issue or the pull request. A separate plan is written only when the approach is uncertain or the decision matters. Before handing off such a plan, Claude Code runs `mentat challenge <plan-file>`, and the maintainer can ask for one at any time. Codex checks the plan against the repository and ends with a verdict; exit 1 means not challenged, and the handoff says so. Claude Code sorts the findings as it sorts review findings. The maintainer sees the plan with what changed, and any objection Claude Code did not adopt, with the reason. A challenge never counts as a review.
3. There is one builder, one branch and one checkout per change. Subagents are mostly for read-only investigation.
4. The test command runs before the pull request opens and after every fix. The pull request shows its result on the final commit, and says so when a check is missing or could not run.
5. Every pull request opens as a draft, with the template, and links its issue with `Closes #N` when there is one.
6. While the pull request is a draft, Claude Code runs `mentat review <N>`. It reviews the pull request's exact head commit against its base with a pinned Codex model and posts Codex's reply to the pull request. Exit 0 means a review was posted, not that it is clean; exit 1 means not reviewed; exit 3 means the head moved, so it runs again. Claude Code sorts each finding: it fixes what affects correctness, the stated requirements, security or a guardrail, and answers the rest with a reason. Lower-priority points become cheap fixes or follow-up issues. Fixes are batched and pushed, then one final `mentat review` covers the latest commit.
7. The pull request is marked ready for review (`gh pr ready`) only when the final review of the latest commit is clean and CI passes. Marking it ready is what requests the maintainer's review. Right after, Claude Code runs `mentat wait <N>` in the background and acts on how it ends: exit 0 (approved at the current head) means merge; exit 1 means read and answer what changed; exit 2 (no response in four hours) means tell the maintainer.
8. Only a blocking finding Claude Code disagrees with goes to the maintainer. A review that fails, times out or returns nothing is not a pass. Ten review rounds is a hard stop: Claude Code stops and tells the maintainer why.
9. Merges use `gh pr merge --squash --match-head-commit <sha>`, where `<sha>` is the commit the final review covered, once required checks and approvals pass.

## Approval
- Changes to Mentat's own files and guardrails wait for the maintainer's Approve on GitHub. The code owners file enforces this.
- Approving a pull request approves the code, not running it.

## What agents never do
- Create releases, deploy, publish, change secrets, run production migrations or run destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated; deleting it is not enough, so the maintainer is told at once.
- Push to main, force-push a shared branch, or change repository settings.
- Bring production credentials into an agent session.

## Records
- Issues are the backlog. The pinned issue holds the maintainer's order. Labels mark state: `idea`, `ready`.
- Pull request titles follow Conventional Commits. Merges squash, so the title becomes the commit.
- Work is referred to as `#N` inside a repository and `owner/repo#N` across repositories.
- Plain words and common industry terms; no project glossary.
