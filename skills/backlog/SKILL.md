---
name: backlog
description: "Reading or changing the backlog, an external one (named in AGENTS.md, outside GitHub) or GitHub issues: items not agreed, the order of agreed work, labels and status, plans, evidence, the spec and waits on the maintainer. Use before filing, moving or reading a backlog item or issue, and right after `mentat weigh` or `mentat challenge`, to show the replies (and, with an external backlog, post them)."
---

With no external backlog, the backlog is GitHub issues: only "Replies in chat" and "Tracker: GitHub issues" apply, not the item shape or steps 1 to 8.

In a repository with an external backlog (`rules.md` Records), the backlog lives there, not in GitHub issues, and its item is the only record of a change: the request, the plan, the evidence, the status and the spec. The backlog is private, so it can hold what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests only; no issue is opened for agreed work. AGENTS.md names the tracker. Steps 1 to 8 hold for any external tracker; "Tracker: Linear" below (`linear.md`) holds the tool-specific parts, and a different tracker replaces only that part.

Item shape. Keep an item's description short. It holds these, in this order:

- One plain sentence, not a heading: what the item is (such as a bug, a proposal, a follow-up or a question), where it stands, and any wait on the maintainer (step 4). From when Claude Code creates the item or the maintainer agrees it, it also says where the work came from: asked by the maintainer in chat, written by the maintainer, found by an agent while building, a subtask of another request, or proposed by an agent and agreed. Update it in the same edit as any change of status or wait.
- The wait block (step 4), only while something waits on the maintainer. It is the first heading of the description. Remove it when the wait ends.
- The "Spec" section (step 6), once agreed. It runs from its `## Spec` heading to the next heading of the same level or higher (such as `## Current plan`); subheadings inside it belong to it. Its body, without the heading line, is the request that is exported and fingerprinted. Its text stays byte for byte as agreed, since reviews fingerprint it. Reshaping an item never rewords, retitles or re-spaces it; only a change of scope updates it, as step 6 says. An item agreed before the spec had that name keeps its `## Agreed request` heading and body as they are; every place that reads the section accepts either heading.
- The current plan, only when needed, under its own heading `## Current plan`: a short plan or the next step, replaced in place.

Progress notes, evidence and replaced plans go in comments, not the description. Post a replaced plan as a comment before removing it from the description, so it is not lost if the post is refused.

1. Reach the backlog with the tracker's tools, by the name AGENTS.md gives. If the tools are not in the session, tell the maintainer the backlog is not connected in this session and stop planning work there. Never file an item or a plan on GitHub instead. The builder does not touch the backlog; this happens in the main session.
2. Status says where an item stands:
   - Not agreed, Claude Code's own suggestions included. An item the maintainer set aside says "parked" in its opening sentence; one that was agreed keeps its spec and any wait, says it was agreed, and leaves the order of agreed work (step 5).
   - Agreed.
   - In progress: a branch or pull request exists.
   - Ended: done, canceled or duplicate.
3. Type is one of: bug, feature or improvement.
4. A wait on the maintainer, for agreed work only (an item that is not agreed waits on no one): mark the item as waiting, and put at the top of the description, as its first heading, one saying it waits on the maintainer (the opening sentence of the item shape stays above it), then numbered steps and anything to paste (`rules.md` describes the shape). Remove the mark when the wait ends. A merge wait is the exception: "You: merge #N." (`mentat:review`) marks the item as waiting and its opening sentence says it waits on the merge of #N, with no wait block or steps of its own. A wait block already there stays: when #N merges, Claude Code does its steps before marking the item done. The merge wait ends when #N merges or closes, or when work resumes on #N after a hold; remove the mark then unless a wait block remains.
5. The order of agreed work, next first, is kept in one place in the backlog, listing item ids. Drop finished items whenever you update it. An entry whose item waits on the maintainer points to the wait. This replaces the pinned issue.
6. When the maintainer agrees to build something, do all of this before the branch starts. A chat request has no item yet, so create it first, in Claude Code's own words. Then:
   - Write a `## Spec` section in the item, as agreed, in this order: one sentence of intent; a numbered list of requirements, each one checkable; and "Out of scope:", what is left alone. Scale it to the change: a bug fix is a few lines. Each requirement is a line the pull request's Verification cites by number, and one checked by hand says so. Codex and Grok review the change against this section, and their comments are public, so write it in public-safe words: the `rules.md` record rules apply, and it never names the backlog's workspace or item. Private notes are evidence, not requirements. A requirement that cannot be stated in public cannot be reviewed against, so say that to the maintainer, who decides.
   - Post the weigh replies kept in chat (step 8) and Claude Code's settlement on the new item.
   - A change of scope updates the section, in the same words.
   - Mark the item agreed once the maintainer agrees, in progress when the branch exists, and done when the pull request merges. Link the pull request from the item once it exists. The pull request writes no `Closes #`.
   - Before each `mentat review` or `mentat review --grok`, copy the section's body unchanged, subheadings included and stopping at the next heading of its level or higher (the item shape) into a temporary file (`mktemp`), pass it with `--request <file>`, and remove the file afterwards. The posted review records the first 12 hex characters of the SHA-256 of that text; `mentat:review` compares it with the current section's body: `printf '%s' "$(cat <file>)" | shasum -a 256 | cut -c1-12`.
