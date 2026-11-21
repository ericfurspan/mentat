# Review depth

Read this when writing a "Ready to merge: #N" message, and again after a compaction.

Right after the "Ready to merge: #N (<item id>)" line, the Ready message carries one review-depth line, derived from what the final check already records: `Review: closely (<reasons>)`, each reason in a few words, or `Review: skim (no listed reason for closer review)`. The line is a prioritization aid, not a safety assessment; the maintainer still decides how to review and merges every pull request. It goes in chat only; the pull request description is unchanged.

The line says closely when any of these holds, and skim otherwise:

- a Risks line, except one only for Grok being unavailable, and except one for a changed agent instruction file whose change alters no guardrail (what an agent may do without the maintainer: merging, pushing, publishing, secrets, approvals, review gates);
- a Decisions line for a call made in the build;
- a Calls made without the maintainer line that files a defect at the round limit or settles a review stop, an extra round or a blocking finding, so a Ready at the round limit with defects filed or stops settled is closely;
- any sentence the Ready message adds, except a weaker review only because Grok is unavailable;
- the agreed spec changed during the build;
- a fast track or waived push, with the reason "not reviewed" for a fast track or "last push not reviewed" for a waived push.

A "Hold #N" line carries no review-depth line. Each new "Ready to merge: #N", after a hold or more rounds, carries a fresh line recomputed for that head.
