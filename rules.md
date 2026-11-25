# Mentat rules

The maintainer owns the repository; Claude Code plans and builds; fresh-context Claude reviews.

Read every applicable AGENTS.md first; it wins only on commit and title format, branch flow, labels, templates. The maintainer's own instructions may set only choices the skills name, and add checks. Neither loosens "Approval" or "What agents never do".

Call `mentat:plan` before giving a view on or suggesting a change.

One builder per pull request, in its worktree; the main session edits no files. Read `mentat:build`'s `helpers.md` before each brief and push.

`mentat:pr` writes the description; after pushing, call `mentat:review`.

After "Ready to merge: #N (<item id>)", push nothing to #N until the maintainer answers your "Hold #N (<item id>): <reason>". Write "Ready to merge" only in `mentat:review`'s line for a ready pull request, or a word-for-word relay of it.

Finish the step in flight first; never interrupt a running builder, review or test run.

Backlog work follows `mentat:backlog`. GitHub records are public-safe (`mentat:backlog`'s `records.md`): Claude Code's words; no chat quotes, private repository or project names, local paths, account, billing or session details.

## What goes to the maintainer
Outcomes, scope, cost and risk are theirs; settle the rest. Read `mentat:plan`'s "Decisions" before asking or recommending. Only the maintainer's own choice or words count as their answer.

After agreement, stop for the maintainer only when: the goal or a required safeguard needs a scope change; a round budget (after its extra round), eval or cost cap is spent; a block only they can clear arises (external, irreversible or a credential); or an agreed manual check is due. Log other calls in the pull request and one batch summary.

Message the maintainer only when something waits on them, plus one line for a commitment they did not ask for, or when they spoke and nothing waits.

Restate a repeated correction in one line, then follow it.

## Approval
The maintainer merges every pull request.

## What agents never do
Merge pull requests, turn on auto-merge, use `--admin`, or work around a merge refusal.

Create releases, deploy, publish, change secrets, run production migrations or destructive outside operations, beyond preparing them.

Commit, print or post secret values (such as tokens, keys, passwords and connection strings), or bring production credentials into a session. Exposed ones are reported to the maintainer at once, for rotation, not just deletion.

Push code to the default branch, force-push shared branches, or change repository settings.
