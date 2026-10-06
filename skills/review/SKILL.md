---
name: review
description: "Review loop for a pull request: running mentat review, acting on its result, and the final check. Use when a pull request is built and its tests and CI pass, and after every push of review fixes."
---

Codex reviews each head commit of the pull request. Claude Code sorts the findings, fixes and pushes, and reviews again until the loop ends. Then it posts the final check and stops; the maintainer merges.

## When the loop ends

- **Ready:** the review exits 0 on the latest commit, or exits 2 and every finding was answered with a reason and none is a blocker Claude Code disagrees with; and Claude Code has read and answered every comment and review the maintainer left. Do the final check below, then stop.
- **Blocked:** a blocking finding Claude Code disagrees with goes to the maintainer.
- **Not reviewed** after the local path: tell the maintainer.
- **Hard stop:** five review rounds. Stop and tell the maintainer why.

## Steps

1. Run `mentat review <N>`, or `mentat review --local <N>` when the repository's AGENTS.md says reviews are local. The app path marks the pull request ready, which starts the Codex app's review of that exact head; the local path reviews that head with local Codex and posts the result on the pull request. Both wait for the result.
2. Act on the exit code:
   - 0: no findings. Go to "When the loop ends".
   - 2: findings were posted on that commit. Go to step 3.
   - 1: not reviewed. After the app path, run `mentat review --local <N>`; after the local path, tell the maintainer.
   - 3: the head moved. Run the same command again.
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

If the pull request's author is not the repository owner, request the owner's review with `gh pr edit <N> --add-reviewer <owner>`. If the author is the owner and the repository requires approvals, tell the maintainer that GitHub will not let them approve their own pull request. Then tell the maintainer in chat that the pull request is ready to merge, and stop. The maintainer merges.
