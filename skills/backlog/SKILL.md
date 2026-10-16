---
name: backlog
description: "Reading or changing the backlog in a repository with an external backlog (one its AGENTS.md names, outside GitHub): ideas, the order of agreed work, plans, evidence, the agreed request and waits on the maintainer. Use before filing, moving or reading a backlog item there."
---

In a repository with an external backlog (`rules.md` Records), the backlog lives there, not in GitHub issues, and its item is the only record of a change: the idea, the plan, the evidence, the status and the agreed request. The backlog is private, so it can hold what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests only; no issue is opened for agreed work. AGENTS.md names the tracker. Steps 1 to 7 hold for any tracker; "Tracker: Linear" below holds the tool-specific parts, and a different tracker replaces only that part.

1. Reach the backlog with the tracker's tools, by the name AGENTS.md gives. If the tools are not in the session, tell the maintainer the backlog is not connected in this session and stop planning work there. Never file an idea or a plan on GitHub instead. The builder does not touch the backlog; this happens in the main session.
2. Status says where an item stands:
   - Idea: not agreed. Claude Code's own suggestions and parked items are ideas too.
   - Agreed.
   - In progress: a branch or pull request exists.
   - Ended: done, canceled or duplicate.
3. Type is one of: bug, feature or improvement.
4. A wait on the maintainer: mark the item as waiting, and put at the top of the description a heading saying it waits on the maintainer, then numbered steps and anything to paste (`rules.md` describes the shape). Remove the mark when the wait ends.
5. The order of agreed work, next first, is kept in one place in the backlog, listing item ids. Drop finished items whenever you update it. This replaces the pinned issue.
6. When the maintainer agrees to build something, do all of this before the branch starts. A chat request has no item yet, so create it first, in Claude Code's own words. Then:
   - Write an "Agreed request" section in the item: what to build, what to leave alone, and how the result is checked, as agreed. Codex and Grok review the change against this section, and their comments are public, so write it in public-safe words: the `rules.md` record rules apply, and it never names the backlog's workspace or item. Private notes are evidence, not requirements. A requirement that cannot be stated in public cannot be reviewed against, so say that to the maintainer, who decides.
   - A change of scope updates the section, in the same words.
   - Mark the item agreed once the maintainer agrees, in progress when the branch exists, and done when the pull request merges. Link the pull request from the item once it exists. The pull request writes no `Closes #`.
   - Before each `mentat review --local` or `mentat review --grok`, copy the section unchanged into a temporary file (`mktemp`), pass it with `--request <file>`, and remove the file afterwards. The posted review records the first 12 hex characters of the SHA-256 of that text; `mentat:review` compares it with the current section: `printf '%s' "$(cat <file>)" | shasum -a 256 | cut -c1-12`.
7. In the item, record what the maintainer asked in Claude Code's own words, labeled as Claude Code's summary, plans, and the evidence behind them. Plain words.

## Tracker: Linear

For a repository whose AGENTS.md names a Linear project, by name and team.

- Step 1: find the project with the Linear connector, by that name and team. If the connector's tools are not in the session, load them with ToolSearch (query `linear`); if they are still missing, Linear is not connected: step 1 applies.
- Step 2: statuses are Backlog (idea), Todo (agreed), In Progress, and Done, Canceled or Duplicate.
- Step 3: type is one of the team's labels: `Bug`, `Feature` or `Improvement`.
- Step 4: add the `Waiting on you` label; remove it when the wait ends.
- Step 5: the order is a section "Order of agreed work, next first" in the project description. Update it with the connector's project save, which accepts partial edits.
- The item is a Linear issue in that project.
