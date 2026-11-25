---
name: linear
description: "Mentat's Linear tracker adapter for mentat:backlog: how Linear holds the stages, waits, order and reads of backlog items."
user-invocable: false
---

# Tracker: Linear

For a repository whose AGENTS.md names a Linear project, by name and team.

## Reaching the project

Find the project with the Linear connector, by that name and team. If the connector's tools are not in the session, load them with ToolSearch (query `linear`); if they are still missing, Linear is not connected: `mentat:backlog` "Reaching the backlog" applies.

## Stages

The Inbox is the Triage status, every issue of the project in Triage, with no label needed; Backlog and Todo are those statuses; In Progress is In Progress or In Review, which marks a merge wait ("Marking a wait") and is not the pull request Status `In review`; Done is Done, Canceled or Duplicate. Inbox issues are undecided, not items: no type label, no item shape, not in the order of agreed work. Triage outcomes set the status explicitly: Accept moves the issue to Backlog with a type label and the item shape; Close sets Canceled, with the reason; Merge sets Duplicate of the target, which gets the one line triage leaves, not the merged text; Later keeps it in Triage. Agents never use Linear's own Accept, Decline, Mark as duplicate or Snooze.

## Start waits

For `mentat:backlog` "Blocked-by links", a start wait is the connector's blocked-by relation from the item to each item it waits on. A blocker is done only in the Done status; Canceled or Duplicate makes the wait dead. When a blocker is marked a duplicate, Linear itself moves its link to the original item, so the wait follows the original.

## Types

An item's type is one of the team's labels: `Bug`, `Feature` or `Improvement`.

## Marking a wait

On a wait other than a merge wait, and on each decision for the maintainer that blocks an item's work, in any stage, add the `Waiting on you` label and assign the item to the project's lead, so the lead's own "My issues" list shows it. No user is named. When a wait ends or a blocking decision is answered, remove the label once no wait block, review stop or blocking decision remains, and clear the assignee, only if it is still the project's lead, only once none of those remains and no merge wait remains. A review stop that asks the maintainer gets the same label and assignment, and the same removal.

Merge wait: "Ready to merge: #N" sets the item's status to In Review, assigns it to the project's lead and writes #N's full URL in its `Now:` line. It adds no `Waiting on you` label; a label another wait needs, such as a hand check after the merge, stays. A session that cannot set In Review (the team has no such status, or the write fails) tells the maintainer and marks the merge wait no other way. Every end of the merge wait other than Done sets the item back to In Progress: work resumes on #N after a hold, #N closes without merging, or #N merges while a hand check after the merge remains (the item then stays open and waiting on that check). The lead's assignment is then cleared only as the paragraph above says. When #N merges with nothing left, the session marks the item Done itself.

## Pull request and issue references

In text a session writes to Linear (descriptions, comments and documents), name a pull request or GitHub issue by its full URL, as a Markdown link whose text may be the short form, such as `[#N](https://github.com/<owner>/<repo>/pull/N)`, never as a bare `#N` or `PR #N`: Linear can turn those into a link to the same number in another connected repository. This holds when a core skill's line naming `#N`, such as "Hold #N" or "Ready to merge: #N", is written into Linear text. Text copied unchanged, such as a spec moved from GitHub issues or an item's `Original text`, stays as it is.

## The order of agreed work

The next agreed work, the tracker's order, is the open Todo items without the `Waiting on you` label and not parked, ranked by Priority level name: Urgent, High, Medium, Low, then No priority, oldest created first within a level. Linear's own drag order is not used. Read every page of results before ranking, and report the waiting and In Progress items too, each In Review item as waiting on a merge. Claude Code sets Priority only to a level the maintainer gave: agreement alone never sets or raises it, and parking keeps it. An open, not parked Backlog item with a Priority level set (not No priority) ranks for triage's planning question, in the same order as Todo items.

## Reading an item

For `mentat:backlog` "Reading an item": the maintainer is the project's lead, the lead field of the project. List every page of an item's comments and of its `Spec` document's comments ("Where the spec lives"). An inline comment carries the description text it quotes. A thread is resolved when its top-level comment is resolved. The answer reply goes as one reply per affected thread, on that thread's top-level comment, inline threads and the `Spec` document's included. Attachment links in comments are not downloaded. An item's original text is read from its `Original text` document, where it has one.

## Where the spec lives

For `mentat:backlog` "Where the spec lives": an item's spec is the whole body of its one issue document titled exactly `Spec`. Read it from the document the issue read lists; when that read lists no documents, as for an archived issue, read it by the id the `Agent records` comment records (`Spec document: <id>`). An item with no `Spec` document and no recorded id reads a `## Spec` or `## Agreed request` section in its description instead, with the span `github.md` in `mentat:backlog`'s folder gives; that section stays last, everything else (`Now:`, links) is written above it, and nothing below it. Before creating the document, read the issue's document list and reuse the one titled `Spec`; two titled `Spec` stop the session and go to the maintainer. Creating it records its id in the `Agent records` comment, and writing the spec there removes any such section from the description.

## Agent records

