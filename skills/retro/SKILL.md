---
name: retro
description: "Looks back at a session and lists what would have made it go better: changes to Mentat, the repository's AGENTS.md, automated checks and tooling, ranked by severity with evidence. Started by the maintainer."
disable-model-invocation: true
---

The maintainer wants to know what would have made the session go better. This runs once: do it, then normal work resumes. Default to the current session. If the maintainer typed text after the command, focus the retro on that, or on the session it names.

1. Finish the step in flight first. Never interrupt a running builder, review or test run. Then change nothing (no edits, no commits, no GitHub writes) until the maintainer has answered the last candidate. Reading is fine.
2. Read the primary sources: what happened in the session (the maintainer's messages, commands and their results, builder reports, review findings), `rules.md`, the output style, the skills and the builder agent, the repository's AGENTS.md files, and its test command and hooks. For another session, read its log on this machine.
3. Look for candidates in these places. Each has a "use when"; skip a place that does not apply.
   - Mentat's own workflow: a rule, skill, output style or builder instruction that made the session slower or wrong. Use when the session went the wrong way and Mentat told it to.
   - Automated checks: a mistake a check could have caught gets a check (the repository's test command, a lint or a hook), not a new rule. Rules are for judgement calls. Read the existing check first, so a check that exists but is unwired or broken is the finding. Use when something slipped through that a machine could see.
   - The repository's AGENTS.md: steering that should be a check, a pointer to a doc, or gone. Use when the file is large or the agent ignored it.
   - Navigation: how long the agent took to find the right file, and whether a pointer would have saved it. Use when finding something took many steps.
   - Tool economy: expensive calls that could be cheaper, such as a huge output read whole. Use when a call cost a lot for little.
   - Instructions that change nothing: steering that would not alter what an agent does. Use when a file is large.
   - Information the agent lacked: logs, access or context that would have settled something early. Use when a crucial fact was missing.
4. Present the candidates one at a time, worst first. This replaces the output style's line limit while it runs. Each is in plain words:
   - What happened, and what it means for the maintainer.
   - The recommendation: what to change, and where it would go (the file, the check or the hook).
   - Its evidence from the session in one short line: a short quote, a command and its result, or a link. Quotes never include credentials or tokens.
   Leave out a candidate with no evidence. If nothing is worth changing, say so.
5. Each candidate is asked file or skip in the message text, with the candidate above it and no tool call after it; the next candidate follows the answer. Once the last candidate is answered, the retro is over, and Claude Code files the agreed ones as issues. Nothing is filed without the maintainer's agreement.
