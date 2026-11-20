# Settings

Every Mentat setting is an environment variable. Set it in the `env` block of Claude Code's settings: your user settings file for your own values, a project's `.claude/settings.json` for a repository's. A setting set but empty counts as unset and uses its default.

A model setting names a model Claude Code accepts. A model outside your plan bills credits or fails.

| Key | What it does | Default | Empty value |
| --- | --- | --- | --- |
| `MENTAT_REVIEW_MODEL` | The model of the local Claude review (`mentat review`). | `opus` | The default. |
| `MENTAT_FIRST_REVIEW_MODEL` | The model of each pull request's first local Claude review; if no model runs, the review runs again on the review default. | Off: every round runs on the review model. | Off. |
| `MENTAT_REVIEW_ROUNDS` | The local review rounds a pull request may use; a whole number of 1 or more. A higher limit the maintainer names in chat for one pull request is passed to that pull request's runs only (the review skill's "Hard stop"). | `5` | The default. |
| `MENTAT_REVIEW_TIMEOUT_SECONDS` | The time limit, in seconds, of a Claude or Codex review and of Codex in `mentat second-opinion`. | `1200` | The default. |
| `MENTAT_GROK_TIMEOUT_SECONDS` | The time limit, in seconds, of a Grok review or second opinion. | `1800` | The default. |
| `MENTAT_GROK_REASONING_EFFORT` | The reasoning effort Grok runs at, in reviews and second opinions. | `high` | The default. |
| `MENTAT_PLAN_CHECK_MODEL` | The model of the plan check. | The plan checker definition's own model. | The default. |
| `MENTAT_BUILDER_MODEL` | The model of every builder run: a build, a CI fix and a review fix. | The builder definition's own model. | The default. |
| `MENTAT_READY_LIMIT` | The open pull requests with a "Ready to merge" line at which `/mentat-lead:orchestrate` hands over no more items; a whole number of 1 or more. | `3` | The default. |

## Other choices

These are not environment variables:

- `~/.config/mentat/warn-kept-branches`: when this file exists, `mentat check` warns if the repository keeps head branches after merge.
- `~/.config/mentat/private-words`: the private word list, one word per line. The publish check `mentat review` runs before it posts, and the `mentat-public-text` module's hook, refuse text that holds one; `mentat check` warns when the list misses a private repository you can reach.
- The lines Mentat reads from a repository's `AGENTS.md`: see the README's [Configuration](../README.md#configuration).
