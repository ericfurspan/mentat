# Settings

Every Mentat setting is an environment variable. Set it in the `env` block of Claude Code's settings: your user settings file for your own values, a project's `.claude/settings.json` for a repository's. A setting set but empty counts as unset and uses its default, except `MENTAT_REVIEW_TIMEOUT_SECONDS`, which refuses it. Three are read only from the repository: `MENTAT_REVIEWERS`, `MENTAT_AGENT_MERGE` and `MENTAT_MERGE_WAIT_PATHS`, from the `env` block of `.claude/settings.json` committed on origin's default branch (the merge hook reads the last two from its local copy of that file, the checkout's `origin/HEAD`, which `mentat agent-merge` updates); your environment, user and local settings, the working tree and other branches never count for them.

A model setting names a model Claude Code accepts; `MENTAT_CODEX_MODEL` names a model Codex accepts. A model outside your plan bills credits or fails.

| Key | What it does | Default | Empty value |
| --- | --- | --- | --- |
| `MENTAT_REVIEW_MODEL` | The model of the local Claude review (`mentat review`). | `opus` | The default. |
| `MENTAT_FIRST_REVIEW_MODEL` | The model of each pull request's first local Claude review; if no model runs, the review runs again on the review default. | Off: every round runs on the review model. | Off. |
| `MENTAT_REVIEW_ROUNDS` | The local review rounds a pull request may use; a whole number of 1 or more. A higher limit for one pull request, which the maintainer names in chat or the session takes as its own extra round, is passed to that pull request's runs only (the review skill's `stop.md` "Round limit"). | `5` | The default. |
| `MENTAT_REVIEW_TIMEOUT_SECONDS` | The one time limit, in seconds, of every reviewer: the local Claude review, each outside reviewer in `mentat review --outside` and each in `mentat second-opinion`. A whole number of 1 or more; any other value, set but empty included, exits 64. | `1800` | Refused: exits 64. |
| `MENTAT_REVIEWERS` | The outside reviewers that `mentat review --outside` and `mentat second-opinion` run, in parallel: names separated by commas or whitespace, each the name of a reviewer the `mentat-reviewers` module ships. Read only from the repository, as above. A repository with the module on runs no outside reviewer until it sets this. | Off: no outside reviewer runs. | Off. |
| `MENTAT_CODEX_MODEL` | The model Codex runs, in reviews (`mentat review --outside`) and second opinions. Not checked and with no fallback: a failed Codex run names the model asked for, and a review record whose Codex ran another model adds `(asked for <model>)`. | Off: Codex runs its own default model. | Off. |
| `MENTAT_GROK_REASONING_EFFORT` | The reasoning effort Grok runs at, in reviews and second opinions. | `high` | The default. |
| `MENTAT_PLAN_CHECK_MODEL` | The model of the plan check. | The plan checker definition's own model. | The default. |
| `MENTAT_BUILDER_MODEL` | The model of every builder run: a build, a CI fix and a review fix. | The builder definition's own model. | The default. |
| `MENTAT_AGENT_MERGE` | The value `on` lets a session merge its own pull request once its reviews and CI pass, as `mentat:review` says, except one that changes a path in `MENTAT_MERGE_WAIT_PATHS` or that a reviewer marked high risk, which wait for the maintainer. Any other value is off. Read only from the repository, as above. | Off: the maintainer merges every pull request. | Off. |
| `MENTAT_MERGE_WAIT_PATHS` | The paths whose change makes a pull request wait for the maintainer even with `MENTAT_AGENT_MERGE` on: names separated by commas or whitespace; an entry ending in `/` covers that folder, any other entry is one file. `.github/` and `.claude/` are always on the list. Read only from the repository, as above. | Off: only `.github/` and `.claude/` wait. | Off: only `.github/` and `.claude/` wait. |
| `MENTAT_READY_LIMIT` | The open pull requests with a "Ready to merge" line at which `/mentat-lead:orchestrate` hands over no more items; a whole number of 1 or more. | `3` | The default. |

`MENTAT_GROK_TIMEOUT_SECONDS`, Grok's own time limit before, is no longer read: `MENTAT_REVIEW_TIMEOUT_SECONDS` is the one limit, and `mentat check` says so while it is set.

## Other choices

These are not environment variables:

- `~/.config/mentat/warn-kept-branches`: when this file exists, `mentat check` warns if the repository keeps head branches after merge.
- `~/.config/mentat/private-words`: the private word list, one word per line. The publish check `mentat review` runs before it posts, and the `mentat-public-text` module's hook, refuse text that holds one; `mentat check` warns when the list misses a private repository you can reach.
- The lines Mentat reads from a repository's `AGENTS.md`: see the README's [Configuration](../README.md#configuration).
