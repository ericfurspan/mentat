---
name: grill
description: "Interviews the maintainer on a plan, decision or idea, one question at a time, when they ask to be grilled (\"grill me\"); never unasked."
user-invocable: false
---

The maintainer wants to be questioned about a plan, decision or idea until the two of you agree on it. Grill them on the request in hand. This runs once: do it, then normal work resumes.

1. Finish the step in flight first. Never interrupt a running implementer, review or test run. Then change nothing while the grill runs: no edits, no commits, no GitHub writes. Reading is fine.
2. Read before asking: the code, the files, the backlog item and what the maintainer has said this session. Lay the subject out as a tree of decisions, where settling one opens the ones that depend on it.
3. Ask only the maintainer's decisions: what to make, its scope, cost and order, and a disagreement that blocks. Ask each as a choice among concrete outcomes you bring, never an open question about what they want. Settle implementation questions yourself, as `rules.md` "What goes to the maintainer" says. A fact is never a question: look it up in the code, the files or a tool (a subagent for a long search) before the question that needs it.
4. Ask one decision at a time, as `mentat:plan` "Decisions" gives, never several in one message or prompt. Every question has a "Stop here" answer, last, in either form. A prompt also has that file's not-ready option before it, which goes on in chat, so it has at most two others; never drop either to fit another.
5. Pick each next question from the answers so far: an answer settles its decision and opens the ones that hang on it, and an answer typed in Other can reshape the tree. A changed answer, one reopened through "Change something" included, also reopens the decisions that depended on it, so no stale choice is listed. Ask nothing whose answer depends on a decision still open, and never ask a decision already answered, in the grill or earlier in the session.
6. Stopping: "Stop here", or Other text saying to stop, ends the grill at once. Reply with two short lists: the decisions agreed so far, and those still open. None of the open ones counts as agreed.
7. Ending: when no decision of the maintainer's is open, ask for confirmation in the message form, with a short list of what was agreed that does not count toward its word bound. Its answers: "Yes, that's it" (recommended; ends the grill, nothing is implemented yet); "Change something", which reopens the decision the maintainer names, in their reply or a follow-up; and "Stop here", last, which ends the grill as step 6 says, the decisions agreed so far staying agreed and the list not confirmed. Act on nothing until they confirm. A confirmed list is not agreement to implement: a change still goes through `mentat:plan` (plan check, proposal and agreement), where the decisions answered here count as answered and are not asked again. The plan check's idea file holds the grill's record.

The grill's record: each question as finally asked, its options or answers, the one marked recommended, and the maintainer's answer; for one answered in the talk after a not-ready pick, the answer they gave in that talk. Leave out a question answered "Stop here" or still open after a not-ready pick, and the earlier form of one reopened or replaced: only each decision's final asking stays.
