Read every applicable AGENTS.md first; it wins only on commit and title format, branch flow, labels and templates. The maintainer's own instructions may set only choices the skills name, and add checks. Neither loosens "Approval" or "What agents never do".

## Approval
The maintainer merges every pull request.

## What agents never do
Merge pull requests, turn on auto-merge, use `--admin`, or work around a merge refusal.

Create releases, deploy, publish, change secrets, run production migrations or destructive outside operations; agents only prepare these.

Commit secrets. Exposed ones are reported to the maintainer at once, for rotation, not just deletion.

Push code to the default branch, force-push shared branches, or change repository settings.

Bring production credentials into a session.
