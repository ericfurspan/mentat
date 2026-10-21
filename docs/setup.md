# Setup

*For people. Agents follow `rules.md`, not this page.*

What a machine needs for Mentat to run, and the plugin commands.

## What a machine needs

- macOS, Claude Code, `git`, `jq`, and `gh` signed in.
- For reviews, one of: OpenAI's Codex GitHub app on the repository (a ChatGPT plan with Codex code review), or the Codex CLI signed in, for local reviews. A repository with an external backlog needs the CLI: its reviews are local. `mentat challenge` and `mentat weigh` also use the CLI, and so does `mentat consult`.
- Optional: Grok Build (`grok`), signed in with `grok login`, adds a second review of each pull request's first head (`mentat review --grok`) and a second view in `mentat weigh` and `mentat consult`.
- Codex installed under `/opt/homebrew` or `/usr/local` (Homebrew, or npm with a system or Homebrew node), for local Codex.
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

## The reply style

The plugin ships an output style, not forced. It is the voice: each reply is written for someone who just walked in, in plain words: what happened, what it means for you, what is left or uncertain, and what you do next. Anything to run or paste comes whole in a fenced block. A failure or a proposal runs as long as it needs. One decision per message, and while work runs Mentat writes only when you are needed, something failed, or the work is done. A skill that sets its own reply shape replaces the style while it runs. How a decision reaches you, as a prompt or as text that ends the turn, is a workflow rule in `rules.md`, so it holds whether or not the style is on. In the terminal, `/output-style` picks it; in the desktop app, `outputStyle` goes in a settings file.

## Reviews

- Codex GitHub app: connect the repository to Codex in ChatGPT, install the app on it, and turn the app's automatic review off (the repository's Review code setting and Personal preferences); `mentat review` then asks for each review with an `@codex review` comment. Connect the GitHub account `gh` is signed in as to your ChatGPT account (ChatGPT Settings → Connectors → GitHub → Connect another account), or the app answers "To use Codex here, create a Codex account and connect to github". If the app does not answer within 20 minutes, Claude Code runs `mentat review --local`.
- Without the app: put a line in the repository's AGENTS.md saying reviews are local, and Claude Code goes straight to `mentat review --local`. In a repository with an external backlog the app is not an alternative: its reviews are always local, with the agreed request passed to Codex and Grok as a file (`--request`), because Mentat builds that prompt itself and whether the app reads a full request in its comment is unverified.
- Either way, Codex (app or local) and Grok follow a `## Code Review Rules` section in AGENTS.md when there is one.

## Per-repository settings

Four settings are prose in the repository's AGENTS.md, with no config file: the backlog (a named external one, else GitHub issues), how pull requests are reviewed (local, or the Codex app), the test command, and a `## Code Review Rules` section. Claude Code states them in one line when change work starts in a repository. `/mentat:setup` shows them and sets the ones you pick, in one pull request; it can also move a repository's planning from GitHub issues to a Linear project, migrating the open issues.

## Optional skills

- [`grilling`](https://skills.sh/mattpocock/skills/grilling) interviews you about a plan until you agree on it.
- [`the-fool`](https://skills.sh/Jeffallan/claude-skills/the-fool) challenges a plan or claim and ends with a stronger version.

Mentat offers `grilling` when it is installed; `the-fool` is yours to start.
