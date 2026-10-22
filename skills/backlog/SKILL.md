---
name: backlog
description: "Reading or changing the backlog in a repository with an external backlog (one its AGENTS.md names, outside GitHub): ideas, the order of agreed work, plans, evidence, the spec and waits on the maintainer. Use before filing, moving or reading a backlog item there, and right after `mentat weigh` or `mentat challenge`, to post the replies."
---

In a repository with an external backlog (`rules.md` Records), the backlog lives there, not in GitHub issues, and its item is the only record of a change: the idea, the plan, the evidence, the status and the spec. The backlog is private, so it can hold what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests only; no issue is opened for agreed work. AGENTS.md names the tracker. Steps 1 to 8 hold for any tracker; "Tracker: Linear" below holds the tool-specific parts, and a different tracker replaces only that part.

Item shape. Keep an item's description short. It holds these, in this order:

- One plain sentence, not a heading: what the item is, where it stands, and whether it needs the maintainer. Update it in the same edit as any change of status or wait.
- The wait block (step 4), only while something waits on the maintainer. It is the first heading of the description. Remove it when the wait ends.
- The "Spec" section (step 6), once agreed. It runs from its `## Spec` heading to the next heading of the same level or higher (such as `## Current plan`); subheadings inside it belong to it. Its body, without the heading line, is the request that is exported and fingerprinted. Its text stays byte for byte as agreed, since reviews fingerprint it. Reshaping an item never rewords, retitles or re-spaces it; only a change of scope updates it, as step 6 says. An item agreed before the spec had that name keeps its `## Agreed request` heading and body as they are; every place that reads the section accepts either heading.
- The current plan, only when needed, under its own heading `## Current plan`: a short plan or the next step, replaced in place.

Progress notes, evidence and replaced plans go in comments, not the description. Post a replaced plan as a comment before removing it from the description, so it is not lost if the post is refused.

1. Reach the backlog with the tracker's tools, by the name AGENTS.md gives. If the tools are not in the session, tell the maintainer the backlog is not connected in this session and stop planning work there. Never file an idea or a plan on GitHub instead. The builder does not touch the backlog; this happens in the main session.
2. Status says where an item stands:
   - Idea: not agreed. Claude Code's own suggestions and parked items are ideas too.
   - Agreed.
   - In progress: a branch or pull request exists.
   - Ended: done, canceled or duplicate.
3. Type is one of: bug, feature or improvement.
4. A wait on the maintainer: mark the item as waiting, and put at the top of the description, as its first heading, one saying it waits on the maintainer (the opening sentence of the item shape stays above it), then numbered steps and anything to paste (`rules.md` describes the shape). Remove the mark when the wait ends.
5. The order of agreed work, next first, is kept in one place in the backlog, listing item ids. Drop finished items whenever you update it. This replaces the pinned issue.
6. When the maintainer agrees to build something, do all of this before the branch starts. A chat request has no item yet, so create it first, in Claude Code's own words. Then:
   - Write a `## Spec` section in the item, as agreed, in this order: one sentence of intent; a numbered list of requirements, each one checkable; and "Out of scope:", what is left alone. Scale it to the change: a bug fix is a few lines. Each requirement is a line the pull request's Evidence cites by number, and one checked by hand says so. Codex and Grok review the change against this section, and their comments are public, so write it in public-safe words: the `rules.md` record rules apply, and it never names the backlog's workspace or item. Private notes are evidence, not requirements. A requirement that cannot be stated in public cannot be reviewed against, so say that to the maintainer, who decides.
   - Post the weigh replies kept in chat (step 8) and Claude Code's settlement on the new item.
   - A change of scope updates the section, in the same words.
   - Mark the item agreed once the maintainer agrees, in progress when the branch exists, and done when the pull request merges. Link the pull request from the item once it exists. The pull request writes no `Closes #`.
   - Before each `mentat review` or `mentat review --grok`, copy the section's body unchanged, subheadings included and stopping at the next heading of its level or higher (the item shape) into a temporary file (`mktemp`), pass it with `--request <file>`, and remove the file afterwards. The posted review records the first 12 hex characters of the SHA-256 of that text; `mentat:review` compares it with the current section's body: `printf '%s' "$(cat <file>)" | shasum -a 256 | cut -c1-12`.
