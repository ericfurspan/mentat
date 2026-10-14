---
name: review
description: "Review loop for a pull request: running mentat review, acting on its result, and the final check. Use when a pull request is built, its tests pass and it is pushed, and after every push of review fixes."
---

Codex reviews each head commit of the pull request, and Grok, where installed, the first. Claude Code sorts the findings, fixes and pushes, and reviews again until the loop ends. Then it posts the final check, and the maintainer merges.

## When the loop ends

- **Ready:** the review exits 0 on the latest commit, or exits 2 and every finding was fixed or answered with a reason, none is a real defect left unfixed, and none is a blocker Claude Code disagrees with; and Claude Code has read and answered every comment and review the maintainer left, and, where this session started Grok, its `mentat review --grok` has ended. Do the final check below, then stop.
- **Blocked:** a blocking finding Claude Code disagrees with goes to the maintainer.
- **Not reviewed** after the local path: tell the maintainer.
- **Hard stop:** five review rounds per pull request, counting rounds before a compaction or a resumed session. A round is a review that exits 0 or 2; a fallback to local review, a moved head and a CI failure are not rounds. If round five is not ready, settle its findings (fix agreed defects and run the tests), then stop without a sixth round and tell the maintainer why, naming any real defect still unfixed and any head not yet reviewed.

Each round's result is on the pull request (the review and the replies to it). After a compaction or a resumed session, count the rounds from there before continuing.

## Steps

1. Run `mentat review <N>`, or `mentat review --local <N>` when the repository's AGENTS.md says reviews are local, right after pushing. Both first wait for CI on that head (up to 30 minutes; with no CI, about a minute). The app path comments `@codex review` on the pull request, which starts the Codex app's review of that exact head (OpenAI's page says the app flags only P0 and P1 issues, though it has posted P2s), and reads the result from the app's summary comment for that commit, counting security-review findings too; the local path reviews that head with local Codex and posts the result on the pull request. Both wait for the result.
2. Act on the exit code:
   - 0: no findings. Go to "When the loop ends".
   - 2: findings were posted on that commit. Go to step 3.
   - 1: not reviewed. After the app path, run `mentat review --local <N>`; after the local path, tell the maintainer. If the local reviewer ended `REVIEW RESULT: INCOMPLETE - ...`, its reason is in the posted reply: give the maintainer the reason with the reply, as a limitation, not a finding.
   - 3: the head moved. Run the same command again.
   - 4: CI did not pass on that head, and nothing was reviewed. Failing checks: fix them, push, and run the same command again. CI still running at the timeout: tell the maintainer.
3. Sort each finding as `rules.md` "Findings" says, Grok's with Codex's (see "Grok"). The round number does not change how a finding is sorted. A review that fails, times out or returns nothing is not a pass. There is no check-in with the maintainer between rounds.
4. Batch the fixes into one brief for the `mentat:builder` subagent (a new dispatch, or continuing the earlier builder). When it reports, run the test command on a clean working tree (`git status --porcelain` prints nothing) on the commit being pushed, push, and update the description (Skill tool, `mentat:pr`). Then go to step 1 for the new head, unless the round limit says to stop. A result on an older head does not make the new head ready.

## Grok

When `grok` is installed (`mentat check` prints its version), the first head also gets `mentat review --grok <N>`, run in parallel with step 1's Codex review. Grok has its own time limit (`MENTAT_GROK_TIMEOUT_SECONDS`, default 30 minutes) and real runs have taken over 20, so do not wait for it: when Codex's round finishes first, sort its findings, push their fixes and go on with the loop; when Grok's result arrives, sort its findings and fold any fixes into the next Codex round. A finished Grok review is posted for the commit it reviewed even if the head has moved since. Ready still waits for a Grok run this session started to end. Grok is not a round: it does not count toward the five and is not run again on later heads. Its exit codes are the review's: 0 no findings, 2 findings posted on the pull request, 1 not reviewed (Codex carries on alone), 3 the head moved, 4 CI did not pass. A Grok reply ending `REVIEW RESULT: INCOMPLETE - ...` is not reviewed too: Codex carries on alone, the final check records the limitation, and any findings in that reply are still sorted.

- Look for a `Grok review started on` comment on the pull request before running it. Count only comments posted by the account `gh` is signed in as (`gh api user --jq .login`); anyone who can comment could post the same text. `mentat review --grok` applies the same rule and exits 1 when its own account's start comment is already there. If there is none and the run exits 3 or 4, run it again for the next head, as the loop does for Codex.
- Once a start comment exists, never start Grok on that pull request again. After a compaction or a resumed session, decide from the pull request's comments, again only this account's: a start comment followed by `Local Grok review of <sha>` means Grok is done, unless that review's last line is `REVIEW RESULT: INCOMPLETE - ...`, which means Grok did not finish and Codex's loop goes on without it; a start comment with `Grok review did not finish on <sha>`, or with no result, means Grok did not finish, and Codex's loop, including Ready, goes on without it.
- Grok's findings are sorted like Codex's: fix what is a real defect, answer the rest with a reason. A fix is pushed with the next Codex round's fixes, not reviewed by Grok again.

## Final check

Once the loop ends ready, read the diff, the description and the linked issue from GitHub, not from memory, and correct any claim in the description that does not hold. Then post one comment on the pull request, six lines at most, that does not repeat the description's summary or scope: the commit checked and its test and CI results, the reviewer's one-sentence statement of the pull request's intent (from the request and the diff, if the last round had none) and whether it matches the description's, how each review finding was settled (Codex's and, where it ran, Grok's, or that Grok did not run), what was not checked, and what most deserves the maintainer's eyes. The comment is the author's own check, not a review or an approval. Start it with `Final check on <sha>`, the commit checked.

If the pull request is still a draft (opened before Mentat stopped using drafts), run `gh pr ready <N>`; if that fails, report it and stop. If the pull request's author is not the repository owner, request the owner's review with `gh pr edit <N> --add-reviewer <owner>`. Then tell the maintainer in chat that the pull request is ready to merge, and stop. The maintainer merges.
