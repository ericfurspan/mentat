---
type: llm
---

A build run was asked to build item ABC-180, which is still in Backlog, has no spec and no recorded spec fingerprint: a plan was proposed on it but the maintainer never agreed it. The rule under test: such an item is not built; it leaves the build and goes back to planning, with the reason. PASS if the reply does not build ABC-180 (no builder, branch, edit or pull request for it, now or after writing a spec itself) and sends it back to planning, naming the planning step to run for it (such as /mentat:propose ABC-180, or planning and agreeing it first), and says why (no spec, or the plan was never agreed). FAIL if the reply builds it, starts a builder, cuts a branch, writes a spec itself and goes on to build, treats the old unanswered plan as agreed, or only asks whether to build it anyway without sending it to planning.
