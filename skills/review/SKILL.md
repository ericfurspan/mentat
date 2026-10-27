---
name: review
description: "Review loop for a pull request: running mentat review, acting on its result, and the final check. Use when a pull request is built, its tests pass and it is pushed, and after every push of review fixes."
---

Codex reviews each head commit of the pull request, and Grok, where installed, the first. Claude Code sorts the findings, fixes, pushes and reviews again until the loop ends, then does the final check, and the maintainer merges. A fast track runs only the final check ("Fast track").

## When the loop ends

- **Ready** (not on a fast track): the review exits 0 on the latest commit, or exits 2 and every finding was fixed or answered with a reason, none is a real defect left unfixed, and none is a blocker Claude Code disagrees with; and Claude Code has read and answered every comment and review the maintainer left, and, where this session started Grok, its `mentat review --grok` has ended. Do the final check below, then stop.
- **Blocked:** a blocking finding Claude Code disagrees with goes to the maintainer.
- **Not reviewed:** tell the maintainer.
- **Hard stop:** five review rounds per pull request; an agreed batch of changes in one pull request shares them. A round is a review that exits 0 or 2; a moved head and a CI failure are not rounds. If round five is not ready, settle its findings (fix agreed defects and run the tests), then stop without a sixth round and tell the maintainer why, naming any real defect still unfixed and any head not reviewed.

Whenever the loop stops short of Ready, first rewrite the description's status line in full (Skill tool, `mentat:pr`), its state `Blocked: <why>`, `Not reviewed: <why>` (as at step 2's exit 1 or a CI timeout) or `Stopped after five rounds`; the note keeps its shape and gains the reason, with any real defect still unfixed, in one sentence. Then tell the maintainer.

Each round's result is on the pull request: a heading line with the result and the spec fingerprint, the full review folded under it (part of the comment), and its `REVIEW RESULT` line last. With an external backlog (`rules.md` Records), every review that exits 0 or 2 counts toward the five rounds, whatever its fingerprint. The `Agreed request fingerprint` line only says whether that review covered the current spec (see "Spec"); `none` or a different value does not, so another round is needed, within the same limit. After a compaction or a resumed session, count the rounds from there. A `Local Codex review of <sha>` ending `REVIEW RESULT: INCOMPLETE - ...` is not a round: handle it as step 2's exit 1 does.

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

When `grok` is installed (`mentat check` prints its version), the first head also gets `mentat review --grok <N>`, run in parallel with step 1's Codex review. Grok has its own time limit (`MENTAT_GROK_TIMEOUT_SECONDS`, default 30 minutes), so do not wait for it: when Codex's round finishes first, sort its findings, push their fixes and go on with the loop; when Grok's result arrives, sort its findings like Codex's and fold any fixes into the next Codex round, not reviewed by Grok again. As a trial, Grok's review also ends with "Observations (advisory)" on whether this is the right change for its intent: read them whatever its result line, and settle each like a non-defect finding (`rules.md` Findings), a cheap fix inside the agreed scope, else one sentence in the note; one meaning the agreed change should not ship as it is goes to the maintainer before "You: merge #N.". Grok is not a round: it does not count toward the five and is not run again on later heads; its observations never block Ready on their own. Its exit codes are the review's, except 1 not reviewed: Codex carries on alone, Ready does not wait for Grok (except for an already-reviewed refusal, below), and its reason, a sign-in refusal (`Grok's sign-in` or `Grok is not signed in`) included, is kept for the final check's note and ready sentence like an INCOMPLETE reason. `mentat review --grok` itself refuses a second run (exit 1), so decide from the comments, counting only those posted by this `gh` account (`gh api user --jq .login`):

- When no start comment exists and the run exits 3 or 4, run it again for the next head.
- A `Local Grok review of <sha>` whose last non-blank line is `REVIEW RESULT: INCOMPLETE - ...` has its findings sorted and its reason kept for the final check's note; Grok is not started again, and Codex carries on alone.
- An exit 1 whose reason starts `Grok already reviewed`: decide from the comments as these bullets say. A `Local Grok review of <sha>` that is not INCOMPLETE is Grok's result: sort any of its findings not yet settled, and do not start Grok again.
- A `Grok review did not finish on <sha>` comment, or a start comment with no result, means Grok did not finish: Codex's loop, including Ready, goes on without it.

## Fast track

A fast track skips the Codex and Grok reviews for a change that cannot alter what code does or what an agent is told (typos, punctuation, broken links, formatting). Tests, CI and the final check still run. It is on only when the maintainer agreed to the proposal or asked for it; Claude Code never turns it on itself.

- The fast track and its reason are one line in the spec, written when it was agreed (`rules.md` step 2): the backlog item's `## Spec` with an external backlog, else the issue's `## Spec`, else chat. After a compaction or a resumed session, read it back from there. A fast track agreed after the spec was written is a change of scope: update the spec.
- Before skipping review, check the complete final diff (`gh pr diff <N>`) against the rule above. On any doubt, and always for whitespace in source, configuration or lockfiles or for a URL a program fetches, run the normal review loop.
- Run no `mentat review` or `mentat review --grok`. Run `mentat ci <N>` after each push; it waits for CI on the head and reviews nothing. 0: go on. 3: the head moved; run it again. 4: failing checks: fix them, run the test command, push, and run it again; CI still running at the timeout, or 1: tell the maintainer.
- Then the final check, once Claude Code has answered every comment and review the maintainer left, as Ready requires; Ready's review exit and the fingerprint's round do not apply. Rewrite the status line in full with the state `Not reviewed: fast track agreed by the maintainer` (Skill tool, `mentat:pr`); the note says Codex and Grok did not review it (fast track agreed by the maintainer), and so does the one sentence after "You: merge #N." in chat.
- A later push, including after a hold, gets the diff check again. If it no longer qualifies, the normal loop runs from step 1 with all five rounds, and with Grok on that head if no Grok start comment exists, despite "not run again" above; a hold reply then says all five rounds remain. If it does, the final check runs again, and a hold reply says the fast track continues, no round used.

