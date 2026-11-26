# Review stop

Read this at the end of every review round, on resume and after a compaction, from `mentat:review`.

A stop is pending after any completed round from round three on, before the last round within the limit, that posted findings, an outside review's included, fixed or answered alike, until it is settled or answered; a finding raised again with no new evidence after its answer was recorded in Review details does not count, unless it was settled by the maintainer and the text it was about changed since (`findings.md`). A round with no findings from any review goes to the final check. The last round within the limit is no stop: it is neither settled nor asked, leaves no stop pending, and "Round limit" alone decides; a later raise of the limit, the maintainer's or the session's, does not make it one. Once "Ready to merge: #N" was given, `after-ready.md` applies instead.

## Order

At the end of the round, and on resume while the stop is pending:

1. Settle on the evidence below: record the stop (below) and go on, with no question, no blocked state and no wait mark. Ask instead only when the findings, or a disproved assumption still open in the item's recorded assumptions, show the goal or a required safeguard cannot be met without a scope change.
2. To ask: rewrite the Status line with the state `Blocked: reassessing after round <n>` (Skill tool, `mentat:pr`), with an external backlog mark the item as waiting on the answer (`mentat:backlog` "Marking a wait"), and ask the question below. It is the loop's tell-the-maintainer.

Push nothing and commission no fixes until the stop is settled or answered. Fixes, or the final check, follow.

## Evidence

The stop is settled or asked on the reviewers' own finding text, the spec's goal (`mentat:backlog` "Where the spec lives"), and any disproved assumption still open in the item's recorded assumptions (`../backlog/records.md` "Assumptions"). The evidence also gives how much the diff grew from the first round's reviewed range to this round's (`git diff --shortstat` of each range, read from the "Change reviewed" line of that round's local Claude review comment, a round as `mentat status` counts it), whether the findings so far cluster in one file or area, and which outside reviewers were off, unknown or did not run or finish. No new subagent.

## The question

One decision, asked as `rules.md` "What goes to the maintainer" says: go on, shrink or close. Recommend a shrink when a scope change can meet the goal, else a close. Each option says what it does in a few words; the session follows its full effects:

- Go on (a settled stop's only move): fixes that round's findings only, from every review (sorted as `findings.md` says), and keeps the spec (an open disproved assumption stays as it is); it adds no round past the limit and gives no Ready for an unreviewed fix.
- Shrink: asks the scope change as one question, then rewrites the spec and records its fingerprint (`mentat:backlog` "Agreement"). This is how a disproved assumption changes scope. Its new implementation needs a review round within the limit.
- Close: the answer says the pull request closes without merging, nothing in it merges unless it is reopened, its branch is kept and its item is canceled. A close, here or at the round limit, is carried out only from the maintainer's words given after that round ended: their answer to the question, or their own word to close given unprompted after it.

## Round limit

After the last round within the limit (`mentat:review` "Hard stop"), whatever its number, no fix from that round is pushed unless the limit is raised: by the session's extra round below, or by the maintainer.

The extra round: right after that round, the session raises the limit by one itself and asks nothing when all four hold: (1) something is left to fix or implement, or that round did not finish or did not cover the current spec; (2) Review details record no higher limit (the maintainer's or the session's own; a raise the maintainer made counts as the extra round); (3) all that is left to fix or implement is within the agreed spec (a real defect on a head that could otherwise be Ready included); (4) no finding needs a scope change or shows the goal cannot be met. A last round that did not finish or did not cover the current spec counts as no finding against the goal, so a `Not reviewed` limit gets the extra round too. With fixes, they are then implemented, pushed and reviewed as a normal round (`mentat:review` step 4); with none, the extra round reviews the current head as `mentat:review` step 1 says, against the current spec. A higher limit for one pull request, which the session raises itself or the maintainer names in chat, is written to the description as it is raised, before that round's `mentat:builder` brief or review (Skill tool, `mentat:pr`), as the Review details line for a higher round limit, naming whose it is, the session's own also as a line in Decisions and Risks; it is passed as `MENTAT_REVIEW_ROUNDS` to its `mentat review` and `mentat status` runs and reread from Review details after a compaction or resume.

When nothing is left to fix or implement and that round finished and covered the current spec, no round could change the head, so the head is Ready (below) or the maintainer is asked at once.

When the session takes no extra round at this limit, the reviewed head may be Ready, its other conditions holding, only when that round covered the current spec (where `mentat:review` "Spec" applies, `mentat status <N> --request <file>` shows `spec: matches`), the goal and every required safeguard hold on that head, judged on the evidence above, no real defect left unfixed is marked blocking by its reviewer, no finding waits on the maintainer's answer, and no change the maintainer asked for in an answer or in a comment or review on the pull request that needs a push is still not done, answered or not, since declining it is theirs; each real defect left is then filed as a follow-up backlog item (`mentat:backlog` "Filing") and listed in Decisions and Risks (`mentat:pr`), saying it was filed, never naming the backlog's workspace or item (`../backlog/records.md`).

Otherwise, unless only a finding waiting on the maintainer's answer (`findings.md`) keeps the head back, the state is `Not reviewed: <why>` when that round did not finish or did not cover the current spec, else `Blocked: <why>`, and the maintainer is asked one question, the limit question: only after the extra round, or at once when no round could change the head or a finding needs a scope change or shows the goal cannot be met. It names each such request not done and each real defect still unfixed, and why a round was `Not reviewed` where one was. Its answers:

- Raise the limit for this pull request.
- Shrink, as "The question" says; its new implementation needs a review round, so at the limit it also takes a raise.
- Close, as "The question" says.

When a finding needs a scope change or shows the goal cannot be met, the question recommends a shrink when a scope change can meet the goal, else a close. After a raise, the session's extra round included, another raise is recommended only when none of the last round's findings was caused by the previous round's fix and each left is a fix within the agreed spec; otherwise the recommendation follows the raises used, the findings per round and their severity, and the work left, saying what each answer costs (a shrink also takes a raise; a close drops the work). The maintainer may always choose a raise.

## Goal evidence

At any round, new evidence that the change cannot meet its goal or a required safeguard without a scope change sets `Blocked: <why>` (after Ready, a hold as `after-ready.md` says) until the maintainer answers. Advice already considered is not reopened.

## Durable pause

A settled stop is recorded once, before its fixes are commissioned, as one line in the description's Decisions and Risks (`mentat:pr`) naming its round and that it went on. A stop that asks, and a limit question ("Round limit"), gets one Review details line (`mentat:pr`) instead, recording the round, the head, the pending findings and the answer, `pending` until given. A resumed session reads both before fixing or announcing Ready. The session that has the pull request records the answer in that Review details line; the session the maintainer answered in records it on the backlog item as their decision, its decisions line (`mentat:backlog` "Item shape"), and, with an external backlog, ends the stop's wait (`mentat:backlog` "Marking a wait").

## Started sessions

An implementation session another session started settles a stop and takes the round limit's extra round itself, sending no question for either, and sends a question, at a stop or the limit, to its starting session and waits only when one is asked (`mentat:build` "Started sessions"). On a "close" the starting session forwards with the maintainer's words (`mentat-lead:orchestrate`), the implementation session closes the pull request without merging, keeps its branch and writes the Review details line. An answer the maintainer gives in the implementation session is acted on there, and with no starting session that session asks the maintainer itself, under the same rules. No forwarded write, no second ask.
