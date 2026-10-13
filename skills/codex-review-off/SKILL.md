---
name: codex-review-off
description: "Turns Codex review off for the rest of the session: no Codex pull request reviews (one Claude code-review replaces them) and no plan challenges, until the maintainer says in chat to turn Codex back on. Started by the maintainer."
disable-model-invocation: true
---

The maintainer has turned Codex off for the rest of this session. Until the maintainer says in chat to turn Codex back on, these replace the Codex review loop (`mentat:review`) with one Claude review, and the plan challenge (`mentat:plan` step 2) with nothing. Everything else in `rules.md` holds. After a compaction or a resumed session, Codex stays off; only the maintainer turns it back on, in chat. When they do, say in one line that Codex review is on again; that starts no review by itself. From then on the next review of any pull request, including one that had a Claude review round, is a Codex review (`mentat review`); a Claude review already running finishes and its findings are settled as usual.

When started, say in one line that Codex is off for this session. If a `mentat review` or `mentat challenge` is running, stop it and say so.

## Pull requests

1. Do not call `mentat:review` or run `mentat review`, `mentat review --local` or `mentat review --grok`.
2. Once the test command passes on the head, push and update the description (Skill tool, `mentat:pr`). Its Evidence says the maintainer turned Codex off for this session and the Claude review is still to come; do not claim a review yet. Step 4 updates it.
3. Run `mentat ci <N>`, which waits for CI on the head (up to 30 minutes; with no CI, about a minute) and reviews nothing itself. 0: go on. 3: the head moved; run it again. 4: failing checks: fix them, run the test command, push, and run it again; CI still running at the timeout: tell the maintainer. 1: tell the maintainer.
4. Review with Claude. Call the Skill tool with `code-review` and the args `medium <N>`. Always pass the level: a bare call reuses the last level typed. The level that runs can differ from the one passed, so take the level from the skill's own output. Never pass `--fix`, which would edit files in the main session, or `--comment`.
   - If the review runs in the background, wait for its result before posting. A review that fails, times out or returns nothing is not a pass; it falls under the last bullet.
   - Post that round's findings as one comment on the pull request, and say so when there are none. Start it with `Claude review round <n> on <sha>`, the head reviewed. The comment is the record of each round.
   - Sort each finding as `rules.md` "Findings" says. Batch the fixes into one brief for the `mentat:builder` subagent. When it reports, run the test command, push, update the description (Skill tool, `mentat:pr`), and run `mentat ci <N>` again.
   - Once the round's findings are settled, or there were none, update the description's Evidence (Skill tool, `mentat:pr`) to say reviewed by Claude, not by Codex, with the level the skill reported.
   - One round by default. Run a second only to confirm the fixes of findings the first raised. Two rounds is the most per pull request; after a compaction or a resumed session, count the `Claude review round` comments already on the pull request. A real defect still unfixed after round two goes to the maintainer.
   - If the skill cannot be invoked or fails, do not stand in for it. The final check says "Not reviewed" and why, and the description's Evidence is updated (Skill tool, `mentat:pr`) to say not reviewed and why.
5. Read the diff, the description and the linked issue from GitHub, not from memory, and correct any claim that does not hold. Post one comment, six lines at most: the commit checked and its test and CI results, one sentence stating the pull request's intent, from the request and the diff, and whether it matches the description's, "Reviewed by Claude (code-review, <level>), not by Codex", with the level the skill's own output reports and the model this session ran on, how each finding was settled, what was not checked, and what most deserves the maintainer's eyes. If the Claude review did not run, write "Not reviewed" and why instead. Start it with `Final check on <sha>`, the commit checked.
6. If the pull request is a draft, run `gh pr ready <N>`; if that fails, report it and stop. Tell the maintainer in chat that the pull request is ready to merge, reviewed by Claude and not Codex (or unreviewed, if the review did not run), and stop.

The maintainer merges, as always.

## Plans

When `rules.md` step 2 calls for `mentat:plan`, still write the plan, but do not run `mentat challenge`. The handoff says the plan was not challenged because the maintainer turned Codex off. The Claude review does not apply to plans.
