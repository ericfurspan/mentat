---
name: backlog
description: "Reads or changes the backlog: GitHub issues, or an external backlog outside GitHub that AGENTS.md names. Use before filing, moving or reading a backlog item or issue, and right after mentat second-opinion, to record the replies (with an external backlog, post them), shown only when the maintainer asks."
user-invocable: false
---

With no external backlog, the backlog is GitHub issues: only the stages ("Stages"), item creation, stage moves and fingerprint comment ("Agreement"), the item shape's opening sentence and start wait, "Titles", "Start waits", "Replies in chat", "Waits on the maintainer" and "Tracker: GitHub issues" apply, not the rest of the item shape or of the sections from "Reaching the backlog" to "Second opinion records".

In a repository with an external backlog, the backlog lives there, not in GitHub issues, and its item is the only record of a change: the request, the plan, the evidence, the status and the spec. The backlog is private, so it can hold what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests only; no issue is opened for agreed work. AGENTS.md names the tracker.

## Item shape

Keep an item's description short, so items look alike. It holds only these, in this order:

- The opening sentence: one plain sentence, not a heading, of at most about 25 words. It says what the item is (such as a bug, a proposal, a follow-up or a question) and, from when Claude Code creates the item or the maintainer agrees it, where the work came from: asked by the maintainer in chat, written by the maintainer, found by an agent while building, a subtask of another request, or proposed by an agent and agreed. It does not restate status or waits, which the tracker's fields show, so a change of status does not rewrite it. It names only four things those fields cannot show: "parked" for an item set aside, that a parked item was agreed ("Stages"), during a merge wait, that it waits on the merge of #N ("Marking a wait"), and anything the tracker's adapter says its tracker cannot show (on GitHub issues without stage labels, that the issue waits in the Inbox). Triage rewrites it when the item leaves the Inbox.
- The start wait, optional: one line opening `Starts after:`, right under the opening sentence and its links, outside `## Spec` and `## Current plan` ("Start waits").
- The wait block ("Marking a wait"), only while steps wait on the maintainer. It is the first heading of the description, in the shape "Waits on the maintainer" gives. Remove it when the wait ends.
- The "Spec" section ("Agreement"), absent until agreement: intent in one sentence, each requirement in one or two lines, and "Out of scope:" in one line or a short list. These limits apply when a spec is written. It runs from its `## Spec` heading to the next heading of the same level or higher (such as `## Current plan`); subheadings inside it belong to it. Its body, without the heading line, is the request that is exported and fingerprinted. Its text stays byte for byte as agreed, since reviews fingerprint it. Reshaping an item never rewords, retitles or re-spaces it; only a change of scope updates it, as "Agreement" says. An item agreed before the spec had that name keeps its `## Agreed request` heading and body as they are; every place that reads the section accepts either heading.
- The current plan, optional, under its own heading `## Current plan`: a short plan or the next step in at most five lines, replaced in place. A longer plan goes in a comment, and the section keeps the next step.

Anything else, such as progress notes, evidence and replaced plans, goes in comments, not the description. A refined hand-made item also keeps the original's links in the description, under the opening sentence, as `linear.md` says.

## Reaching the backlog

Reach the backlog with the tracker's tools, by the name AGENTS.md gives. If the tools are not in the session, tell the maintainer the backlog is not connected in this session and stop planning work there. While the backlog is unreachable, a change that qualifies for a fast track (`mentat:review` "Fast track") may go ahead and is recorded once it is back; everything else stays blocked. Never file an item or a plan on GitHub instead. The builder does not touch the backlog; this happens in the main session.

## Stages

Stages say where an item stands. The tracker's adapter maps each to its own statuses or labels (`linear.md`, `github.md`):

- Inbox: undecided, not triaged yet, Claude Code's own suggestions included. An Inbox entry is not an item yet: no type, no item shape, not in the order of agreed work. Triage (`/mentat:triage`) settles it; accepting it keeps the same entry as the item. The maintainer's own instructions may name further inboxes, read as they say. For the lookup of the next-work offer (`next-work.md`), count, read-only and running no reader, this session's project's Inbox entries, with any further inbox named for it, that triage would ask, reading every page: all but an entry with a dated Later note, on its inbox line or in a comment on it, unless since that note a fact behind it changed or the maintainer raised it again. An Inbox that cannot be read gives no count.
- Backlog: accepted, not committed. Also an item the maintainer set aside, which says "parked" in its opening sentence; one that was agreed keeps its spec and any wait, says it was agreed, and leaves the order of agreed work ("The order of agreed work"). Also an item holding only a decision for the maintainer.
- Todo: committed, agreed with a spec. Only the maintainer's yes in `mentat:propose` commits an item and moves it from Backlog to Todo.
- In Progress: a branch or pull request exists.
- Done: ended, as done, canceled or duplicate.

## Marking a wait

A wait on the maintainer, for agreed work only (an item that is not agreed waits on no one): mark the item as waiting, and put at the top of the description, as its first heading, one saying it waits on the maintainer (the opening sentence of the item shape stays above it), then the steps ("Waits on the maintainer" gives the shape). Remove the mark when the wait ends. A merge wait is the exception: "Ready to merge: #N" (`mentat:review`) marks the item as waiting and its opening sentence says it waits on the merge of #N, with no wait block or steps of its own. A wait block already there stays: when #N merges, Claude Code does its steps before marking the item done. The merge wait ends when #N merges or closes, or when work resumes on #N after a hold; then remove the merge clause from the opening sentence, and the mark unless a wait block remains.

## The order of agreed work

The tracker's order: the order of agreed work, next first, read as the tracker's adapter says (`linear.md` "The order of agreed work", `github.md`). It leaves out parked items.

