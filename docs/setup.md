# Setup

*For people. Agents follow `rules.md`, not this page.*

What a machine needs for Mentat to run, and the plugin commands.

## What a machine needs

- macOS only, with Claude Code, `git`, `jq`, and `gh` signed in.
- Required for reviews: the Codex CLI signed in. `mentat challenge` and `mentat weigh` also use the CLI, and so does `mentat consult`.
- Codex installed under `/opt/homebrew` or `/usr/local` (Homebrew, or npm with a system or Homebrew node), as part of its sandbox. Anywhere else Codex's own runs (its reviews, and its part of `mentat challenge`, `mentat weigh` and `mentat consult`) cannot start; Grok's review, `mentat ci` and Claude-only mode still run.
- Codex's effort is fixed at high.
- Optional: Grok Build (`grok`) adds a second review of each pull request's first head (`mentat review --grok`) and a second view in `mentat weigh` and `mentat consult`. It runs only on your own sign-in (`grok login`) and does not use an API key from the environment.
- A separate GitHub account for the agent, where the repository requires an approval.

## Plugin commands

Run in a terminal. Mentat is installed once per machine at `user` scope, so it is on in every folder.

| What | Command |
| --- | --- |
| Install, once per machine | `claude plugin install mentat --marketplace ericfurspan/mentat` (adds the marketplace and installs at `user` scope). Claude Code before 2.1.292: `claude plugin marketplace add ericfurspan/mentat`, then `claude plugin install mentat@mentat` |
| Turn it off in one project | `claude plugin disable mentat@mentat --scope local` in that checkout. Back on: `claude plugin enable mentat@mentat --scope local` |
| Update | `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope user`, then `/reload-plugins` in a running session |
| Remove | `claude plugin uninstall mentat@mentat --scope user` |
| Where it is installed and on | `claude plugin list` |

`uninstall` names the scope the install used; `claude plugin list` shows it. To install for one repository instead of the whole machine, use `--scope project` or `--scope local` ([plugin scopes](https://code.claude.com/docs/en/plugins/install)).

The `mentat` command is on Claude Code's Bash tool's PATH while the plugin is on, not on the terminal's.

## Reviews

- `mentat review` reviews each head with the Codex CLI on this machine; nothing is installed on the repository.
- In a repository with an external backlog, the agreed request is passed to Codex and Grok as a file (`--request`), because Mentat builds the review prompt itself.
- Codex and Grok follow a `## Code Review Rules` section in AGENTS.md when there is one.

## Per-repository settings

Three settings are prose in the repository's AGENTS.md, with no config file: the backlog (a named external one, else GitHub issues), the test command, and a `## Code Review Rules` section. Claude Code states them in one line when change work starts in a repository. `/mentat:setup` shows them and sets the ones you pick, in one pull request; it can also move a repository's planning from GitHub issues to a Linear project, migrating the open issues.

In a repository with a Linear backlog, branch names carry the item key (for example `feat/abc-26-branch-key`), so Linear's GitHub integration links each pull request to its item. For this to be safe, set the integration's "Comments in GitHub" to post without issue descriptions, and turn it off for public repositories, since an item's description can hold a wait block with steps for the maintainer.

## Plan interviews

To be interviewed about a plan one question at a time, use `/mentat:grill` (see the [README's commands](../README.md#commands)). Claude Code may offer a grill when a request has several open decisions that depend on each other, and starts one only if you agree.
