---
name: plan
description: "Writing a separate plan and having Codex challenge it. Use when the approach is uncertain, the decision matters, or the maintainer asks for a challenge."
---

A separate plan is written when `rules.md` step 2 calls for this skill. The scope statement that step requires is still written either way.

## Steps

1. Write the plan in a file, where the repository keeps working files. It names its consequential assumptions, what would prove each wrong or how it will be checked, and a simpler alternative (including doing nothing) when a real one exists.
2. Before handing it off, run `mentat challenge <plan-file>`. Codex checks the plan against the repository and ends with a verdict.
   - 0: delivered. Read the verdict and the findings.
   - 1: not challenged. The handoff says so.
3. Sort the findings as `rules.md` "Findings" says, and update the plan.
4. Hand off: the maintainer sees the plan with what the challenge changed, and any objection Claude Code did not adopt, with the reason.

A challenge never counts as a review.
