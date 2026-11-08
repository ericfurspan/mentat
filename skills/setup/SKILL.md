---
name: setup
description: "Shows and sets this repository's Mentat settings. Arguments: what to change; with none, shows the settings and asks which to change."
argument-hint: "[what to change]"
disable-model-invocation: true
---

The maintainer wants to see or change this repository's Mentat settings. They live as prose in the repository's AGENTS.md, and this skill adds no config file to the repository; step 5's per-user review tools setting is the one file outside it. This runs once: do it, then normal work resumes. If the maintainer typed text after the command, start from that.

1. Read every AGENTS.md that applies (root and nested, and `AGENTS.override.md` if present, which replaces the AGENTS.md beside it). Show the three effective settings in one line: the backlog (the named external one, else GitHub issues), the test command AGENTS.md names or "not named", and whether a Code Review Rules section exists. Show effective values, never "default". Change nothing yet.
2. Ask only about what is missing or would change, one decision at a time with a recommendation, as `rules.md` "What goes to the maintainer" says. When the maintainer typed what to change, do that. When they typed nothing, ask once which of the three settings to change, naming the missing ones first, with a recommendation. "None" ends the skill: no pull request.
3. The three settings, and the exact lines written to AGENTS.md. A line written replaces the existing sentence for that setting, never sits beside it. When the choice is GitHub issues, the existing backlog sentence is deleted and nothing is written:
   - Backlog: GitHub issues (nothing written); a Linear line already in AGENTS.md is shown as is. To move planning to Linear, the maintainer runs `/mentat:linear`.
   - Test command: the one AGENTS.md names, else the one the repository shows. Confirm it with the maintainer and write it only on a yes. Line: ``The one test command is `<command>`.``
   - Code Review Rules: only when the section is missing; an existing section is the maintainer's and changes only if they ask. Offer this starter under a `## Code Review Rules` heading, for the maintainer to trim:
     - Flag any secret, token or credential added to the repository, including in tests, fixtures and workflow files. Placeholder values that are clearly fake are fine.
     - Flag workflow changes that give a job secrets, write permissions or deploy access it does not need. Workflows should declare `permissions` explicitly and pin third-party actions to a commit SHA.
     - Flag shell scripts that break on paths with spaces or ignore a failing command.
     - Flag only problems with a realistic trigger.
4. Write the lines in one pull request, by the normal path. The maintainer's answers above are the agreement, so the change is not weighed again. The main session edits no files.
   - Put the spec (shape in `mentat:pr`) in the repository's backlog item: a GitHub issue when the backlog stays GitHub issues, or an item in the external backlog when it already has one. Requirements are numbered: the lines in AGENTS.md. "Out of scope:" is last.
   - Run `mentat check`. Brief the `builder` subagent: the lines, the AGENTS.md file to edit (the root one; the override if present), the file's own style, that each line replaces the existing sentence for that setting (and that a backlog sentence is deleted when the choice is GitHub issues), and to leave the rest alone. Run the repository's test command before the push when `rules.md` step 3 calls for it, call the Skill tool with `mentat:pr` for the body and with `mentat:review` for the loop.
5. The review tools setting, for this user in every repository. Step 1 also shows, on a second line, the contents of `~/.config/mentat/reviewers` (the tools `mentat weigh`, `mentat challenge` and `mentat consult` run, any of `claude`, `codex` and `grok`; missing or empty runs Codex and Grok) and `~/.config/mentat/claude-model` (Claude's model; missing picks one). When the maintainer asks, write only those two files, never AGENTS.md, then run `mentat check`; this needs no pull request.
6. End with one line to the maintainer saying what was set. A pending merge goes as "You: merge #N."
