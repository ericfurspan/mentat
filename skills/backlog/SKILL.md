---
name: backlog
description: "Reading or changing the backlog in a repository whose AGENTS.md names a Linear project: ideas, the order of agreed work, plans, evidence and waits on the maintainer. Use before filing, moving or reading a backlog item there."
---

In a repository whose AGENTS.md names a Linear project, the backlog lives in that project, not in GitHub issues, and the Linear item is the only record of a change: the idea, the plan, the evidence, the status and the agreed request. Linear is private, so it can hold what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests only; no issue is opened for agreed work.

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
   - Write an "Agreed request" section in the item: what to build, what to leave alone, and how the result is checked, as agreed. Codex and Grok review the change against this section, and their comments are public, so write it in public-safe words: the `rules.md` record rules apply, and it never names the Linear workspace or item. Private notes are evidence, not requirements. A requirement that cannot be stated in public cannot be reviewed against, so say that to the maintainer, who decides.
   - A change of scope updates the section, in the same words.
   - Set the item to Todo when agreed, In Progress when the branch exists, and Done when the pull request merges. Link the pull request from the item once it exists. The pull request writes no `Closes #`.
   - Before each `mentat review --local` or `mentat review --grok`, copy the section unchanged into a temporary file (`mktemp`), pass it with `--request <file>`, and remove the file afterwards. The posted review records the first 12 hex characters of the SHA-256 of that text; `mentat:review` compares it with the current section: `printf '%s' "$(cat <file>)" | shasum -a 256 | cut -c1-12`.
7. In Linear, record what the maintainer asked in Claude Code's own words, labeled as Claude Code's summary, plans, and the evidence behind them. Plain words.
