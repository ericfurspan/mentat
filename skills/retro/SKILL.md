---
name: retro
description: "Retrospective on a coding session: finds what in the setup made the work harder and proposes fixes to the setup, not the code."
disable-model-invocation: true
---

The maintainer has asked for a retrospective. Its subject is the **setup** the agent worked in: the repository's checks, instructions, review rules and tools, and Mentat's own workflow. The code is not its subject. The goal is that the same problem does not happen again.

## Steps

1. Pick the session: the one the maintainer names, or else the current one. Claude Code keeps sessions as `~/.claude/projects/<working directory, with each / as ->/<session id>.jsonl`. Read what the session did, not only how it ended: tool calls, errors, retries, waits, and the maintainer's corrections.
2. Read the setup it ran under: every AGENTS.md that applies, the repository's test command, CI workflows, pre-commit hooks, and the `## Code Review Rules` section that Codex reads.
3. Find candidates, using the categories below. Each needs evidence from the session: what happened, and roughly when.
4. For each candidate, name the fix and where it goes. A mechanical rule (a pattern, a banned call, a file location, a command that must pass) becomes a **check**: a test, a lint rule, a pre-commit hook or a CI job, whichever the repository already has. Only a judgment call becomes a written **review rule** in `## Code Review Rules`. A fix to Mentat's own workflow (`rules.md`, its skills, `bin/mentat`, its hooks) belongs in Mentat's repository, not the project's.
5. Present the candidates to the maintainer, most severe first, each in two or three lines: the problem with its evidence, the fix, where it goes. Done when every candidate has evidence and a destination.
6. Change nothing until the maintainer approves. An approved candidate becomes an issue in the repository it belongs to, or a pull request through the normal flow.

## Categories

| Look for | Fix |
|---|---|
| A long search for a file, fact or command | A pointer in a file the agent already reads |
| A mistake a check could have caught; a repository with no check running in CI or a pre-commit hook | A check; a missing or broken one is itself the finding |
| A problem review should have caught and did not | A check if it is mechanical, else a rule in `## Code Review Rules` |
| An always-loaded file (AGENTS.md, `rules.md`) that is long, or holds something only one task needs | Move it to a skill, a doc behind a pointer, or a check |
| An instruction that changes nothing the agent does | Delete it |
| An expensive or slow tool call, or a step the agent waited on with nothing to wake it | Streamline it, or move the wait into a script |
| Information the agent needed and could not reach | Give it read access, or say where it lives |
| The same correction from the maintainer more than once | The rule or check that makes it unnecessary |

## Reference

- The builder carries the most context: it explores, writes and debugs. The reviewer reads a diff. Standards belong in review, not in the builder's always-loaded instructions.
- Always-loaded files cost every session. Keep them to what must hold everywhere, plus pointers.
- Session logs can hold credentials. Quote only the lines that carry the signal, and write `<REDACTED>` for any token, key or password.
- One session can overweight a one-off. Say when a candidate rests on a single occurrence.
