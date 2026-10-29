# Tracker: Linear

For a repository whose AGENTS.md names a Linear project, by name and team.

- Step 1: find the project with the Linear connector, by that name and team. If the connector's tools are not in the session, load them with ToolSearch (query `linear`); if they are still missing, Linear is not connected: step 1 applies.
- Step 2: statuses are Backlog (not agreed, or parked), Todo (agreed), In Progress, and Done, Canceled or Duplicate.
- Step 3: type is one of the team's labels: `Bug`, `Feature` or `Improvement`.
- Step 4: on a wait, add the `Waiting on you` label and assign the item to the project's lead, so the lead's own "My issues" list shows it. No user is named. When the wait ends, remove the label and clear the assignee only if it is still the project's lead. If the project has no lead, set the label alone and say once that the item could not be assigned. A merge wait after "You: merge #N." gets the same label and assignment, and the same removal.
- Step 5: the order is a section "Order of agreed work, next first" in the project description. Update it with the connector's project save, which accepts partial edits.
- The item is a Linear issue in that project.
- Name the item's branch with its identifier as its own segment, lowercase, as in the branch names Linear itself suggests, after a Conventional Commits type, for example `feat/wrk-26-branch-key`, so that Linear's GitHub integration attaches the pull request to the item. Step 6's hand-added link on the item stays, for a repository without the integration.
- Step 8: post each comment with the connector's comment tool, on the issue.
- Hand-made items. When a session lists this project to choose or plan work (not while copying a spec for a review, not for `mentat:propose`'s read, and not from a skill that forbids writes), it refines each open item there that the project's lead created, that has none of the type labels and that has no `## Spec` or `## Agreed request` section. First it posts a comment headed as the maintainer's original text, holding the item's title and description as they are; if that comment is refused, the item stays unchanged. Then it sets a title, one type label (`Improvement` when the choice is unclear) and a description holding the item shape's opening sentence and the original's links. A question stays a question: refining neither answers nor researches it. An item in Triage moves to Backlog; one in Todo or In Progress keeps its status and is named in the reply. The assignee and other labels stay as they are. An item that cannot get a fair title or type without inventing what it asks stays unchanged and is named in the reply.
- Merge waits left by GitHub. When a session lists this project to choose or plan work (not while copying a spec for a review, not for `mentat:propose`'s read, and not from a skill that forbids writes), it reads, with `gh pr view` in its repository, the pull request named by each open item with a merge wait: the `Waiting on you` label and an opening sentence saying it waits on the merge of that pull request. Merged: do what `mentat:review` says after "When the maintainer says #N merged" (the wait block's steps, then the item marked done), then the repository's own post-merge steps, unless the session can establish that they already ran. Closed without merging: remove the merge wait (step 4) and leave the status. Still open, or the lookup fails: leave the item unchanged, as with any other `Waiting on you` item. Name the cleared items in one line of the reply, then the next step, with any links on the message's last line.
- Once per session, at that first listing, name in one line of the reply the lead's open items in the team that have no project. Never move an item into a project.
- The team's labels are `Bug`, `Feature`, `Improvement` and `Waiting on you`.
- A new project's description is this text, with the repository's name in place of `<repository>`:

````
Planning for the <repository> repository. Each item is the only record of a change: the request, plan, evidence, status and its "Spec" section, written in public-safe words. GitHub holds code and pull requests only; no issue is opened for agreed work. The `mentat:backlog` skill describes how items move.

## Order of agreed work, next first

Nothing agreed is waiting. Other items are in Backlog.

## How items move

* Backlog: not agreed, or parked
* Todo: agreed
* In Progress: a branch or pull request exists
* Done, Canceled or Duplicate: how it ended
* The "Waiting on you" label: the item waits on the maintainer and is assigned to the project's lead while it waits, with the steps at the top of its description (a merge wait names the pull request in its opening sentence instead)
````