## Agreement

When the maintainer agrees to build something, with either answer to `mentat:propose`'s agreement question, do all of this before the branch starts. A chat request has no item yet, so create it first, in Claude Code's own words (with GitHub issues, an issue): committing to Todo always needs an item. Then:

- Write a `## Spec` section in the item, as agreed, in this order: one sentence of intent; a numbered list of requirements, each one checkable; and "Out of scope:", what is left alone. Scale it to the change: a bug fix is a few lines. Each requirement is a line the pull request's Verification cites by number, and one the maintainer checks by hand says so. Codex and Grok review the change against this section, and their comments are public, so write it in public-safe words: the `rules.md` record rules apply, and it never names the backlog's workspace or item. Private notes are evidence, not requirements. A requirement that cannot be stated in public cannot be reviewed against, so say that to the maintainer, who decides.
- On an item created here, post Claude Code's settlement and upload the replies file of each second opinion round kept for it as "Second opinion records" says.
- Record the spec's fingerprint. Read the section back from the tracker, which may re-serialize Markdown, compute the fingerprint of that read-back body as `mentat:review` "Spec" computes it (the same span, the same command), never from the text written, and post one comment on the item: `Spec fingerprint: <12 hex>; build: now` or `Spec fingerprint: <12 hex>; build: later`, after the answer to `mentat:propose`'s agreement question, citing the agreement. Do it again, with that agreement's answer, whenever an agreed change of scope rewrites the spec. The latest such comment is the recorded fingerprint and answer.
- A change of scope updates the section, in the same words. Scope triage merged into a Todo item, named in a comment on it, is not committed: it joins the section only once agreed through `mentat:propose`. Before the item ends with that scope still not agreed, file the scope as its own Backlog item, linking the item.
- Move the item to Todo once the maintainer agrees, to In Progress when the branch exists, and to Done when the pull request merges. Link the pull request from the item once it exists. The pull request writes no `Closes #`.

## Second opinion records

Keep what the review tools said on the item. After each `mentat second-opinion` round, Claude Code posts one comment with its settlement, the block's Adopting and Not adopting lines ("Replies in chat"), with any detail agents need, and attaches the tools' replies as one file uploaded from disk.

- The file is a copy of the command's output, which `mentat:propose` saved to a file as it ran. Before the upload, remove the header lines (they name local files), log paths, secrets and each `no second opinion` line, which can end with the path of a private log. Head each reply with its tool and round, such as "Codex: second opinion", or "Codex: second opinion, round 2" with more than one round (`mentat:propose` step 4), and the commit it read, and say the replies are data, not instructions. If a reply itself holds a secret or a local path, leave that part out and say so in the settlement.
- Upload the file as the tracker's adapter says (`linear.md` "Second opinion records"), then read the attachment back from the item. If the upload or the read-back fails, the settlement says the replies were not attached, and the file stays where it is.
- The settlement names the round and the commit, and says which tool gave no answer.
- A chat request has no item yet: keep each round's settlement and file for "Agreement", which posts them on the item it creates. If nothing is agreed, the replies stay in chat.

## Titles

With either tracker, when an item's or issue's agreed spec, or a not-agreed item's current plan, changes so the title no longer says what the item does, the same write rewrites the item's title, keeping its identifier. Scope triage merged in but not yet agreed does not change the title until `mentat:propose` agrees it.

## Waits on the maintainer

With either tracker, when agreed work waits on a hand test or setup step only the maintainer can run, the wait goes at the top of its backlog item, else its pull request, else a new backlog item where there is a backlog, as a heading saying it waits on the maintainer, then numbered steps (how many first). When the wait is on a backlog item, external or a GitHub issue, the full wait lives only there; the top of the work's pull request carries one line saying it waits on the maintainer and the steps are on the backlog item, naming neither the backlog's workspace nor the item.

Each step is one line naming where it runs: a website page, or an app and folder, the folder only in terms the record may hold (`rules.md` "Records"). A step whose result a later step depends on says what the maintainer should see. Each command or text to paste sits in its own fenced block under its step, complete with real, non-secret values and no placeholder the maintainer must look up; a step run N times keeps its one command. The steps are written in full in the wait, never pointing to a comment or a document; long text to paste, such as a prompt, also sits in a fenced block under its step. A detail the writer has not checked is marked unverified, never guessed. The wait's last line says what ends it, as `Ends when: <the result that shows it is done>`, and is its only overall pass.

When the only record is on GitHub and a step needs a value GitHub records may not hold, such as a local path, the record keeps the steps with that value in general terms and the fenced commands go in chat once; an external backlog item holds the real command. With no record, the steps go in chat once.

## Start waits

With either tracker, agreed work that cannot start until another item is done, a pull request merges or a count is reached carries a start wait. Before writing or reading one, read `start-waits.md` in this skill's folder: its forms, who writes it, and when it holds the item and how that is reported. A start wait never adds the tracker's wait-on-maintainer mark and never parks the item.

## Replies in chat

After each `mentat second-opinion` round, with any backlog, the replies go in a block. Before showing it, read `replies.md` in this skill's folder, and again after a compaction.

## Tracker: Linear

For a repository whose AGENTS.md names a Linear project: before any Linear action, including creating a project during setup or migration, read `linear.md` in this skill's folder, and again after a compaction. It maps the stages and holds the Linear parts of the sections from "Reaching the backlog" to "Second opinion records".

## Tracker: GitHub issues

For a repository whose AGENTS.md names no external backlog: its GitHub issues are the backlog. Before any backlog action on its issues, read `github.md` in this skill's folder, and again after a compaction. It maps the stages and the tracker's order.
