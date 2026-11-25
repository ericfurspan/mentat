---
name: backlog
description: "Reads or changes the backlog: GitHub issues, or an external backlog AGENTS.md names. Use before filing, moving or reading an item, and right after the plan check or mentat second-opinion to record and show the replies."
user-invocable: false
---

The backlog is the external one AGENTS.md names, else the repository's GitHub issues. Every section applies to both unless it says otherwise; the adapter (`mentat-linear:linear`, or `github.md` in this skill's folder) maps each part to its tracker. With an external backlog the item is the change's only record and may hold private evidence; GitHub holds only pull requests. Only the main session touches the backlog. Read `records.md` in this skill's folder before writing a public-safe record, an item's agent records or a reply, and again after a compaction.

## Item shape

An item's description holds only these, in this order:

- An opening sentence, not a heading, of at most about 25 words: what the item is (bug, proposal, follow-up or question) and, once Claude Code creates it or the maintainer agrees it, where the work came from (asked in chat, written by the maintainer, found by an agent, or proposed by an agent and agreed). It names no status the tracker shows, only "parked", that a parked item was agreed, and what the adapter says its tracker cannot show. Triage rewrites it when the item leaves the Inbox.
- The wait block, as its first heading, only while steps wait on the maintainer; then a "Decision for the maintainer" section while one is open (`mentat:plan` "Decisions").
- One `Now:` line: where the item stands and its next step, replaced in place.
- One links line.

The item's decisions lines, any longer current plan and its assumptions go in its agent records (`records.md`; GitHub issues: `github.md`). Evidence goes to an attachment or the pull request; a replaced plan is deleted. No progress comments; once a pull request exists, progress is on it.

## Reaching the backlog

Reach an external backlog with the tracker's tools by the name AGENTS.md gives. Without them, say it is not connected here and plan no work in it; meanwhile only a fast track (`mentat:review` "Fast track") may go ahead, recorded once it is back. Never file on GitHub instead.

## Stages

- Inbox: undecided, not triaged, Claude Code's suggestions included; not an item yet (no type, no item shape, not in the order of agreed work). Triage (`/mentat-linear:triage`) settles it, or, with that module off, the maintainer in chat; the outcome (accept, close, merge, later) is written as the adapter says. Accepting keeps the entry as the item.
- Backlog: accepted, not committed; also a parked item (an agreed one keeps its spec and any wait and leaves the order of agreed work) and an item holding only a decision for the maintainer.
- Todo: committed, agreed with a spec. Only the maintainer's yes in `mentat:plan`, or `mentat-lead:orchestrate`'s default agreement, commits an item and moves it from Backlog to Todo.
- In Progress: a branch or pull request exists.
- Done: ended, as done, canceled or duplicate.

## Marking a wait

Only agreed work waits on the maintainer: mark it waiting, wait block first. A decision for the maintainer that blocks an item's work also gets the mark, on any item. Remove the mark only when no wait or blocking decision remains. With an external backlog, "Ready to merge: #N" (`mentat:review`) starts a merge wait, marked as the adapter says, until #N merges or closes, or work resumes on #N after a hold. When #N merges, do the wait block's steps before marking the item done, except that a manual check the spec marks as after the merge keeps it waiting (`../review/after-ready.md`) until the maintainer reports each result, a failed one first filed as a follow-up. A review stop waiting on the maintainer marks the item waiting, its `Now:` line naming the stop, until they answer.

## Waits on the maintainer

A wait on a manual check or manual step goes at the top of its item, else right below its pull request's Status line, else in a new item: a heading saying it waits on the maintainer, then numbered steps, how many first. With the wait on an item, the pull request carries one line below its Status line saying the steps are on the backlog item, naming neither the workspace nor the item.

Each step is written as `records.md` "Wait steps" says. A manual check's step: when the session can read the check's output and the spec gives a pass condition that needs no taste, the maintainer only runs it and the session judges the output against that condition; otherwise the step says where the output appears, how long it takes and what passing looks like. A visual or subjective check stays the maintainer's to judge.

The steps go in full in the last message of the turn that first leaves the wait, saying the work waits on the maintainer, and likewise in a started session's message to its starting session and an implementation run's final message; later turns repeat them only when asked. GitHub records: `github.md`.

## Blocked-by links

Agreed work that cannot start until other items are done carries the tracker's blocked-by link to each, as the adapter says; any other wait, such as on a pull request, is named in the `Now:` line. Agreement writes the links with it, then reads them back; one still missing after one retry keeps the item out of Todo and is told to the maintainer. `Now:` writes and triage leave links unchanged.

