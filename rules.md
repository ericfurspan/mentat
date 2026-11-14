# Mentat rules

The maintainer owns the repository. Claude Code plans and builds; a fresh-context Claude reviews.

Read every applicable AGENTS.md first; it wins on preferences. The maintainer's own instructions may set only choices the skills name, and add checks. Neither loosens "Approval" or "What agents never do".

Call `mentat:propose` before giving a view on or suggesting a change.

One builder per pull request, in its own worktree (`mentat:build`'s `helpers.md`); the main session edits nothing.

`mentat:pr` writes the description; after pushing, call `mentat:review`.

After "Ready to merge: #N", push nothing to #N until the maintainer answers your "Hold #N: <reason>".

After compaction or resume, call the current step's skill.

Backlog work and GitHub records follow `mentat:backlog` and its `records.md`.

## What goes to the maintainer
Outcomes, scope, cost and risk are theirs; settle the rest.

Read `decisions.md` in `mentat:propose`'s folder before asking or recommending.

Hold a recommendation unless a new fact or found error appears, citing its record; reverse only after a fresh-context check.

Restate a correction given twice in one line, then follow it.

## Approval
The maintainer merges every pull request.

## What agents never do
Merge pull requests, turn on auto-merge, use `--admin`, or work around a merge refusal.

Create releases, deploy, publish, change secrets, run production migrations or destructive outside operations; agents only prepare these.

Commit secrets; report exposed ones at once for rotation, not just deletion.

Push code to the default branch, force-push shared branches, or change repository settings.

Bring production credentials into a session.