For `records.md` in `mentat:backlog`'s folder, "Agent records": edit the item's `Agent records` comment in place with the connector's comment save, given that comment's id, never by posting a new one. Upload a replies file, a second opinion round's or the plan check's, with the connector: call `prepare_attachment_upload` for the item with the file's name, content type and exact size in bytes; send the file from disk to the upload URL it returned with `curl -X PUT --data-binary @<file>` and every signed header it returned, verbatim, within 60 seconds; then call `create_attachment_from_upload` with the asset URL it returned.

## Branch names

Name the item's branch with its identifier as its own segment, lowercase, as in the branch names Linear itself suggests, after a Conventional Commits type, for example `feat/abc-26-branch-key`, so that Linear's GitHub integration attaches the pull request to the item. The hand-added link on the item that `mentat:backlog` "Agreement" asks for stays, for a repository without the integration.

## GitHub integration

Warning for the maintainer: Linear's GitHub integration can post an item's description, a wait block included, to GitHub. The maintainer sets its "Comments in GitHub" to post without issue descriptions and turns it off for public repositories; agents do not change it. Mentat does not rely on the integration. Its move of an item to Done at merge is undone for an item still waiting on a hand check ("Waits left open"), and its review-request automation, if on, can move an item to In Review before Ready.

## Waits left open

When a session lists this project to choose or plan work (not for `mentat:plan`'s read, typed or not, not while copying a spec for a review, and not from a skill that forbids writes), it reads each open item's wait, first setting back to In Progress, as open, each item in the Done status, never Canceled or Duplicate, that still has the `Waiting on you` label and a wait block holding a hand check after the merge (Linear's GitHub integration can move it to Done at merge; labels stay). Merge wait: for each item in In Review, and each item just set back from Done whose `Now:` line holds a pull request's full URL, it reads, with `gh pr view` in its repository, the pull request whose full URL its `Now:` line holds; an In Review item with no such URL is left unchanged and named. Merged: make only the item update `after-ready.md` in `mentat:review`'s folder gives when the maintainer says #N merged (the wait block's steps it does, then the item marked done, or kept waiting on each hand check after the merge), then the repository's own post-merge steps unless the session can establish that they already ran, and go on with the listing. Closed without merging: make only the item update `after-ready.md` in `mentat:review`'s folder gives when #N is closed without merging (the merge wait ended, which sets In Progress, and each hand check after the merge removed, with the label and the lead's assignment as "Marking a wait" says). Still open, or the lookup fails: leave the item unchanged. Hand wait: for each open item with a wait block, no merge wait and no linked pull request still open, it reads the item's comments. A comment that reports the wait's `Ends when` result ends the wait ("Marking a wait": the block removed, and the label and the lead's assignment as it says); for hand checks the spec marks as after the merge, comments reporting each one's result, pass or fail, end it and mark the item done, each failed result first filed as a follow-up (`mentat:backlog` "Marking a wait"). A comment that may report it, or a later report on a block with no `Ends when` line, leaves the item unchanged, and the item is named as "may be done" with the comment's date. An item whose linked pull request is still open is left unchanged for `mentat:review`, and named "may be done" the same way when a comment may report its result. Name the cleared items in one line of the reply. A skill that forbids writes instead reads both kinds of wait the same way, changes nothing, and names each item that looks done as "may be done".

## Labels

The team's labels are `Bug`, `Feature`, `Improvement` and `Waiting on you`, which marks every wait except a merge wait, and every decision for the maintainer that blocks an item's work ("Marking a wait").

## New project shape

A new project's overview holds only what is unique to it: its short summary is one line saying what the project is for, its long description stays empty, and its repository, where there is one, is a link under Resources.

## Moving to Linear

1. Create the project as "New project shape" says, with the maintainer as lead and the team's labels ("Labels"), and make sure the team has a started status named In Review.
2. Move the open issues, holding back any with an open closing pull request or an open blocker (`gh issue view <N> --json blockedBy`) that does not move with it, such as one held back or in another repository.
3. Before copying each spec, compute the issue's current spec fingerprint as `mentat:backlog` "Agreement" says and compare it with the one the issue records, read as `records.md` in `mentat:backlog`'s folder says. Copy the spec unchanged into the new item's `Spec` document ("Where the spec lives"). Carry the issue's current assumptions, and under `Decisions:` each line of its body's `## Decisions` that records an objection of the maintainer's ("Decision lines" in that file), unchanged and, only when the two fingerprints match and the issue's start wait is not dead (`mentat:backlog` "Blocked-by links"), its build answer with any `Agreed by default` line, with, as the fingerprint, that of the copied spec as read back from Linear, computed the same way; otherwise no fingerprint or build answer is carried, so the item goes back to planning. What is carried goes in one `Agent records` comment on the new item, always with the `Spec document: <id>` record of a copied spec, the one exception to issue comments staying on the issue. Re-create each blocked-by link between moved issues as the connector's blocked-by relation between their new items.
4. Change the AGENTS.md backlog line to name the project, in a pull request.
5. Close only the moved issues once that change merges.
