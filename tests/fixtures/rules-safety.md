Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a named workflow that commits to the default branch), the repository wins and Claude Code says so once; "Approval" and "What agents never do" always hold.

The maintainer's own instructions may set only the choices these rules and the skills name, and may add second opinions or checks; "Approval" and "What agents never do" still hold.

## Approval
- The maintainer merges every pull request.

## What agents never do
- Merge pull requests, turn on auto-merge, merge with `--admin`, or work around a merge refusal.
- Create releases, deploy, publish, change secrets, run production migrations or destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated, not just deleted, so the maintainer is told at once.
- Push code changes to the default branch, force-push a shared branch, or change repository settings.
- Bring production credentials into an agent session.
