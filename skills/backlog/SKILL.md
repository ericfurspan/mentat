---
name: backlog
description: "Reads or changes the backlog: GitHub issues, or an external backlog outside GitHub that AGENTS.md names. Use before filing, moving or reading a backlog item or issue, and right after the plan check or mentat second-opinion, to record the replies (with an external backlog, in the item's one Agent records comment, edited in place) and show them as replies.md says."
user-invocable: false
---

With no external backlog, the backlog is GitHub issues: only the stages ("Stages"), item creation, stage moves and fingerprint record ("Agreement"), "Where the spec lives", the item shape as `github.md` gives it, no progress comments on an item (progress is on the pull request once one exists), "Filing", "Titles", "Advice against", "Material assumptions", "Relayed writes", "Start waits", "Reading an item", "Replies in chat", "Waits on the maintainer" and "Tracker: GitHub issues" apply, not the rest of the sections from "Reaching the backlog" to "Plan check record".

In a repository with an external backlog, the backlog lives there, not in GitHub issues, and its item is the only record of a change: the request, the plan, the evidence, the status and the spec. The backlog is private, so it can hold what GitHub should not: planning evidence that may come from private sessions. GitHub holds pull requests only; no issue is opened for agreed work. AGENTS.md names the tracker.

## Item shape

Keep an item's description short, so items look alike. It holds only these, in this order:

- The opening sentence: one plain sentence, not a heading, of at most about 25 words. It says what the item is (such as a bug, a proposal, a follow-up or a question) and, from when Claude Code creates the item or the maintainer agrees it, where the work came from: asked by the maintainer in chat, written by the maintainer, found by an agent while building, or proposed by an agent and agreed. It does not restate status or waits, which the tracker's fields show, so a change of status does not rewrite it. It names only three things those fields cannot show: "parked" for an item set aside, that a parked item was agreed ("Stages"), and anything the tracker's adapter says its tracker cannot show (on GitHub issues without stage labels, that the issue waits in the Inbox). Triage rewrites it when the item leaves the Inbox.
- The start wait, optional: one line opening `Starts after:` ("Start waits").
- The wait block ("Marking a wait"), only while steps wait on the maintainer, in the shape "Waits on the maintainer" gives, its steps in full; remove it when the wait ends. Then, on every tracker, a section headed "Decision for the maintainer" while one is open on the item: written when it arises (`../propose/decisions.md`), removed when its answer is recorded (`agent-records.md`). These are the first headings of the description, the wait block first.
- One `Now:` line, the item's next step: where the item stands and what comes next, replaced in place.
- One links line.

The item's decisions lines, any longer current plan and its material assumptions go in its agent records (`agent-records.md`). The tracker's adapter may keep the next step and the decisions lines elsewhere (`github.md`); every reader and writer uses its place. Evidence goes to an attachment or the pull request; a replaced plan is deleted, not posted as a comment. Agents post no progress comments on an item; once a pull request exists, progress is on the pull request.

## Reaching the backlog

Reach the backlog with the tracker's tools, by the name AGENTS.md gives. If the tools are not in the session, tell the maintainer the backlog is not connected in this session and stop planning work there. While the backlog is unreachable, a change that qualifies for a fast track (`mentat:review` "Fast track") may go ahead and is recorded once it is back; everything else stays blocked. Never file an item or a plan on GitHub instead. The builder does not touch the backlog; this happens in the main session.

## Stages

Stages say where an item stands. The tracker's adapter maps each to its own statuses or labels (`mentat-linear:linear`, `github.md`):

- Inbox: undecided, not triaged yet, Claude Code's own suggestions included. An Inbox entry is not an item yet: no type, no item shape, not in the order of agreed work. Triage (`/mentat-linear:triage`, in the `mentat-linear` module, for any tracker) settles it; where that module is off, the maintainer settles an entry in chat with Claude Code, its outcome (accept, close, merge, later) written as the tracker's adapter says for triage outcomes. Accepting it keeps the same entry as the item.
- Backlog: accepted, not committed. Also an item the maintainer set aside, which says "parked" in its opening sentence; one that was agreed keeps its spec and any wait, says it was agreed, and leaves the order of agreed work ("The order of agreed work"). Also an item holding only a decision for the maintainer, which is not a wait ("Marking a wait").
- Todo: committed, agreed with a spec. Only the maintainer's yes in `mentat:propose` commits an item and moves it from Backlog to Todo.
- In Progress: a branch or pull request exists.
- Done: ended, as done, canceled or duplicate.

## Marking a wait

A wait on the maintainer, for agreed work only (an item that is not agreed waits on no one): mark the item as waiting, and put at the top of the description, as its first heading, one saying it waits on the maintainer (the opening sentence of the item shape stays above it), then the steps ("Waits on the maintainer" gives the shape). A decision for the maintainer is not a wait: the tracker's wait mark marks one that blocks an item's work too, on any item, as the tracker's adapter says, and one that does not block gets no mark. When a wait ends or a blocking decision is answered, remove the mark only when no wait or blocking decision remains. A merge wait, with an external backlog only, is the exception: "Ready to merge: #N" (`mentat:review`) marks it as the tracker's adapter says, with no wait block or steps of its own. A wait block already there stays: when #N merges, Claude Code does its steps before marking the item done, except a hand check the spec marks as after the merge, which is the maintainer's and keeps the item open and waiting, not done (`../review/after-ready.md`), until they report each such check's result; the last report, pass or fail, ends that wait and marks the item done, each failed check first filed as a follow-up ("Filing"). The merge wait ends when #N merges or closes, or when work resumes on #N after a hold, as the tracker's adapter says. A review stop waiting on the maintainer's answer (`mentat:review`) also marks the item as waiting, with no wait block, its next step ("Item shape") naming the stop; the maintainer's answer ends it, and the same write replaces that next step with the item's actual one and removes the mark only when no wait or blocking decision remains.