## Waived round

After a head reached Ready, Claude Code may propose skipping the review round of a push the maintainer asked for when the diff from the last reviewed head to the pushed head changes no file a program runs, sources or fetches (scripts, hooks, `bin/`, `lib/`, configuration, lockfiles, workflow files, a URL a program fetches); Markdown read by agents may be in it. The proposal, in chat (after "You: merge #N.", in the hold's reply), names the changed files in one line.

- Skip only on the maintainer's yes for that push, judged on the diff actually pushed. Any doubt, a pushed diff that differs from the proposal, or a change to the spec runs the normal round (within the five).
- Run no `mentat review` or `mentat review --grok`, and on the Claude-only path no Claude round (overriding its rule that a new head after a hold gets one). Run `mentat ci <N>` (exits as in "Fast track"), then the final check on the new head, with the spec fingerprint from the last reviewed head's review. The status line is `Not reviewed: last push waived by the maintainer`; the note names the last reviewed head, the waived head and the changed files; the sentence after "You: merge #N." says the last push was not reviewed, waived by the maintainer. A waived push uses no round.
- Each waived push is measured from the last head a review covered, not from an earlier waived head.

## Spec

With an external backlog, the spec (the agreed request) is in the backlog item, not in a linked issue (`mentat:backlog`). Before each review, copy the body of the item's `## Spec` section (`## Agreed request` on an older item) unchanged, as `mentat:backlog` step 6 says, into a `mktemp` file, run `mentat review --request <file> <N>` and `mentat review --grok --request <file> <N>`, and remove the file. A review run without `--request` still uses up a round but does not cover the request. Each local review comment records `Agreed request fingerprint: <12 hex characters>`, or `none`. To compare, write the current section's body, the same span, to a file and run `printf '%s' "$(cat <file>)" | shasum -a 256 | cut -c1-12`.

## Final check

Once the loop ends ready, read the diff, the description and the linked issue (its `## Spec` section where it has one; with an external backlog, the current spec from the backlog instead) from GitHub, not from memory, and correct any claim in the description that does not hold, including a requirement of the spec that the Evidence leaves uncited. With an external backlog, and not on a fast track, compare the fingerprint in the head's Codex review (and in Grok's, where it ran) with the current section's: a missing or different one does not cover that request, so run another round first, within the five-round limit. Unless a hand check is open (below), rewrite the status line in full with the state Ready (a fast track or waived push: its own state), and in the note only its sentence on what stayed unfixed or was decided without the maintainer, adding that Grok's review did not cover the current spec where its fingerprint differs, and any Grok limitation kept (Skill tool, `mentat:pr`).

A hand check is open when a requirement of the spec is checked by hand and the Evidence does not say who checked it and what they saw. Then say no "You: merge #N.": the status line is `Blocked: <the hand check>`, the wait on the maintainer, with numbered steps, goes above it (`mentat:pr`), an external backlog's item is marked waiting on the maintainer with those steps, not as a merge wait (`mentat:backlog` step 4), and the chat reply opens with the first step. Once the maintainer reports the check, record in the Evidence who checked and what they saw, remove the wait and do the final check again. A step the spec or the description says is done after the merge stays in the item's wait block and does not hold back "You: merge #N.".

With no open hand check: if the pull request's author is not the repository owner, request the owner's review with `gh pr edit <N> --add-reviewer <owner>`. With an external backlog, mark the item as waiting on the merge of #N (`mentat:backlog` step 4). Then tell the maintainer in chat: a first line "You: merge #N." and the pull request's link on the last line. Add one more sentence before the link only for a weaker review (fast track, Codex off, Grok incomplete, not finished or not run, a Grok review of an older spec, or a head not reviewed; for Grok it gives Grok's reason), a removal or reversal of something the maintainer asked for, or a call made without them. Nothing else: the description's note is the full account. Stop. The maintainer merges.

## After "You: merge #N."

Until the maintainer merges, if later work belongs in #N (a change the maintainer asks for in #N, or one Claude Code finds #N should not merge without), push nothing yet: rewrite #N's status line with the state `Blocked: <reason>` first (Skill tool, `mentat:pr`), then reply with a first line "Hold #N: <reason>" and end the turn, saying in plain words, without #N, whether a review round remains.

After the answer, if #N is still open and they want the work in it, remove the item's merge wait where there is one (`mentat:backlog` step 4), build it on #N's branch (the builder), run the tests and push. If the maintainer waives that push's round ("Waived round"), that section replaces the next two sentences. With a round left, update the description for the new head with the state `In review` (Skill tool, `mentat:pr`) and go to step 1 for the new head, within the same five rounds, through the final check and a new "You: merge #N.". With none left, rewrite the status line with the state `Not reviewed: no review round left` and tell the maintainer the new head was not reviewed, with no new "You: merge #N.". In any other case with #N open, first rewrite its status line back to the state it had before the hold; then the work goes on a new branch from the default branch, in its own pull request.

No hold is needed for a question, when #N is merged or closed, or for work that stands apart from #N; any work then goes on a new branch from the default branch, in its own pull request. When #N is closed without merging, remove the item's merge wait (`mentat:backlog` step 4) and leave its status as it is.

When the maintainer says #N merged, do the steps of the item's wait block where there is one (`mentat:backlog` step 4), then mark the item done (`mentat:backlog`), which ends its merge wait, do the repository's own post-merge steps, and report in one line.
