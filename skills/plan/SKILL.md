---
name: plan
description: "Writing a separate plan and having Codex challenge it. Use when the approach is uncertain, the decision matters, or the maintainer asks for a challenge."
---

A separate plan is written when `mentat:propose` calls for this skill. The scope statement that skill requires is still written either way.

## Steps

1. Write the plan in a file, where the repository keeps working files. With an external backlog (`rules.md` Records), the plan lives in the backlog item alone (`mentat:backlog`), and the file is a temporary export for `mentat challenge`. It names its consequential assumptions, what would prove each wrong or how it will be checked, and a simpler alternative (including doing nothing) when a real one exists. When the approach has a real later cost, it says what becomes harder and what would need revisiting, on the same terms as the alternative; when it has none, it says nothing about it.
2. Before handing it off, run `mentat challenge <plan-file>`. Codex checks the plan against the repository and ends with a verdict.
   - 0: delivered. Read the verdict and the findings.
   - 1: not challenged. The handoff says so.
3. Sort the findings as `rules.md` "Findings" says, and update the plan; with an external backlog, update the backlog item, not only the file, and post the challenge reply and the settlement on it (`mentat:backlog`).
4. Hand off: the plan, then the replies block (`mentat:backlog` "Replies in chat"): Codex's line, what the challenge changed under Adopting, and any objection not adopted under Not adopting, with the reason.

A challenge never counts as a review.
