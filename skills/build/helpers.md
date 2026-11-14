# Helper builds

Read this before briefing a builder and before each push, and again after a compaction or a resume. It covers every builder run: the initial build, CI fixes, review fixes and work after a hold alike.

## Briefs

The builder is the `mentat:builder` subagent. A brief names any existing design the change keeps that could affect its goal.

Before fixing a raised problem, Claude Code checks likely related cases in proportion to its scope and reports a shared cause when found, keeping the fix within the agreed scope. A fix it recommends targets the cause the evidence supports; when the cause is unknown, it recommends finding the cause first.

A correction during agreed work does not reopen the spec; a change of scope goes to the maintainer as one question. Claude Code follows any correction within the agreed scope at once, and files it as an item only when the maintainer asks.

## Worktree

After `git fetch origin`, create the branch and its worktree with `git worktree add --no-track -b <branch> <path> origin/<default>`. `<path>` is always the absolute path `<main>/.claude/worktrees/<name>`, where `<main>` is the main checkout (the parent of `git rev-parse --path-format=absolute --git-common-dir`) and `<name>` the branch with each `/` as `-`, never a path inside another worktree. Keep `--no-track`: without it the branch tracks the default branch, so a bare `git push` would aim at it. The branch carries the item id as the tracker's adapter says. The same worktree serves every later helper of that pull request. A branch that already has a worktree uses it; one with none gets `git worktree add <path> <branch>`.

The main session never changes its own directory into a worktree: it runs `git -C <path>` or a subshell `( cd <path> && ... )`. It pushes with `git -C <path> push -u origin <branch>` once the worktree is committed and `git -C <path> status --porcelain` prints nothing; the pushed head is `git -C <path> rev-parse HEAD`, which `mentat review` then reads from GitHub.

## One helper per branch

Before a brief, if the worktree is locked, brief no helper and go to "Recovery". Otherwise run `git worktree lock --reason "mentat helper <item id>" <path>`, then brief the helper and start it with the Agent tool's background option, so the session stays free. When its completion notice arrives, done, stopped or failed, run `git worktree unlock <path>`, then the main-checkout check. The brief names the worktree's absolute path and branch.

## Main-checkout check

Before each brief, note the main checkout's branch, `HEAD` and the output of `git status --porcelain -- ':(exclude).claude/worktrees'`. After the helper reports, that status prints nothing, and the branch and `HEAD` are what they were before the brief. If the main checkout was not clean before the brief, compare the output with the one taken then, and the run's final message says the check was weaker. On any difference, start no further helper, change nothing in the main checkout, and tell the maintainer the paths and what changed. The check does not see writes to ignored paths.

## Testing

Before pushing, Claude Code tests the pushed commit, with a clean working tree (`git -C <path> status --porcelain` prints nothing), not relying on the builder's report, unless the repository's AGENTS.md says CI runs the test command on every pull request. Then CI is that run, except that after CI fails on the branch, the next commit is tested this way before it is pushed; and when that run was skipped, a head with no CI check runs is not a pass: Claude Code tests that commit before any review of it counts.

## Recovery

After a compaction or a resume, before any other build step, read `git worktree list --porcelain`. For each worktree under the main checkout's `.claude/worktrees/` whose branch carries an item id of this session's own work (its build queue, or the item it agreed), read its branch, its lock, `git -C <path> status --porcelain`, its commits not on origin's copy of its branch, and its pull request (`gh pr list --head <branch> --state all --json number,state,headRefOid`), with `mentat status <N>` for an open one. Every other worktree there, locked or not, is another session's: leave it untouched and list it for the maintainer.

Of this session's worktrees, a locked one's helper counts as running only while the host's list of this session's subagents shows it running and its report is not yet in the session: wait for that report. Otherwise it stopped: unlock the worktree, which is unfinished if it has uncommitted or unpushed work. If that list cannot be read, wait for the report and tell the maintainer.

## Unfinished

A worktree is unfinished when it has uncommitted changes or commits not pushed, or its helper stopped before reporting. It is kept: never removed, reset, stashed or cleaned. List it, one line each (path, branch, what is unfinished), in the recovery message and in the build run's final message. Continue it with one new helper briefed into it with the item's brief, told that an earlier helper stopped there and that its work stays where it fits the brief, or, with nothing left to build, with the next step (test, push, review).

## After merge

Remove only a worktree "Worktree" made for the merged pull request's branch, never the checkout this session runs in and never one with another worktree's path under it in `git worktree list`; a worktree this rules out is kept and listed. Act only on this session's worktrees as "Recovery" defines them; leave another session's untouched and list it. When the maintainer says #N merged, or the recovery read finds it merged, and `gh pr view <N> --json state,headRefOid` shows `MERGED` with the head equal to the worktree's `HEAD`, run `git worktree remove <path>` (never `--force`), then `git branch -D <branch>`: the pull request's state shows it merged, not ancestry, since a squash merge leaves the branch unmerged to git. Before removing, `git -C <path> status --porcelain --ignored` must print nothing; otherwise keep the worktree and list it with those paths. A refusal keeps the worktree and lists it as unfinished. A worktree whose pull request closed without merging is kept and listed until the maintainer says to drop it. The remote branch is left alone.

## A separate session

A build runs in a separate session only as `mentat:propose` "Starting a build" says.