## The order of agreed work

The tracker's order: the order of agreed work, next first, read as the tracker's adapter says (`mentat-linear:linear` "The order of agreed work", `github.md`). It leaves out parked items.

## Where the spec lives

An item's spec lives where the tracker's adapter says ("Where the spec lives" in `mentat-linear:linear` or `github.md`); every skill that reads, writes or fingerprints a spec takes it from there. It is absent until agreement. Its body is the request that is exported and fingerprinted, and stays byte for byte as agreed: reshaping an item never rewords, retitles or re-spaces it; only a change of scope updates it ("Agreement"). Before and after a write that moves it, fingerprint it as "Agreement" says; if the two differ, restore the earlier body before anything relies on it. Build readiness handles a mismatch with the recorded fingerprint.

## Agreement

When the maintainer agrees to build something, with either answer to `mentat:propose`'s agreement question, do all of this before the branch starts. A chat request has no item yet, so create it first, in Claude Code's own words (with GitHub issues, an issue): committing to Todo always needs an item. Then:

- Write the spec ("Where the spec lives"), as agreed, in this order: one sentence of intent; a numbered list of requirements, each one checkable, in one or two lines; and "Out of scope:", what is left alone, in one line or a short list. Scale it to the change: a bug fix is a few lines. Each requirement is a line the requirement table in the pull request's Review details cites by number, and one the maintainer checks by hand says so, and "after the merge" when the change takes effect only once merged. The reviewers `mentat:review` runs review the change against it, and their comments are public, so write it in public-safe words: `records.md` in this skill's folder applies, and it never names the backlog's workspace or item. Private notes are evidence, not requirements. A requirement that cannot be stated in public cannot be reviewed against, so say that to the maintainer, who decides.
- On an item created here, write the plan check and second opinion records kept for it, with their files, as `agent-records.md` in this skill's folder says.
- Record the spec's fingerprint. Read the spec back from the tracker, which may re-serialize Markdown, compute the fingerprint of that read-back body as `mentat:review` "Spec" computes it (the same command), never from the text written, and record it with the answer to `mentat:propose`'s agreement question (build now or later), citing the agreement, in the item's agent records (`agent-records.md`). Do it again, with that agreement's answer, whenever an agreed change of scope rewrites the spec.
- A change of scope updates the spec, in the same words. Scope triage merged into a Todo item, named in a comment on it, is not committed: it joins the spec only once agreed through `mentat:propose`. Before the item ends with that scope still not agreed, the scope goes to the Inbox as one entry naming the item.
- Move the item to Todo once the maintainer agrees, to In Progress when the branch exists, and to Done when the pull request merges, or, with hand checks after the merge, once the maintainer reports each one's result ("Marking a wait", or `github.md` with GitHub issues). Link the pull request from the item once it exists. The pull request writes no `Closes #`.

## Second opinion records

Keep what the review tools said on the item: after each `mentat second-opinion` round, record Claude Code's settlement and attach the tools' replies as `agent-records.md` in this skill's folder says.

## Plan check record

With an external backlog, after the plan check, record its settlement and attach its reply as `agent-records.md` in this skill's folder says.

## Filing

With either tracker, before filing an entry or item, read `filing.md` in this skill's folder, and again after a compaction.

## Titles

With either tracker, when an item's or issue's agreed spec, or a not-agreed item's current plan, changes so the title no longer says what the item does, the same write rewrites the item's title, keeping its identifier. Scope triage merged in but not yet agreed does not change the title until `mentat:propose` agrees it.

## Advice against

With either tracker, when Claude Code advised against an item and the maintainer goes ahead anyway, record the advice as `agent-records.md` in this skill's folder says: when, its shape, and how `mentat:review` "Final check" quotes it.

## Material assumptions

With either tracker, before writing an item's material assumptions, or briefing a builder for an item, read `assumptions.md` in this skill's folder, and again after a compaction: the list's shape, when it is written and what reaches the maintainer.

## Relayed writes

With either tracker, a backlog write that a build session another session started sends back is made as "Relayed writes" in `../build/SKILL.md` says; read it then.

## Waits on the maintainer

With either tracker, before writing or reading a wait on a hand test or setup step only the maintainer can run, read `waits.md` in this skill's folder, and again after a compaction: where the wait goes and its shape.

## Start waits

With either tracker, agreed work that cannot start until another item is done, a pull request merges or a count is reached carries a start wait. Before writing or reading one, read `start-waits.md` in this skill's folder: its forms, who writes it, and when it holds the item and how that is reported. A start wait never adds the tracker's wait-on-maintainer mark and never parks the item.

## Reading an item

With either tracker, before reading an item to plan, propose, triage or build it, or to record an answer on it, read `item-reads.md` in this skill's folder, and again after a compaction.

## Replies in chat

After the plan check, and after each `mentat second-opinion` round, with any backlog, the replies go in a block. Before showing it, read `replies.md` in this skill's folder, and again after a compaction.

## Tracker: Linear

For a repository whose AGENTS.md names a Linear project: before any Linear action, including creating a project, call the Skill tool with `mentat-linear:linear`, and again after a compaction. It maps the stages and holds the Linear parts of the sections from "Reaching the backlog" to "Second opinion records". When that skill is not available, say the `mentat-linear` module is off, so the backlog is not reachable in this session, and go on as "Reaching the backlog" says.

## Tracker: GitHub issues

For a repository whose AGENTS.md names no external backlog: its GitHub issues are the backlog. Before any backlog action on its issues, read `github.md` in this skill's folder, and again after a compaction. It maps the stages and the tracker's order.
