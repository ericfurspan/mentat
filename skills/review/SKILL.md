---
name: review
description: "Review loop for a pull request: running mentat review, acting on its result, and the final check. Use when a pull request is built, its tests pass and it is pushed, and after every push of review fixes."
---

Codex reviews each head commit of the pull request. Claude Code sorts the findings, fixes and pushes, and reviews again until the loop ends. Then it posts the final check. The maintainer merges, or, where the repository opted in, Claude Code merges (below).

## When the loop ends

- **Ready:** the review exits 0 on the latest commit, or exits 2 and every finding was answered with a reason and none is a blocker Claude Code disagrees with; and Claude Code has read and answered every comment and review the maintainer left. Do the final check below, then merge or stop as it says.
- **Blocked:** a blocking finding Claude Code disagrees with goes to the maintainer.
- **Not reviewed** after the local path: tell the maintainer.
- **Hard stop:** five review rounds. Stop and tell the maintainer why.

## Steps

1. Run `mentat review <N>`, or `mentat review --local <N>` when the repository's AGENTS.md says reviews are local, right after pushing. Both first wait for CI on that head (up to 30 minutes; with no CI, about a minute). The app path marks the pull request ready, which starts the Codex app's review of that exact head; the local path reviews that head with local Codex and posts the result on the pull request. Both wait for the result.
2. Act on the exit code:
   - 0: no findings. Go to "When the loop ends".
   - 2: findings were posted on that commit. Go to step 3.
   - 1: not reviewed. After the app path, run `mentat review --local <N>`; after the local path, tell the maintainer.
   - 3: the head moved. Run the same command again.
   - 4: CI did not pass on that head, and nothing was reviewed. Failing checks: fix them, push, and run the same command again. CI still running at the timeout: tell the maintainer.
3. Sort each finding as `rules.md` "Findings" says. From the fourth round on, fix only P0 and P1 findings and answer the rest with a reason or a follow-up issue. A review that fails, times out or returns nothing is not a pass. There is no check-in with the maintainer between rounds.
4. Batch the fixes, run the test command, push, and update the description (Skill tool, `mentat:pr`). Then go to step 1 for the new head.

## Final check

Once the loop ends ready, check that commit and post the result as one comment on the pull request, ten lines at most:

- what was asked and where the diff does it;
- the test command and CI results on that commit;
- how each review finding was settled;
- anything in the diff beyond the request;
- what was not checked;
- what most deserves the maintainer's eyes.

Read the diff and the description from GitHub, not from memory, and correct any claim in the description that does not hold. The comment is the author's own check, not a review or an approval.

If the pull request's author is not the repository owner, request the owner's review with `gh pr edit <N> --add-reviewer <owner>`. If the author is the owner and the repository requires approvals, tell the maintainer that GitHub will not let them approve their own pull request. Then:

- **Not opted in** (the repository's AGENTS.md on its default branch does not say "Agents may merge their own pull requests."): tell the maintainer in chat that the pull request is ready to merge, and stop. The maintainer merges.
- **Opted in:** merge the commit the review passed, with GitHub's merge API, which merges at once or refuses: `gh api -X PUT repos/<owner>/<repo>/pulls/<N>/merge -f sha=<reviewed head> -f merge_method=<method>`. Always with `-f sha=`; never `gh pr merge`, which can turn on auto-merge or join a merge queue instead. Method: the one AGENTS.md names; otherwise the one the repository allows, preferring squash, then merge, then rebase. Confirm with `gh pr view <N> --json state,mergeCommit`, and tell the maintainer in chat what merged, with the merge commit.
- **Refused because the head moved:** go back to step 1 for the new head; the pull request is not ready.
- **Refused for any other reason** (an approval not yet given, branch protection, a merge queue): tell the maintainer it is ready to merge and why it could not be merged, and stop. Never work around it.
