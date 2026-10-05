# How work moves in this repository (Mentat)

The maintainer owns this repository. Claude Code plans, builds and merges. Codex reviews pull requests through OpenAI's Codex GitHub app. The maintainer decides what matters. The repository's AGENTS.md names its one test command and anything specific to it.

Before agents first work in a repository, and after its GitHub settings change, Claude Code runs `mentat setup <owner/repo>`. A refused or incomplete result goes to the maintainer with the lines that caused it, and agents do not start work there until it reads "Setup OK". The maintainer assesses the items it lists as not checked once, before agents first work there.

## A change
1. Work starts from a chat request or an issue.
2. Claude Code reads the code first, then writes down what it will build, what it will leave alone and how the result will be checked, in the issue or the pull request. Anything it adds beyond the request, it names there and asks first when the maintainer did not ask for it. A separate plan is written only when the approach is uncertain or the decision matters. Before handing off such a plan, Claude Code runs `mentat challenge <plan-file>`, and the maintainer can ask for one at any time. Codex checks the plan against the repository and ends with a verdict; exit 1 means not challenged, and the handoff says so. Claude Code sorts the findings as it sorts review findings. The maintainer sees the plan with what changed, and any objection Claude Code did not adopt, with the reason. A challenge never counts as a review.
3. There is one builder, one branch and one checkout per change. Subagents are mostly for read-only investigation.
4. The test command runs before the pull request opens and after every fix. The pull request shows its result on the final commit, and says so when a check is missing or could not run.
5. Every pull request opens as a draft, with the template, and links its issue with `Closes #N` when there is one.
6. When the build is done, the test command passes and CI passes, Claude Code runs `mentat review <N>`. It marks the pull request ready, which starts the Codex app's review of that exact head, and waits for the result: exit 0 means no findings; exit 2 means findings were posted on that commit; exit 1 means not reviewed, and Claude Code tells the maintainer; exit 3 means the head moved, so it runs again. Claude Code sorts each finding: it fixes what affects correctness, the stated requirements, security or a guardrail when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. Lower-priority points become cheap fixes or follow-up issues. Fixes are batched and pushed, then `mentat review` runs again for the new head.
7. When `mentat review` exits 0 on the latest commit, or exits 2 and every finding was answered with a reason and none is a blocker Claude Code disagrees with (step 8), and Claude Code has read and answered every comment and review the maintainer left, it does a final check of that commit and posts it as one comment on the pull request, ten lines at most: what was asked and where the diff does it, the test command and CI results on that commit, how each review finding was settled, anything in the diff beyond the request, what was not checked, and what most deserves the maintainer's eyes. It reads the diff and the description from GitHub, not from memory, and corrects any claim in the description that does not hold. The comment is the author's own check, not a review or an approval. Then it requests the maintainer's review with `gh pr edit <N> --add-reviewer <owner>`, where `<owner>` is the repository owner; GitHub does not request code owners on a pull request opened as a draft. Then it runs `mentat wait <N>` in the background and acts on how it ends: exit 0 (approved at the current head) means merge; exit 1 means read and answer what changed; exit 2 (no response in four hours) means tell the maintainer.
8. Only a blocking finding Claude Code disagrees with goes to the maintainer. A review that fails, times out or returns nothing is not a pass. After three review rounds, Claude Code brings the maintainer the trade-off before going on. Ten review rounds is a hard stop: Claude Code stops and tells the maintainer why.
9. Merges use `gh pr merge --squash --match-head-commit <sha>`, where `<sha>` is the commit the app's final review covered, once required checks and approvals pass.

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