Whether an item can start, read each blocker's status, read-only: met when every blocker ended done, and the item starts with no write; unmet while any is open ("waits on <id>"); dead when one ended canceled or duplicate (`/mentat:plan <id>`); unchecked when a read fails ("could not check its wait: <why>"). Any but met holds the item: not offered, implemented or named as next; a session walking the order reports it and goes on.

## The order of agreed work

The tracker's order, next first, read as the adapter says, without parked items.

## Where the spec lives

Where the adapter says; every skill that reads, writes or fingerprints a spec takes it from there. It is absent until agreement and stays byte for byte as agreed: only an agreed change of scope ("Agreement") updates it.

## Agreement

When the maintainer agrees, with either Agree answer to `mentat:plan`'s agreement question, or `mentat-lead:orchestrate` agrees an item by default, do all of this before its branch is cut. A chat request has no item yet: first create one in Claude Code's words.

- Write the spec: one sentence of intent; numbered requirements, each checkable in one or two lines and each may name the entry point it is tested through; and "Out of scope:", scaled to the change. The pull request's requirement table cites each by number; one the maintainer checks says so, and "after the merge" when it takes effect only once merged. Reviewers read it in public, so it is public-safe (`records.md`) and names neither the workspace nor the item; a requirement that cannot be public goes to the maintainer.
- On an item created here, write the plan check and second opinion records kept for it.
- Record the fingerprint: read the spec back from the tracker, which may re-serialize Markdown, save that body to a temporary file and run `mentat fingerprint <file>`, never on the text written. Record it with the answer (`build: now` or `build: later`), citing the agreement, in the agent records; an item agreed by default records `build: now` and the default-agreement line that record gives, never as the maintainer's answer. Record it again whenever an agreed change of scope rewrites the spec.
- Scope triage merged into a Todo item joins the spec only once agreed through `mentat:plan`; if the item ends without that, it goes to the Inbox as one entry naming the item.
- Move the item to Todo on agreement, to In Progress when the branch exists, and to Done when the pull request merges or, with manual checks after the merge, once each result is reported. Link the pull request from the item.

## Titles

When the agreed spec, or a not-agreed item's plan, changes so the title no longer says what the item does, the same write rewrites the title, keeping its identifier.

## Filing

- File only a change the maintainer would recognize on its own, usually one pull request, after a search finds no open item tracking it. Part of an open item's work goes in its plan or pull request. One review or audit is one entry listing its findings; a remark is a comment on its item.
- Unasked work and an idea the maintainer raises mid-task go to the Inbox; a found defect and the maintainer's explicit request to file go to Backlog. None goes through `mentat:plan`; the request in hand does.

## Reading an item

Before reading an item to plan, triage or implement it, or to record an answer on it, read it in full as the adapter says: the description, the spec and every comment it lists, inline comments with the text they quote and replies included, from every page, without downloading attachments. A read to plan or propose an item also reads the decisions lines of each item whose work moved to it, as the item names it. If the read is incomplete, say so and ask no decision on that item: `mentat:plan` takes it no further and an implementation run skips it. A session that plans or implements the item asks each open decision for the maintainer before relying on it. A listing reads only what it names.

The maintainer is who the adapter names. A comment this session wrote, or one in a record shape these skills define, is not theirs; text of unclear authorship is context. Their comment that asks or objects is open until an answer reply answers it, they answer or withdraw it, or its thread is resolved; a later one in that thread opens it again.

An open comment that bears on a decision the session asks is named in that question, which answers it with the facts looked up first; when it objects to the options, they are revised or the question says why they stand. One that bears on none is answered directly where the skill may write, with an answer reply (`records.md` "Answer replies"), and named in one line of the session's report.

## Replies in chat

After the plan check and after each `mentat second-opinion` round, show the replies in chat as `records.md` "Reply block" says; with an external backlog, also record the settlement and attach the replies as its "Plan check and second opinions" says.

## Forwarded writes

A backlog write a started implementation session sends back is made by its starting session, as `mentat-lead:orchestrate` says.

## Tracker: Linear

Where AGENTS.md names a Linear project, call the Skill tool with `mentat-linear:linear` before any Linear action, and again after a compaction. When it is not available, say the `mentat-linear` module is off and go on as "Reaching the backlog" says.

## Tracker: GitHub issues

Where AGENTS.md names no external backlog, read `github.md` in this skill's folder before any backlog action, and again after a compaction.
