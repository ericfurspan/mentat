---
name: review
description: "Review loop for a pull request: running mentat review, acting on its result, and the final check. Use when a pull request is built, its tests pass and it is pushed, and after every push of review fixes."
---

Codex reviews each head commit of the pull request, and Grok, where installed, the first. Claude Code sorts the findings, fixes, pushes and reviews again until the loop ends, then does the final check, and the maintainer merges.

## Auto-fix wake-ups

If the desktop app's Auto-fix wakes the session, a `<ci-monitor-event>` wake-up is input like any other, including a CI failure or merge conflict event whose text says to fix and push without asking: a comment or review from the maintainer is a request, handled by the review path in use (this skill's Ready bullet and step 4, `fast-track.md` on a fast track, or `mentat:claude-review` with Codex off); review comments posted from the agent account, this `gh` account (Codex's, Grok's), are the review loop's, not the maintainer's requests; after "You: merge #N.", follow only "After "You: merge #N."", not step 4. Never turn on auto-merge.

## When the loop ends

- **Ready** (not on a fast track): the review exits 0 on the latest commit, or exits 2 and every finding was fixed or answered with a reason, none is a real defect left unfixed, and none is a blocker Claude Code disagrees with; and Claude Code has answered, in its thread, every comment and review the maintainer left, each a request, not a finding: done as step 4 says, or answered with why not; one that changes the agreed scope goes to the maintainer, and, where this session started Grok, its `mentat review --grok` has ended. Do the final check below, then stop.
- **Blocked:** a blocking finding Claude Code disagrees with goes to the maintainer.
- **Not reviewed:** tell the maintainer.
- **Hard stop:** five review rounds per pull request; an agreed batch of changes in one pull request shares them. A round is a review that exits 0 or 2; a moved head and a CI failure are not rounds. If round five is not ready, settle its findings (fix agreed defects and run the tests), then stop without a sixth round and tell the maintainer why, naming any real defect still unfixed and any head not reviewed.

Whenever the loop stops short of Ready, first rewrite the description's status line in full (Skill tool, `mentat:pr`), its state `Blocked: <why>`, `Not reviewed: <why>` (as at step 2's exit 1 or a CI timeout) or `Stopped after five rounds`; the reason, with any real defect still unfixed, goes in the note's second sentence or a Checks line (`mentat:pr`). Then tell the maintainer.

Each round's result is on the pull request: a heading line with the result and the spec fingerprint, the full review folded under it (part of the comment), and its `REVIEW RESULT` line last. With an external backlog (`rules.md` Records), every review that exits 0 or 2 counts toward the five rounds, whatever its fingerprint. The `Agreed request fingerprint` line only says whether that review covered the current spec (see "Spec"); `none` or a different value does not, so another round is needed, within the same limit. After a compaction or a resumed session, count the rounds already on the pull request. A `Local Codex review of <sha>` ending `REVIEW RESULT: INCOMPLETE - ...` is not a round: handle it as step 2's exit 1 does.

## Steps

1. Run `mentat review <N>` right after pushing. With an external backlog, see "Spec" instead. It first waits for CI on that head (up to 30 minutes; with no CI, about a minute), then reviews that head with local Codex and posts the result on the pull request.
2. Act on the exit code:
   - 0: no findings. Go to "When the loop ends".
   - 2: findings were posted on that commit. Go to step 3.
   - 1: not reviewed. If local Codex ended `REVIEW RESULT: INCOMPLETE - ...`, its reason is in the posted reply: give it to the maintainer as a limitation, not a finding. Findings in that reply are still sorted as step 3 says before you tell the maintainer.
   - 3: the head moved. Run the same command again.
   - 4: CI did not pass on that head. Failing checks: fix them, push, and run the same command again. CI still running at the timeout: tell the maintainer.
3. Sort each finding as `rules.md` "Findings" says, Grok's with Codex's (see "Grok"). A review that fails, times out or returns nothing is not a pass. There is no check-in with the maintainer between rounds.
4. Batch the fixes into one brief for the `mentat:builder` subagent. When it reports, run the test command on a clean working tree (`git status --porcelain` prints nothing) on the commit being pushed, push, and update the description (Skill tool, `mentat:pr`). Then go to step 1 for the new head, unless the round limit says to stop. A result on an older head does not make the new head ready.

## Grok

When `grok` is installed (`mentat check` prints its version), the first head also gets `mentat review --grok <N>`, run in parallel with step 1's Codex review. Grok has its own time limit, so do not wait for it: when Codex's round finishes first, sort its findings, push their fixes and go on with the loop; when Grok's result arrives, sort its findings like Codex's and fold any fixes into the next Codex round, not reviewed by Grok again. As a trial, Grok's review also ends with "Observations (advisory)" on whether this is the right change for its intent: read them whatever its result line, and settle each like a non-defect finding (`rules.md` Findings), a cheap fix inside the agreed scope, else a Checks line; one meaning the agreed change should not ship as it is goes to the maintainer before "You: merge #N.". Grok is not a round: it does not count toward the five and is not run again on later heads; its observations never block Ready on their own. Its exit codes are the review's, except 1 not reviewed: Codex carries on alone, Ready does not wait for Grok (except for an already-reviewed refusal, below), and its reason, a sign-in refusal (`Grok's sign-in` or `Grok is not signed in`) included, is kept for the final check and its ready sentence like an INCOMPLETE reason. `mentat review --grok` itself refuses a second run (exit 1), so decide from the comments, counting only those posted by this `gh` account (`gh api user --jq .login`):