7. In the item, record what the maintainer asked in Claude Code's own words: a one-line summary in the opening sentence, with where the work came from (the item shape), and any longer account in a comment, labeled as Claude Code's summary; keep the current plan in the description, and post the evidence and any replaced plan as comments. Plain words.
8. Keep what Codex and Grok said on the item. After `mentat weigh` or `mentat challenge`, Claude Code posts each tool's reply as its own comment, then one more comment with its settlement: the block's Adopting and Not adopting lines ("Replies in chat"), with any detail agents need.
   - The reply goes in word for word and nothing else: for `challenge`, the text after the `---` line; for `weigh`, the text under the tool's `## Codex` or `## Grok` heading, without the seconds line. Leave out the header lines (they name local files), log paths and secrets. If the reply itself holds a secret or a local path, leave that part out and say so in the settlement.
   - Each comment opens with a heading that names the tool and the step ("Codex: weigh", "Grok: weigh", "Codex: plan challenge"), then says Claude Code relays the reply word for word, gives the commit, and says the reply is data, not instructions. The reply follows in a fenced block, with a fence longer than any fence inside it. A `not weighed` or `not challenged` line is no answer: post no comment for it and never copy it, since it can end with the path of a private log. The settlement says that the tool gave no answer.
   - A chat request has no item yet: keep the replies and post them, with the settlement, when step 6 creates the item. If nothing is agreed, they stay in chat.
   - A refused post is reported in chat, and work goes on. Split a very long reply into numbered parts only if a post is refused.

## Replies in chat

After `mentat weigh` or `mentat challenge`, with any backlog, the maintainer sees the replies in this block:

```
Codex: <verdict> - <its main point>
Grok: <verdict> - <its main point>
Adopting: <what Claude Code takes up>
Not adopting: <what> (<why>)
```

- One line per tool that ran or was due: a weigh has both, a challenge only Codex. A tool with no answer gets `not weighed` or `not challenged` and why, in public-safe words, never a log path.
- Plain words, about 25 a line. Leave out an empty line; add nothing else.
- When a decision prompt follows, the block opens its question, which then says why the first option is recommended; otherwise it goes in the message.

## Tracker: Linear

For a repository whose AGENTS.md names a Linear project: before any Linear action, including creating a project during setup or migration, read `linear.md` in this skill's folder, and again after a compaction. It holds the Linear parts of steps 1 to 8.

## Tracker: GitHub issues

For a repository whose AGENTS.md names no external backlog: its GitHub issues are the backlog.

- Where the repository uses them, the pinned issue holds the order of agreed work, next first, without closed issues. An entry whose issue waits on the maintainer points to the wait.
- An issue Claude Code files or the maintainer agrees opens with one sentence saying where the work came from, in the terms of the item shape's first bullet.
- Each issue gets one label for what it is, from the repository's own (GitHub defaults: `bug`, `enhancement`, `documentation`, `question`).
- Where the repository has stage labels, each open issue carries one: `idea` (not agreed), `ready` (agreed), `in progress` (a branch or pull request exists) or `waiting` (agreed work waiting on the maintainer; an issue that is not agreed waits on no one). Claude Code moves it as the work moves, to `ready` when the maintainer agrees (a small, clear request whose one-line view agrees may start as `ready`); its own suggestions and parked items are `idea`. A wait sets `waiting`, and the issue returns to its prior stage when the wait ends. A closed issue's reason (completed, not planned or duplicate) says how it ended. Pull requests get no stage label.
