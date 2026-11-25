---
name: linear
description: "Mentat's Linear tracker adapter for mentat:backlog: how Linear holds the stages, waits, order and reads of backlog items."
user-invocable: false
---

# Tracker: Linear

For a repository whose AGENTS.md names a Linear project, by name and team.

## Reaching the project

Find the project with the Linear connector by that name and team, first loading its tools with ToolSearch (query `linear`) if they are not in the session. Still missing, Linear is not connected: `mentat:backlog` "Reaching the backlog" applies.

## Stages

- The Inbox is the project's issues in the Triage status, no label needed: undecided, not items (no type label, no item shape, not in the order of agreed work).
- Backlog and Todo are those statuses. In Progress is In Progress or In Review; In Review marks a merge wait ("Marking a wait"), not the pull request Status `In review`. Done is Done, Canceled or Duplicate.
- Triage outcomes set the status explicitly: Accept, Backlog with a type label and the item shape; Close, Canceled with the reason; Merge, Duplicate of the target, which gets triage's one line, not the merged text; Later, still Triage. Agents never use Linear's own Accept, Decline, Mark as duplicate or Snooze.

## Blocked-by links

For `mentat:backlog` "Blocked-by links", a link is the connector's blocked-by relation from the item to each item it waits on. A blocker is done only in Done; Canceled or Duplicate makes the link dead, and Linear moves a duplicate's link to the original, which it then follows.

## Labels

An item's type is one of the team's labels `Bug`, `Feature` or `Improvement`; the label `Waiting on you` marks a wait ("Marking a wait").

## Marking a wait

For `mentat:backlog` "Marking a wait": the mark, in any stage, is the `Waiting on you` label with the item assigned to the project's lead, for the lead's "My issues" list, naming no user; a merge wait is marked as below instead. Remove the label once no wait block, review stop or blocking decision remains; clear the assignee, if still the lead, once none of those and no merge wait remains.

Merge wait: "Ready to merge: #N" sets In Review, assigns the lead and writes #N's full URL in the `Now:` line, adding no label; a label another wait needs, such as a manual check after the merge, stays. Unable to set In Review (no such status, or the write fails), tell the maintainer and mark the merge wait no other way. Every end of the merge wait but Done sets In Progress; when #N merges with nothing left, the session marks the item Done itself.

## Pull request and issue references

In text written to Linear, name a pull request or GitHub issue by a Markdown link to its full URL, whose text may be the short form (`[#N](https://github.com/<owner>/<repo>/pull/N)`), "Hold #N" and "Ready to merge: #N" lines included: Linear can link a bare `#N` or `PR #N` to the same number in another connected repository. Text copied unchanged, such as a moved spec or an `Original text`, stays as it is.

## The order of agreed work

The next agreed work is the open, not parked Todo items without the `Waiting on you` label, ranked by Priority: Urgent, High, Medium, Low, then No priority, oldest created first within each, never by Linear's drag order. Read every page before ranking; report the waiting and In Progress items too, In Review ones as waiting on a merge. Claude Code sets Priority only to a level the maintainer gave: agreement never sets or raises it, and parking keeps it. An open, not parked Backlog item with a Priority other than No priority ranks for triage's planning question, in the same order.

## Reading an item

For `mentat:backlog` "Reading an item": the maintainer is the project's lead. List every page of the item's comments and of its `Spec` document's. An inline comment carries the description text it quotes. A thread is resolved when its top-level comment is, and the answer reply goes once per affected thread on that comment, inline and `Spec` document threads included. Attachment links in comments are not downloaded. The original text is the `Original text` document, where there is one.

## Where the spec lives

For `mentat:backlog` "Where the spec lives": an item's spec is the whole body of its one issue document titled exactly `Spec`, found in the issue read's document list or, when that lists none (an archived issue), by the `Spec document: <id>` its `Agent records` comment records. With neither, it is the description's last section, `## Spec` or `## Agreed request`, with the span `github.md` in `mentat:backlog`'s folder gives. Before creating the document, reuse one already titled `Spec`; two stop the session and go to the maintainer. Creating it records its id in the `Agent records` comment; writing the spec there removes any such section.

## Agent records