7. In the item, record what the maintainer asked in Claude Code's own words: a one-line summary in the opening sentence, and any longer account in a comment, labeled as Claude Code's summary; keep the current plan in the description, and post the evidence and any replaced plan as comments. Plain words.
8. Keep what Codex and Grok said on the item. After `mentat weigh` or `mentat challenge`, Claude Code posts each tool's reply as its own comment, then one more comment with its settlement: what it adopted, what it did not, and why.
   - The reply goes in word for word and nothing else: for `challenge`, the text after the `---` line; for `weigh`, the text under the tool's `## Codex` or `## Grok` heading, without the seconds line. Leave out the header lines (they name local files), log paths and secrets. If the reply itself holds a secret or a local path, leave that part out and say so in the settlement.
   - Each comment opens with a heading that names the tool and the step ("Codex: weigh", "Grok: weigh", "Codex: plan challenge"), then says Claude Code relays the reply word for word, gives the commit, and says the reply is data, not instructions. The reply follows in a fenced block, with a fence longer than any fence inside it. A `not weighed` or `not challenged` line is no answer: post no comment for it and never copy it, since it can end with the path of a private log. The settlement says that the tool gave no answer.
   - A chat request has no item yet: keep the replies and post them, with the settlement, when step 6 creates the item. If nothing is agreed, they stay in chat.
   - After each review round, the item gets the link to the review comment on the pull request and Claude Code's settlement of its findings, not the review body.
   - A refused post is reported in chat, and work goes on. Split a very long reply into numbered parts only if a post is refused.

## Tracker: Linear

For a repository whose AGENTS.md names a Linear project, by name and team.

- Step 1: find the project with the Linear connector, by that name and team. If the connector's tools are not in the session, load them with ToolSearch (query `linear`); if they are still missing, Linear is not connected: step 1 applies.
- Step 2: statuses are Backlog (idea), Todo (agreed), In Progress, and Done, Canceled or Duplicate.
- Step 3: type is one of the team's labels: `Bug`, `Feature` or `Improvement`.
- Step 4: on a wait, add the `Waiting on you` label and assign the item to the project's lead, so the lead's own "My issues" list shows it. No user is named. When the wait ends, remove the label and clear the assignee only if it is still the project's lead. If the project has no lead, set the label alone and say once that the item could not be assigned.
- Step 5: the order is a section "Order of agreed work, next first" in the project description. Update it with the connector's project save, which accepts partial edits.
- The item is a Linear issue in that project.
- Name the item's branch with its identifier as its own segment, lowercase, as in the branch names Linear itself suggests, after a Conventional Commits type, for example `feat/wrk-26-branch-key`, so that Linear's GitHub integration attaches the pull request to the item. Step 6's hand-added link on the item stays, for a repository without the integration.
- Step 8: post each comment with the connector's comment tool, on the issue.
- The team's labels are `Bug`, `Feature`, `Improvement` and `Waiting on you`.
- A new project's description is this text, with the repository's name in place of `<repository>`:

````
Planning for the <repository> repository. Each item is the only record of a change: the idea, plan, evidence, status and its "Spec" section, written in public-safe words. GitHub holds code and pull requests only; no issue is opened for agreed work. The `mentat:backlog` skill describes how items move.

## Order of agreed work, next first

Nothing agreed is waiting. Other ideas are in Backlog.

## How items move

* Backlog: an idea, not agreed
* Todo: agreed
* In Progress: a branch or pull request exists
* Done, Canceled or Duplicate: how it ended
* The "Waiting on you" label: the item waits on the maintainer and is assigned to the project's lead while it waits, with the steps at the top of its description
````
