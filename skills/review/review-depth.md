# Review depth

Read this when writing, repeating or relaying a "Ready to merge: #N" message, and again after a compaction.

Right after the "🔔 Ready to merge: #N (<item id>)" line, the Ready message carries one review-depth line, derived from what the final check already records: `Review: closely (<reasons>)`, each reason in a few words, or `Review: skim (no listed reason for closer review)`. The line is a prioritization aid, not a safety assessment; the maintainer still decides how to review and merges every pull request. It goes in chat only; the pull request description is unchanged.

The line says closely when any of these holds, and skim otherwise:

- a Risks line, except one only for Grok being unavailable, and except one for a changed agent instruction file whose change alters no guardrail (what an agent may do without the maintainer: merging, pushing, publishing, secrets, approvals, review gates);
- a Decisions line for a call made in the build;
- a Calls made without the maintainer line that files a defect at the round limit or settles a review stop, an extra round or a blocking finding, so a Ready at the round limit with defects filed or stops settled is closely;
- any sentence the Ready message adds, except a weaker review only because Grok is unavailable;
- the agreed spec changed during the build;
- a fast track or waived push, with the reason "not reviewed" for a fast track or "last push not reviewed" for a waived push.

A "Hold #N" line carries no review-depth line. Each new "Ready to merge: #N", after a hold or more rounds, carries a fresh line recomputed for that head.

## Push notice

The Ready line starts with "🔔 ", and every repeat or relay of it keeps it word for word, the icon included. A "Hold #N" line, a Blocked or Not reviewed report and a question get no icon and no push, and the pull request's Status line stays as `mentat:pr` gives it.

A session that shows the maintainer a Ready line in its own chat for the first time then sends one push notification, when it has a push-notification tool (in Claude Code, `PushNotification`), naming the repository, the pull request, the item and a few words of its title, in at most about 150 characters. The line is in chat before the push, and nothing waits on the push. Ready lines first shown in one turn share one push naming each. A Ready line for a new head after a hold counts as first shown; one shown again, such as when listing what waits on the maintainer, sends none. A session started by another session sends none; the starting session that relays the line sends it. With no such tool, or when the push is not sent, fails or is refused, go on: no retry, no report.
