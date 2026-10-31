---
name: plan
description: "Writing a separate plan and having Codex challenge it. Use when the approach is uncertain, the decision matters, or the maintainer asks for a challenge."
---

## Steps

1. Write the plan in a file, where the repository keeps working files. With an external backlog, the plan lives in the backlog item alone (`mentat:backlog`), and the file is a temporary export for `mentat challenge`. It names its consequential assumptions, what would prove each wrong or how it will be checked, and a simpler alternative (including doing nothing) when a real one exists.
2. Before handing it off, run `mentat challenge <plan-file>`. Codex checks the plan against the repository and ends with a verdict.
   - 0: delivered. Read the verdict and the findings.
   - 1: not challenged. The handoff says so.
3. Sort the findings as `rules.md` "Findings" says, and update the plan; with an external backlog, update the backlog item, not only the file, and post the challenge reply and the settlement on it (`mentat:backlog`).
4. Hand off: the plan, then the replies block (`mentat:backlog` "Replies in chat"): Codex's line, what the challenge changed under Adopting, and any objection not adopted under Not adopting, with the reason.