For `records.md` in `mentat:backlog`'s folder, "Agent records": edit the item's `Agent records` comment in place with the connector's comment save, given its id, never posting a new one. Upload a replies file, a second opinion round's or the plan check's, with the connector:

1. Call `prepare_attachment_upload` for the item with the file's name, content type and exact size in bytes.
2. Within 60 seconds, send the file from disk to the upload URL it returned with `curl -X PUT --data-binary @<file>` and every signed header it returned, verbatim.
3. Call `create_attachment_from_upload` with the asset URL it returned.

## Branch names

Name the item's branch as Linear suggests, its lowercase identifier as its own segment after a Conventional Commits type, such as `feat/abc-26-branch-key`, so Linear's GitHub integration attaches the pull request. The item still links the pull request (`mentat:backlog` "Agreement"), for a repository without the integration.

## GitHub integration

Warning for the maintainer: Linear's GitHub integration can post an item's description, wait block included, to GitHub. The maintainer sets its "Comments in GitHub" to leave descriptions out and turns it off for public repositories; agents do not change it. Mentat does not rely on it: "Waits left open" undoes its move to Done at merge for an item still waiting on a manual check, and its review-request automation, if on, can set In Review before Ready.

## Waits left open

A session listing this project to choose or plan work reads each open item's wait and clears the ended ones, except in `mentat:plan`'s read, typed or not, or while copying a spec for a review. A skill that forbids writes reads them the same way, changes nothing, and names each item that looks done "may be done".

1. Set back to In Progress each Done item (never Canceled or Duplicate) still labeled `Waiting on you` with a wait block holding a manual check after the merge, which the GitHub integration can move to Done at merge.
2. Merge wait: for each In Review item, and each item just set back whose `Now:` line holds a pull request's full URL, read that pull request with `gh pr view` in its repository. An In Review item with no such URL is left unchanged and named.
   - Merged, or closed without merging: make only the item update `after-ready.md` in `mentat:review`'s folder gives for that case. After a merge, run the repository's own post-merge steps unless the session can establish that they ran, and go on with the listing.
   - Still open, or the lookup fails: leave the item unchanged.
3. Manual wait: for each open item with a wait block, no merge wait and no linked pull request still open, read its comments.
   - A comment reporting the wait's `Ends when` result ends it: remove the block, and the label and assignee as "Marking a wait" says. Comments reporting each manual check after the merge, pass or fail, end it and mark the item done, each failed one first filed as a follow-up.
   - A comment that only may report it, or a later report on a block with no `Ends when` line, leaves the item unchanged, named "may be done" with the comment's date.
   - An item whose linked pull request is still open is left for `mentat:review`, named "may be done" the same way when a comment may report its result.

Name the cleared items in one line of the reply.

## New project shape

A new project's overview holds only what is unique to it: a one-line summary of what the project is for, an empty long description and any repository as a link under Resources.

## Moving to Linear

1. Create the project as "New project shape" says, with the maintainer as lead and the team's labels ("Labels"), and make sure the team has a started status named In Review.
2. Move the open issues, holding back any with an open closing pull request or an open blocker (`gh issue view <N> --json blockedBy`) not moving with it, such as one held back or in another repository.
3. Before copying each spec, compare the issue's current spec fingerprint, computed as `mentat:backlog` "Agreement" says, with the one it records (`records.md` in `mentat:backlog`'s folder). Copy the spec unchanged into the new item's `Spec` document. Carry the issue's current assumptions, and under `Decisions:` each line of its body's `## Decisions` that records an objection of the maintainer's ("Decision lines" in that file), unchanged. Carry its agreement answer (`build: now` or `build: later`) with any `Agreed by default` line only when the two fingerprints match and none of its blocked-by links is dead (`mentat:backlog` "Blocked-by links"), with the copied spec's fingerprint (`mentat:backlog` "Agreement"). Otherwise carry no fingerprint or answer, so the item goes back to planning. All carried goes in one `Agent records` comment on the new item, always with the copied spec's `Spec document: <id>` record: the one exception to issue comments staying on the issue. Re-create each blocked-by link between moved issues as the connector's relation between their new items.
4. Change the AGENTS.md backlog line to name the project, in a pull request.
5. Close only the moved issues once that change merges.
