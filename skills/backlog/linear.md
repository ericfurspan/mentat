# Tracker: Linear

For a repository whose AGENTS.md names a Linear project, by name and team.

## Reaching the project

Find the project with the Linear connector, by that name and team. If the connector's tools are not in the session, load them with ToolSearch (query `linear`); if they are still missing, Linear is not connected: `mentat:backlog` "Reaching the backlog" applies.

## Stages

The Inbox is the Triage status, every issue of the project in Triage, with no label needed; Backlog, Todo and In Progress are those statuses; Done is Done, Canceled or Duplicate. Inbox issues are undecided, not items: no type label, no item shape, not in the order of agreed work. Triage outcomes set the status explicitly: Accept moves the issue to Backlog with a type label and the item shape; Close sets Canceled, with the reason; Merge sets Duplicate of the target; Later keeps it in Triage. Agents never use Linear's own Accept, Decline, Mark as duplicate or Snooze.

## Start waits

In `start-waits.md`, an `<item id>` is done only in the Done status; Canceled or Duplicate makes the wait dead.

## Types

An item's type is one of the team's labels: `Bug`, `Feature` or `Improvement`.

## Marking a wait

On a wait, add the `Waiting on you` label and assign the item to the project's lead, so the lead's own "My issues" list shows it. No user is named. When the wait ends, remove the label and clear the assignee only if it is still the project's lead. A merge wait after "Ready to merge: #N" gets the same label and assignment, and the same removal.

## The order of agreed work

The next agreed work, the tracker's order, is the open Todo items without the `Waiting on you` label and not parked, ranked by Priority level name: Urgent, High, Medium, Low, then No priority, oldest created first within a level. Linear's own drag order is not used. Read every page of results before ranking, and report the waiting and In Progress items too. Claude Code sets Priority only to a level the maintainer gave: agreement alone never sets or raises it, and parking keeps it.

The Backlog order, for the lookup of the next-work offer (`next-work.md`), is the open Backlog items, not parked, ranked by the same keys: Priority level, then oldest created first within a level. Read every page of results before ranking; Linear's own drag order is not used.

## Reading an item

For `item-reads.md`: the maintainer is the project's lead, the lead field of the project. List every page of an item's comments. An inline comment carries the description text it quotes. A thread is resolved when its top-level comment is resolved. The answer reply goes as one reply per affected thread, on that thread's top-level comment, inline threads included. Attachment links in comments are not downloaded.

## Second opinion records

Upload the replies file with the connector: call `prepare_attachment_upload` for the item with the file's name, content type and exact size in bytes; send the file from disk to the upload URL it returned with `curl -X PUT --data-binary @<file>` and every signed header it returned, verbatim, within 60 seconds; then call `create_attachment_from_upload` with the asset URL it returned. Read the attachment back from the item.

## Branch names

Name the item's branch with its identifier as its own segment, lowercase, as in the branch names Linear itself suggests, after a Conventional Commits type, for example `feat/abc-26-branch-key`, so that Linear's GitHub integration attaches the pull request to the item. The hand-added link on the item that `mentat:backlog` "Agreement" asks for stays, for a repository without the integration.

## GitHub integration

Warning for the maintainer: Linear's GitHub integration can post an item's description, a wait block included, to GitHub. The maintainer sets its "Comments in GitHub" to post without issue descriptions and turns it off for public repositories; agents do not change it.

## Hand-made items

Off unless the maintainer's own instructions turn it on. Then, when a session lists this project to choose or plan work (not while copying a spec for a review, not for `mentat:propose`'s or `mentat:plan`'s read, not for the lookup of the next-work offer (`next-work.md`), and not from a skill that forbids writes), it refines each open item there that the project's lead created, that has none of the type labels, that has no `## Spec` or `## Agreed request` section and that is not in Triage: every item in Triage is the Inbox ("Stages"), settled in triage, so the cleanup skips it by status. First it posts a comment headed as the maintainer's original text, holding the item's title and description as they are; if that comment is refused, the item stays unchanged. Then it sets a title, one type label (`Improvement` when the choice is unclear) and a description holding the item shape's opening sentence and the original's links, with any start wait line unchanged. A question stays a question: refining neither answers nor researches it. An item in Todo or In Progress keeps its status and is named in the reply. The assignee and other labels stay as they are. An item that cannot get a fair title or type without inventing what it asks stays unchanged and is named in the reply.

## Waits left open

When a session lists this project to choose or plan work (not for `mentat:propose`'s or `mentat:plan`'s read, not for the lookup of the next-work offer (`next-work.md`), not while copying a spec for a review, and not from a skill that forbids writes), it reads each open item's wait. Merge wait: it reads, with `gh pr view` in its repository, the pull request named by each open item with a merge wait: the `Waiting on you` label and an opening sentence saying it waits on the merge of that pull request. Merged: do what `../review/after-ready.md` says when the maintainer says #N merged (the wait block's steps, then the item marked done), then the repository's own post-merge steps, unless the session can establish that they already ran. Closed without merging: remove the merge wait ("Marking a wait") and leave the status. Still open, or the lookup fails: leave the item unchanged. Hand wait: for each open item with a wait block, no merge wait and no linked pull request still open, it reads the item's comments. A comment that reports the wait's `Ends when` result ends the wait ("Marking a wait": the block, the label and the lead's assignment removed). A comment that may report it, or a later report on a block with no `Ends when` line, leaves the item unchanged, and the item is named as "may be done" with the comment's date. An item whose linked pull request is still open is left unchanged for `mentat:review`, and named "may be done" the same way when a comment may report its result. Name the cleared items in one line of the reply. A skill that forbids writes instead reads both kinds of wait the same way, changes nothing, and names each item that looks done as "may be done".

## Labels

The team's labels are `Bug`, `Feature`, `Improvement` and `Waiting on you`.

## New project shape

A new project's overview holds only what is unique to it: its short summary is one line saying what the project is for, its long description stays empty, and its repository, where there is one, is a link under Resources.
