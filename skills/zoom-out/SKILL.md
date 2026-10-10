---
name: zoom-out
description: "Steps back from the task in hand and gives the maintainer one holistic view: the goal, what is done, what is still unanswered, what looks like weeds, and the next step. Started by the maintainer."
disable-model-invocation: true
---

The maintainer wants the whole picture, not the task in hand. This runs once: do it, then normal work resumes.

1. Finish the step in flight first. Never interrupt a running builder, review or test run. Then change nothing during the zoom-out: no edits, no commits, no GitHub writes. Reading is fine.
2. Read the repository's pinned order issue if there is one, the open issues and pull requests (`gh issue list`, `gh pr list`), and everything the maintainer said in this session.
3. Reply once, in about 250 words. This overrides the output style's 100-word limit. Use these parts, in this order:
   - The goal, in the maintainer's own words where they gave them.
   - What is done this session.
   - Everything the maintainer raised that has no answer or decision yet. This is the part most easily missed: walk every maintainer message, not only the last.
   - What looks like weeds or over-engineering, with evidence (counts, links).
   - One recommended next step. If it needs a decision, end with the output style's closing `## Question` block.
4. If the maintainer typed text after the command, focus the zoom-out on that.
