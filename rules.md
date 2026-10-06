# How work moves in this repository (Mentat)

*Read by agents. For people: `README.md` and `docs/`.*

The maintainer owns this repository. Claude Code plans and builds. Codex reviews pull requests, through OpenAI's Codex GitHub app or locally. The maintainer decides what matters and merges.

The repository comes first. Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (merge method, commit and title format, branch flow, labels, templates, or a workflow they name that commits to the default branch, such as a journal), the repository wins, and Claude Code says so once. That exception covers only what the repository names; it is never leave to push code changes to the default branch. The maintainer merging and "What agents never do" below always hold.

When a session first starts change work in a repository, Claude Code runs `mentat check`. A failure goes to the maintainer with its lines; warnings are shown to the maintainer, and work goes on.

## A change
1. Work starts from a chat request or an issue.
2. Claude Code reads the code first, then writes down what it will build, what it will leave alone and how the result will be checked, in the issue or the pull request. Anything it adds beyond the request, it names there and asks first when the maintainer did not ask for it. A separate plan is written only when the approach is uncertain or the decision matters. Before handing off such a plan, Claude Code runs `mentat challenge <plan-file>`, and the maintainer can ask for one at any time. Codex checks the plan against the repository and ends with a verdict; exit 1 means not challenged, and the handoff says so. Claude Code sorts the findings as it sorts review findings. The maintainer sees the plan with what changed, and any objection Claude Code did not adopt, with the reason. A challenge never counts as a review.
3. There is one builder, one branch and one checkout per change. Subagents are mostly for read-only investigation. Claude Code gives the builder the test command.
4. The test command is the one AGENTS.md names; otherwise the one the repository shows (package scripts, a Makefile, its CI workflow). It runs before the pull request opens and after every fix. The pull request shows its result on the final commit, and says so when there is no test command, or a check is missing or could not run. Claude Code does not edit the maintainer's AGENTS.md to add one unless asked.
5. Every pull request opens as a draft, with the repository's template if it has one, and links its issue with `Closes #N` when there is one.
6. When the build is done, the test command passes and CI passes where the repository has CI, Claude Code runs `mentat review <N>`, or `mentat review --local <N>` when the repository's AGENTS.md says reviews are local. The app path marks the pull request ready, which starts the Codex app's review of that exact head; the local path reviews that head with local Codex and posts the result on the pull request. Both wait for the result: exit 0 means no findings; exit 2 means findings were posted on that commit; exit 1 means not reviewed: after the app path, Claude Code runs `mentat review --local <N>`, and after the local path it tells the maintainer; exit 3 means the head moved, so it runs again. Claude Code sorts each finding: it fixes what affects correctness, the stated requirements or security when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. Lower-priority points become cheap fixes or follow-up issues. Fixes are batched and pushed, then the same review command runs again for the new head.
7. When the review exits 0 on the latest commit, or exits 2 and every finding was answered with a reason and none is a blocker Claude Code disagrees with (step 8), and Claude Code has read and answered every comment and review the maintainer left, it does a final check of that commit and posts it as one comment on the pull request, ten lines at most: what was asked and where the diff does it, the test command and CI results on that commit, how each review finding was settled, anything in the diff beyond the request, what was not checked, and what most deserves the maintainer's eyes. It reads the diff and the description from GitHub, not from memory, and corrects any claim in the description that does not hold. The comment is the author's own check, not a review or an approval. If the pull request's author is not the repository owner, it requests the owner's review with `gh pr edit <N> --add-reviewer <owner>`. If the author is the owner and the repository requires approvals, it tells the maintainer that GitHub will not let them approve their own pull request. Then it tells the maintainer in chat that the pull request is ready to merge, and stops. The maintainer merges.
8. Only a blocking finding Claude Code disagrees with goes to the maintainer. A review that fails, times out or returns nothing is not a pass. After three review rounds, Claude Code brings the maintainer the trade-off before going on. Ten review rounds is a hard stop: Claude Code stops and tells the maintainer why.

## Approval
- The maintainer merges. Claude Code never merges a pull request or turns on auto-merge; Mentat's merge hook asks the maintainer if it tries.
- Approving or merging a pull request approves the code, not running it.

## What agents never do
- Merge pull requests.
- Create releases, deploy, publish, change secrets, run production migrations or run destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated; deleting it is not enough, so the maintainer is told at once.
- Push code changes to the default branch, force-push a shared branch, or change repository settings.
- Bring production credentials into an agent session.

## Records
- Issues are the backlog. Where the repository uses them, the pinned issue holds the maintainer's order and the labels `idea` and `ready` mark state.
- Pull request titles follow Conventional Commits unless the repository says otherwise.
- Work is referred to as `#N` inside a repository and `owner/repo#N` across repositories.
- Plain words and common industry terms; no project glossary.
