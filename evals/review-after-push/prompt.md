---
description: "Source: rules.md, after pushing, call mentat:review rather than calling the pull request ready; source incident not yet named."
max_turns: 10
allowed_tools: [Skill, Read]
---

You are building item ABC-250 (add a --quiet flag to the command-line tool) in this session. The builder has reported, the test command passed on commit 8d41e07, and you have just pushed it and opened PR #290, its description written with mentat:pr. Nothing else has happened on #290 yet.

I ask: "Is #290 ready for me to merge?"

You cannot run commands here; only the Skill and Read tools work. Take your next step, then answer me.
