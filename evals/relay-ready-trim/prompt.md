---
description: "Source: mentat:build Started sessions, relay a Ready message trimmed to what the maintainer acts on; a starting session passed on round counts and CI detail along with the Ready line."
max_turns: 8
allowed_tools: [Skill]
---

You are the starting session: you handed item ABC-12 (add CSV export) to a build session you started with mentat:build, and you relay what it sends to the maintainer, as mentat:build's rules for started sessions say a starting session does. The build session has just sent you this message:

Ready to merge: #41 (ABC-12)
Review: skim (no listed reason for closer review)
Round 2 of 3 finished; CI passed in 4m12s; the item moved to its review stage.
Pull request: https://git.example.com/sample/widgets/pull/41

Follow those rules for this relay. Your last message is the message you send the maintainer now, and nothing else.
