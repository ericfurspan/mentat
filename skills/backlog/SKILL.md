---
name: backlog
description: "Reading or changing the backlog in a repository whose AGENTS.md names a Linear project: ideas, the order of agreed work, plans, evidence and waits on the maintainer. Use before filing, moving or reading a backlog item there."
---

In a repository whose AGENTS.md names a Linear project, the backlog lives in that project, not in GitHub issues. Linear is private, so it holds what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests and, once the maintainer agrees to build something, one issue for it.

1. Find the project with the Linear connector, by the name and team AGENTS.md gives. If the connector's tools are not in the session, load them with ToolSearch (query `linear`). If they are still missing, tell the maintainer Linear is not connected in this session and stop planning work there. Never file an idea or a plan on GitHub instead. The builder does not touch the backlog; this happens in the main session.
2. Status says where an item stands:
   - Backlog: an idea, not agreed. Claude Code's own suggestions and parked items are Backlog too.
   - Todo: agreed.
   - In Progress: a branch or pull request exists.
   - Done, Canceled or Duplicate: how it ended.
3. Type is one of the team's labels for what it is: `Bug`, `Feature` or `Improvement`.
4. A wait on the maintainer: add the `Waiting on you` label, and put at the top of the description a heading saying it waits on the maintainer, then numbered steps and anything to paste (`rules.md` describes the shape). Remove the label when the wait ends.
5. The project description holds a section "Order of agreed work, next first", listing item ids. Update it with the connector's project save, which accepts partial edits, and drop finished items whenever you update it. This replaces the pinned issue.
6. When the maintainer agrees to build something, do all of this before the branch starts. A chat request has no Linear item yet, so create it first, in Claude Code's own words. Then:
   - Open a GitHub issue whose body holds the public-safe request: what to build and how it is checked, in Claude Code's words. A request left in a comment never reaches Codex or Grok, which read the issue body. The GitHub record rules in `rules.md` apply. The issue gets a type label and no stage label, and it does not link to or name the Linear workspace or item.
   - Link the GitHub issue from the Linear item, and the pull request once it exists. Set the item to Todo when agreed, In Progress when the branch exists, and Done when the pull request merges. The pull request closes the issue with `Closes #N` as usual.
7. In Linear, record what the maintainer asked in Claude Code's own words, labeled as Claude Code's summary, plans, and the evidence behind them. Plain words.
