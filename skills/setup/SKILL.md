---
name: setup
description: "Shows and sets Mentat's per-repository settings (the backlog, how pull requests are reviewed, the test command and the Code Review Rules), which live as prose in the repository's AGENTS.md, including moving a repository's planning from GitHub issues to a Linear project. Started by the maintainer."
disable-model-invocation: true
---

The maintainer wants to see or change this repository's Mentat settings. They live as prose in the repository's AGENTS.md. There is no config file, and this skill adds none. This runs once: do it, then normal work resumes. If the maintainer typed text after the command, start from that.

1. Read every AGENTS.md that applies (root and nested, and `AGENTS.override.md` if present, which replaces the AGENTS.md beside it). Show the four effective settings in the form `rules.md` uses at session start: the backlog (the named external one, else GitHub issues), reviews (local when AGENTS.md says so or an external backlog is named, else the Codex app), the test command AGENTS.md names or "not named", and whether a Code Review Rules section exists. Show effective values, never "default". Change nothing yet.
2. Ask only about what is missing or would change, one decision per message with a recommendation (`rules.md`, "What goes to the maintainer", says how). Start with what the maintainer typed. Then offer the test command and the Code Review Rules when they are missing. Last, ask whether to change the backlog or reviews, unless the maintainer already covered them (recommend no change). If nothing changes, say so and stop: no pull request.
3. The four settings, and the exact lines written to AGENTS.md:
   - Backlog: GitHub issues (nothing written) or a Linear project in a named team. Line: ``The external backlog is the Linear project `<name>`, in team `<team>`.`` Recommend the repository's name as the project name.
   - Reviews: local or the Codex app. Line for local: ``Pull request reviews in this repository are local: run `mentat review --local <N>`. The Codex GitHub app does not review here.`` When the backlog is external, reviews are local by rule: skip the question, say why, and write no line.
   - Test command: the one AGENTS.md names, else the one the repository shows. Confirm it with the maintainer and write it only on a yes (`rules.md` adds none unasked). Line: ``The one test command is `<command>`.``
   - Code Review Rules: only when the section is missing; an existing section is the maintainer's and changes only if they ask. Offer this starter under a `## Code Review Rules` heading, for the maintainer to trim:
     - Flag any secret, token or credential added to the repository, including in tests, fixtures and workflow files. Placeholder values that are clearly fake are fine.
     - Flag workflow changes that give a job secrets, write permissions or deploy access it does not need. Workflows should declare `permissions` explicitly and pin third-party actions to a commit SHA.
     - Flag shell scripts that break on paths with spaces or ignore a failing command.
     - Flag only problems with a realistic trigger.
4. Write the lines in one pull request, by the normal path. The maintainer's answers above are the agreement, so the change is not weighed again. The main session edits no files.
   - Put the spec (shape in `mentat:pr`) in the repository's backlog item: a GitHub issue when the backlog stays GitHub issues, an item in the external backlog when it already has one, or the switch item (step 5) when switching to Linear. Requirements are numbered: the lines in AGENTS.md, and, when switching, the migration and the closes. "Out of scope:" is last.
   - Run `mentat check`. Brief the `builder` subagent: the lines, the AGENTS.md file to edit (the root one; the override if present), the file's own style, and to leave the rest alone. Run the repository's test command on a clean tree before the push, call the Skill tool with `mentat:pr` for the body and with `mentat:review` for the loop.
   - When switching, the pull request reads its spec from the switch item, and every review is `mentat review --local --request <file> <N>` (and `--grok`), since AGENTS.md names the backlog only once the pull request merges. The pull request body writes no `Closes #`.
5. Linear, when chosen. Load the Linear connector tools with ToolSearch (query `linear`). If they are missing, Linear is not connected: say so and stop; nothing has been created. Then, in order:
   - Find the team by name. If it is not there, stop and say so.
   - If a project of the chosen name exists in the team, stop and show it to the maintainer.
   - Create the project with the description in `mentat:backlog` ("Tracker: Linear", new project description), the repository's name filled in, and the maintainer as lead.
   - Create the switch item first: title `chore: move planning from GitHub issues to this backlog`, label Improvement, status Todo, an opening sentence, and a `## Spec` holding the AGENTS.md line, the migration and the closes, in public-safe words that name neither the workspace nor an item. Set it In Progress when the branch exists.
   - Migrate the open issues (step 6), then add its wait block (`mentat:backlog` step 4) and the `Waiting on you` label when the pull request is open: the closes wait on the merge.
6. Migration. One open GitHub issue at a time, from the main session (the builder never touches the backlog). Skip the pinned issue: its order moves to the project, and the issue itself is left for the maintainer.
   1. List the open issues. An open issue that an open pull request still closes (`Closes #N` in its body) is not migrated: list those to the maintainer in one message, recommending they stay on GitHub until that pull request merges. Do not close them.
   2. Read the issue: `gh issue view <N> --json title,body,labels,state`.
   3. The spec is the issue's `## Spec` section, else its `## Agreed request`, heading kept, copied without rewording (pass the text through, never retype it). The item follows the item shape in `mentat:backlog`: an opening sentence in Claude Code's words; the issue's `## Waits on the maintainer` section first when it has one, with the `Waiting on you` label; the spec; `## Current plan` when the issue has one. Anything else in the body goes in the item's first comment, unchanged, labeled as copied from GitHub issue #N. The issue's own comments stay on the issue.
   4. Type from the label: `bug` is Bug, `enhancement` is Feature, else Improvement.
   5. Status. With stage labels: `idea` is Backlog, `ready` is Todo, `in progress` is In Progress, `waiting` is the stage it would have without the wait, plus the `Waiting on you` label. Without them: In Progress when a branch or open pull request for it exists (`git ls-remote --heads origin`, `gh pr list --state open`), else Backlog (an idea with no spec lands there); an issue that waits on the maintainer gets the same, plus the `Waiting on you` label. When the state is ambiguous (a waiting issue with no branch, for one), ask the maintainer.
   6. A pull request linked from the issue is linked from the item.
   7. After each item is created, add or update one comment on the switch item mapping GitHub issue numbers to item ids, and listing the issues left for the maintainer. Its first line says Linear re-serializes Markdown, so specs there match in wording, not byte for byte. An interrupted run resumes from that comment and never creates an item twice: before creating, also search the project for an item of the same title.
   8. When all are done, set the project's order of agreed work (`mentat:backlog` step 5): the switch item first, then the migrated In Progress and Todo items in the pinned issue's order, else by issue number. Replace "Nothing agreed is waiting." in the project description.
7. Closing the GitHub issues waits on the merge of the AGENTS.md pull request. Until then the switch item's wait block says so. When the maintainer says it merged, or any later session finds it merged (`gh pr view <N> --json state`) while the switch item is not Done, for each migrated issue, using the mapping comment:
   ```
   gh issue close <N> --reason "not planned" --comment "Planning for this repository moved to its backlog outside GitHub on <date>; this issue's content lives there now. Pull requests stay on GitHub."
   ```
   The comment links nothing. Then set the switch item to Done, remove its wait block and label, and drop it from the project's order. From then on a pull request body here writes no `Closes #`. The issues left for the maintainer's decision stay as they are.
8. End with one line to the maintainer: what was set, and what waits on them (the merge, a decision about a listed issue, the pinned issue to close or unpin, or nothing).
