# Review stop

Read this at the end of every review round, on resume and after a compaction, from `mentat:review`.

A stop is pending after any completed round from round three on that posted findings, Codex's included, fixed or answered alike, until it is settled or answered. A round with no findings from either review goes to the final check. The last round within the limit has no stop: "Round limit" applies. Once "Ready to merge: #N" was given, `after-ready.md` applies instead.

## Order

At the end of the round, and on resume while the stop is pending:

1. Where `mentat reviewers` prints `reviewers: on`, `grok` is installed and `mentat status <N>` shows `grok stop: none`, run `mentat review --grok --stop <N>`, with `--request <file>` and `--require-ci` as `mentat:review` "Spec" and step 1 say; exit 3 runs it again. With any other `grok stop:` value, run nothing: re-read its comment, naming its head and spec fingerprint from that field (`running on` is did not finish unless this session's own run is still going). Wait for it.
2. Settle on the evidence below: for ordinary defects, record the stop (below) and go on, with no question, no blocked state and no wait mark. Ask instead only when the findings show the goal or a required safeguard is still missed, a disproved material assumption is open, or the session is unsure.
3. To ask: rewrite the Status line with the state `Blocked: reassessing after round <n>` (Skill tool, `mentat:pr`), with an external backlog mark the item as waiting on the answer (`mentat:backlog` "Marking a wait"), and ask the question below. It is the loop's tell-the-maintainer.

Push nothing and commission no fixes until the stop is settled or answered. Fixes, or the final check, follow.

## Evidence

The stop is settled or asked on the reviewers' own finding text, the spec's goal (`mentat:backlog` "Where the spec lives"), Grok's stop review, and any disproved material assumption still open in the item's recorded assumptions (`mentat:backlog` "Material assumptions"). The evidence also gives how much the diff grew from the first round's reviewed range to this round's (`git diff --shortstat` of each range, read from the "Change reviewed" line of that round's local Claude review comment, a round as `mentat status` counts it) and whether the findings so far cluster in one file or area; the question names both in a few words. When Grok is not installed, outside reviewers are off or unknown, or Grok did not finish or refused, the question says so; with outside reviewers off, it does not call the review weaker. No new subagent.

## The question

One decision, asked as `rules.md` "What goes to the maintainer" says: go on, shrink or close. Recommend close or shrink when the findings show the goal or a required safeguard is still missed. Each option says what it does in a few words; the session follows its full effects:

- Go on (a settled stop's only move): fixes that round's findings only, from the local review and Codex, Grok's stop review findings among them (sorted as `findings.md` says), and keeps the spec (an open disproved assumption stays as it is); it adds no round past the limit and gives no Ready for an unreviewed fix.
- Shrink: asks the scope change as one question, then rewrites the spec and records its fingerprint (`mentat:backlog` "Agreement"). This is how a disproved assumption changes scope. Its rebuild needs a review round within the limit.
- Close: closes the pull request and cancels the item.

## Round limit

After the last round within the limit (`mentat:review` "Hard stop"), whatever its number, no fix from that round is pushed. The reviewed head may be Ready, its other conditions holding, only when that round covered the current spec (where `mentat:review` "Spec" applies, `mentat status <N> --request <file>` shows `spec: matches`), the goal and every required safeguard hold on that head, judged on the evidence above (Grok's stop review included, run as "Order" step 1 says, when that round is from round three on and posted findings), and no finding left unfixed is marked blocking by its reviewer; each real defect left is then filed as a follow-up backlog item (`mentat:backlog` "Filing") and listed in Calls made without the maintainer (`mentat:pr`), saying it was filed, never naming the backlog's workspace or item (`../backlog/records.md`). Otherwise the state is `Not reviewed: <why>` when that round did not finish or did not cover the current spec, else `Blocked: <why>`, and the maintainer is asked one question, naming each real defect still unfixed: close, or raise the limit for this pull request; it says a shrink also needs a review round.

## Goal evidence

At any round, new evidence that the change cannot meet its goal sets `Blocked: <why>` (after Ready, a hold as `after-ready.md` says) until the maintainer answers. Advice already considered is not reopened.

## Durable pause

A settled stop is recorded once, before its fixes are commissioned, as one line in the description's Calls made without the maintainer (`mentat:pr`) naming its round and that it went on. A stop that asks gets one Review details line (`mentat:pr`) instead, recording the round, the head, the pending findings, Grok's stop result and the answer, `pending` until given. A resumed session reads both before fixing or announcing Ready. The session that has the pull request records the answer there; the session the maintainer answered in records it on the backlog item as their decision, its decisions line (`mentat:backlog` "Item shape"), and, with an external backlog, ends the stop's wait (`mentat:backlog` "Marking a wait").

## Started sessions

A build session another session started settles an ordinary stop itself, and sends a question, at a stop or the limit, to its starting session and waits only when one is asked (`mentat:build` "Started sessions"). On close, the starting session cancels the item from the maintainer's answer, then forwards "close"; the build session closes the pull request and writes the Review details line. No relayed write, no second ask.

## Grok coverage

Grok's plain review covers the first head by design, so only its spec can be older; its stop review can be on an older head or spec. Either is disclosed in `mentat:review` "Final check", never a reason for another round.