- When no start comment exists and the run exits 3 or 4, run it again for the next head.
- A `Local Grok review of <sha>` whose last non-blank line is `REVIEW RESULT: INCOMPLETE - ...` has its findings sorted and its reason kept for the final check; Grok is not started again, and Codex carries on alone.
- An exit 1 whose reason starts `Grok already reviewed`: decide from the comments as these bullets say. A `Local Grok review of <sha>` that is not INCOMPLETE is Grok's result: sort any of its findings not yet settled, and do not start Grok again.
- A `Grok review did not finish on <sha>` comment, or a start comment with no result, means Grok did not finish: Codex's loop, including Ready, goes on without it.

## Fast track

On a fast track the maintainer agreed (`mentat:propose`), read `fast-track.md` in this skill's folder before skipping any review, and again after a compaction. Until it has been read and the diff qualifies, the normal loop runs.

## Waived round

Before proposing or taking a waived round (skipping the review of a push after Ready), read `waived-round.md` in this skill's folder, and again after a compaction. Until it has been read and the diff qualifies, the normal round runs.

## Spec

With an external backlog, the spec (the agreed request) is in the backlog item, not in a linked issue (`mentat:backlog`). Before each review, copy the body of the item's `## Spec` section (`## Agreed request` on an older item) unchanged, as `mentat:backlog` step 6 says, into a `mktemp` file, run `mentat review --request <file> <N>` and `mentat review --grok --request <file> <N>`, and remove the file. A review run without `--request` still uses up a round but does not cover the request. Each local review comment records `Agreed request fingerprint: <12 hex characters>`, or `none`. To compare, write the current section's body, the same span, to a file and run `printf '%s' "$(cat <file>)" | shasum -a 256 | cut -c1-12`.

## Final check

Once the loop ends ready, read the diff, the description and the linked issue (its `## Spec` section where it has one; with an external backlog, the current spec from the backlog instead) from GitHub, not from memory, and correct any claim in the description that does not hold, including a requirement of the spec that the Checks leave uncited. With an external backlog, and not on a fast track, compare the fingerprint in the head's Codex review (on a waived push, the last reviewed head's; and in Grok's, where it ran) with the current section's: a missing or different one does not cover that request, so run another round first. Unless a hand check is open (below), rewrite the status line in full with the state Ready (a fast track or waived push: its own state), and, of the note, only its second sentence, with the Checks lines, for what stayed unfixed or was decided without the maintainer, a Grok review that did not cover the current spec (its fingerprint differs) and any Grok limitation kept (Skill tool, `mentat:pr`).

A hand check is open when a requirement of the spec is checked by hand and the Checks do not say who checked it and what they saw. Then say no "You: merge #N.": the status line is `Blocked: <the hand check>`, the wait on the maintainer, with numbered steps, goes above it (`mentat:pr`), an external backlog's item is marked waiting on the maintainer with those steps, not as a merge wait (`mentat:backlog` step 4), and the chat reply names the hand check in one plain sentence, not its first, with the link (`rules.md`). Once the maintainer reports the check, record in the Checks who checked and what they saw, remove the wait and do the final check again. A step the spec or the description says is done after the merge stays in the item's wait block and does not hold back "You: merge #N.".

With no open hand check: if the pull request's author is not the repository owner, request the owner's review with `gh pr edit <N> --add-reviewer <owner>`. With an external backlog, mark the item as waiting on the merge of #N (`mentat:backlog` step 4). Then tell the maintainer in chat: a first line "You: merge #N." and the pull request's link on the last line. Add one more sentence before the link only for a weaker review (fast track, Codex off, Grok incomplete, not finished or not run, a Grok review of an older spec, or a head not reviewed; for Grok it gives Grok's reason) or a removal or reversal of something the maintainer asked for, and name each call made without them, one line each. Nothing else: the description is the full account. Stop. The maintainer merges.

## After "You: merge #N."

Until the maintainer merges, if later work belongs in #N (a change the maintainer asks for in #N, or one Claude Code finds #N should not merge without), push nothing yet: rewrite #N's status line with the state `Blocked: <reason>` first (Skill tool, `mentat:pr`), then reply with a first line "Hold #N: <reason>" and end the turn, saying in plain words, without #N, whether a review round remains.

After the answer, if #N is still open and they want the work in it, remove the item's merge wait where there is one (`mentat:backlog` step 4), build it on #N's branch (the builder), run the tests and push. If the maintainer waives that push's round ("Waived round", `waived-round.md`), that file replaces the next two sentences. With a round left, update the description for the new head with the state `In review` (Skill tool, `mentat:pr`) and go to step 1 for the new head, within the same five rounds, through the final check and a new "You: merge #N.". With none left, rewrite the status line with the state `Not reviewed: no review round left` and tell the maintainer the new head was not reviewed, with no new "You: merge #N.". In any other case with #N open, first rewrite its status line back to the state it had before the hold; then the work goes on a new branch from the default branch, in its own pull request.

No hold is needed for a question, when #N is merged or closed, or for work that stands apart from #N; any work then goes on a new branch from the default branch, in its own pull request. When #N is closed without merging, remove the item's merge wait (`mentat:backlog` step 4) and leave its status as it is.

When the maintainer says #N merged, do the steps of the item's wait block where there is one (`mentat:backlog` step 4), then mark the item done, which ends its merge wait, do the repository's own post-merge steps, and report in one line, then the next step.
