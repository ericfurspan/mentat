# Review stop

Read this at the end of every review round, on resume and after a compaction, from `mentat:review` or `mentat:claude-review`.

A stop is pending after any completed round from round three on (round two on the Claude-only path, `mentat:claude-review`) that posted findings, Codex's included, fixed or answered alike. A round with no findings from either review goes to the final check. The five-round hard stop still holds; at round five the stop comes first. Once "Ready to merge: #N" was given, `after-ready.md` applies instead.

## Order

At the end of the round, and on resume while the answer is pending:

1. Rewrite the Status line with the state `Blocked: reassessing after round <n>` (Skill tool, `mentat:pr`).
2. On the `mentat review` path, where `mentat reviewers` prints `reviewers: on`, `grok` is installed and `mentat status <N>` shows `grok stop: none`, run `mentat review --grok --stop <N>`, with `--request <file>` and `--require-ci` as `mentat:review` "Spec" and step 1 say; exit 3 runs it again. With any other `grok stop:` value, run nothing: re-read its comment, naming its head and spec fingerprint from that field (`running on` is did not finish unless this session's own run is still going). On the Claude-only path Grok is off.
3. Ask the question below. It is the loop's tell-the-maintainer.

Push nothing and commission no fixes until the answer. Fixes, or the final check, follow it.

## Evidence

The reviewers' own finding text, the spec's goal, Grok's stop review, and any disproved material assumption still open in the item's latest assumptions comment (`mentat:backlog` "Material assumptions"). When Grok is not installed, outside reviewers are off or unknown, or Grok did not finish or refused, the question says so; with outside reviewers off, it does not call the review weaker. No new subagent.

## The question

One decision, asked as `rules.md` "What goes to the maintainer" says: go on, shrink or close. Recommend close or shrink when the findings show the goal or a required safeguard is still missed; go on for ordinary defects. Each option says what it does in a few words inside the word bound; the session follows its full effects:

- Go on: fixes that round's findings only, from the local review and Codex, Grok's stop review findings among them (sorted as `findings.md` says), and keeps the spec (an open disproved assumption stays as it is); it adds no round past the limit and gives no Ready for an unreviewed fix. On the Claude-only path, its fixes get no further round and no Ready. Fixes left with no round end as `Not reviewed: no review round left`.
- Shrink: asks the scope change as one question, then rewrites the spec and records its fingerprint (`mentat:backlog` "Agreement"). This is how a disproved assumption changes scope. Its rebuild needs a review round within the limit, else `Not reviewed: no review round left`.
- Close: closes the pull request and cancels the item.

## Goal evidence

At any round, new evidence that the change cannot meet its goal sets `Blocked: <why>` (after Ready, a hold as `after-ready.md` says) until the maintainer answers. Advice already considered is not reopened.

## Durable pause

One Review details line (`mentat:pr`) records the round, the head, the pending findings, Grok's stop result and the answer, `pending` until given. A resumed session reads it before fixing or announcing Ready. The session that has the pull request records the answer there; the session the maintainer answered in records it on the backlog item as their decision.

## Started sessions

A build session another session started sends the question to its starting session and waits (`rules.md` "Sessions"). On close, the starting session cancels the item from the maintainer's answer, then forwards "close"; the build session closes the pull request and writes the Review details line. No relayed write, no second ask.

## Grok coverage

Grok's plain review covers the first head by design, so only its spec can be older; its stop review can be on an older head or spec. Either is disclosed in `mentat:review` "Final check", never a reason for another round.
