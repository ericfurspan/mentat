---
name: zoom-out
description: "Steps back from the task in hand and gives the maintainer one holistic view: the goal, what is done, what is still unanswered, what looks like weeds, and the next step. Started by the maintainer."
disable-model-invocation: true
---

The maintainer wants the whole picture, not the task in hand. This runs once: do it, then normal work resumes. If the maintainer typed text after the command, focus the zoom-out on that.

1. Finish the step in flight first. Never interrupt a running builder, review or test run. Then change nothing during the zoom-out: no edits, no commits, no GitHub writes. Reading is fine.
2. Read the backlog. Where the repository has an external backlog, read it through `mentat:backlog`: its order of agreed work and open items. Otherwise read the repository's pinned order issue if there is one, and the other open issues too. Open pull requests are read from GitHub either way. Then read everything the maintainer said in this session.
3. Reply once, in about 250 words. This skill sets the reply's shape while it runs. If it runs long, shorten the other parts, never the list of unanswered asks. Use these parts, in this order:
   - The goal, as the opening paragraph of `rules.md` gives it, plus anything the maintainer said this session that differs from it, in their own words.
   - What is done this session.
   - Everything the maintainer raised that has no answer or decision yet. This is the part most easily missed: walk every maintainer message, not only the last. If the session was compacted and early messages survive only as a summary, say so here: asks from before it may be missing.
   - What looks like weeds or over-engineering, with evidence (counts, links).
   - Are we solving the right problem, and is there a better approach? Answer in one or two sentences.
   - Whether the goal or the plan itself should change, said plainly, not only the next step.
   - One recommended next step. If it needs a decision, ask it after the reply, as `rules.md` "What goes to the maintainer" says.
