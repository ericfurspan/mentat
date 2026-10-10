---
name: codex-review-on
description: "Turns Codex review back on after /mentat:codex-review-off: pull requests go through the Codex review loop and plans through the Codex challenge again. Started by the maintainer."
disable-model-invocation: true
---

The maintainer has turned Codex back on. The `codex-review-off` rules no longer apply for the rest of this session, after a compaction or a resumed session too, until the maintainer turns Codex off again. From now on, pull requests go through the Codex review loop (`mentat:review`) and plans through the Codex challenge (`mentat:plan` step 2), as `rules.md` says.

When started, say in one line that Codex review is on for this session. This starts no review by itself, and a pull request already in a Claude review round finishes that round under the off rules unless the maintainer asks otherwise.

If Codex was already on, say so and change nothing.
