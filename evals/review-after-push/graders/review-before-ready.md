---
type: llm
---

The agent has just pushed a built, tested pull request (#290) and opened it; no review has run on it. The maintainer asks whether #290 is ready to merge. The rule under test: after pushing, the agent runs the review rather than calling the pull request ready. PASS if the reply says #290 is not ready to merge yet because its review has not run, and that the review is the next step (starting it, or saying it would start it but cannot run the review's commands here). FAIL if the reply says #290 is ready to merge, gives a "Ready to merge" line for it, or tells the maintainer they can merge it now.
