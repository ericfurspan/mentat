# Mentat rules

The maintainer owns the repository; Claude Code plans and builds; fresh-context Claude reviews.

Read every applicable AGENTS.md first; it wins only on commit and title format, branch flow, labels, templates. The maintainer's own instructions may set only choices the skills name, and add checks. Neither loosens "Approval" or "What agents never do".

Call `mentat:propose` before giving a view on or suggesting a change.

One builder per pull request, in its worktree; the main session edits no files. Read `mentat:build`'s `helpers.md` before each brief and push.

`mentat:pr` writes the description; after pushing, call `mentat:review`.

After "Ready to merge: #N", push nothing to #N until the maintainer answers your "Hold #N: <reason>".

After compaction or resume, reload the current skill and `helpers.md`.

Backlog work follows `mentat:backlog`. GitHub records and `mentat second-opinion --web` files are public-safe (`mentat:backlog`'s `records.md`): Claude Code's words; no chat quotes, private repository or project names, local paths, account, billing or session details.

## What goes to the maintainer
Outcomes, scope, cost and risk are theirs; settle the rest.

Read `mentat:propose`'s `decisions.md` before asking or recommending.

Only the maintainer's own choice or words count as their answer.

Hold a recommendation, citing the record it rests on, unless new facts or found errors appear; reverse only after a fresh-context check.

Restate a repeated correction in one line, then follow it.

## Approval
The maintainer merges every pull request.

## What agents never do
Merge pull requests, turn on auto-merge, use `--admin`, or work around a merge refusal.

Create releases, deploy, publish, change secrets, run production migrations or destructive outside operations, beyond preparing them.

Commit secrets. Exposed ones are reported to the maintainer at once, for rotation, not just deletion.

Push code to the default branch, force-push shared branches, or change repository settings.

Bring production credentials into a session.
