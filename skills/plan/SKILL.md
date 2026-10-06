---
name: plan
description: "Writing a separate plan and having Codex challenge it. Use when the approach is uncertain, the decision matters, or the maintainer asks for a challenge."
---

A separate plan is written only when the approach is uncertain or the decision matters; the maintainer can also ask for a challenge at any time. The scope statement in the issue or pull request (`rules.md` step 2) is still written either way.

## Steps

1. Write the plan in a file, where the repository keeps working files.
2. Before handing it off, run `mentat challenge <plan-file>`. Codex checks the plan against the repository and ends with a verdict.
   - 0: delivered. Read the verdict and the findings.
   - 1: not challenged. The handoff says so.
3. Sort the findings as `rules.md` "Findings" says, and update the plan.
4. Hand off: the maintainer sees the plan with what the challenge changed, and any objection Claude Code did not adopt, with the reason.

A challenge never counts as a review.
