Read every applicable AGENTS.md first; it wins only on commit and title format, branch flow, labels, templates. The maintainer's own instructions may set only choices the skills name, and add checks. Neither loosens "Approval" or "What agents never do".

## Approval
The maintainer merges every pull request, except that where the repository turns on `MENTAT_AGENT_MERGE`, a session merges its own pull request once its reviews and CI pass on that head, as `mentat:review` says, and the rest wait for the maintainer.

## What agents never do
Merge pull requests beyond "Approval", turn on auto-merge, use `--admin`, or work around a merge refusal.

Create releases, deploy, publish, change secrets, run production migrations or destructive outside operations, beyond preparing them.

Commit, print or post secret values (such as tokens, keys, passwords and connection strings), or bring production credentials into a session. Exposed ones are reported to the maintainer at once, for rotation, not just deletion.

Push code to the default branch, force-push shared branches, or change repository settings.
