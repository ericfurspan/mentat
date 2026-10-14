# Credits

The one-sentence intent check in Mentat's review brief (the `review_criteria` function in `lib/shared.sh`, which `mentat review --local` gives local Codex and `mentat review --grok` gives Grok) comes from the Core Workflow of Jeffallan's `code-reviewer` skill ([code-reviewer](https://jeffallan.github.io/claude-skills/skills/quality/code-reviewer/), repository [Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills), MIT License). There, before reviewing, the reviewer summarizes the pull request's intent in one sentence and asks the author to clarify if it cannot. The `review` skill's final check applies the same one-sentence test when Claude Code posts it.

Changes for Mentat: the sentence is written from the linked issue and the diff rather than the description, a disagreement with the description is itself a finding, and the `pr` skill applies the same test to the description before the pull request opens.
