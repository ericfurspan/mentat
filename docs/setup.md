# Setup

*For people. Agents follow `rules.md` and `rules-records.md`, not this page.*

What a machine needs for Mentat to run, and the plugin commands.

## What a machine needs

- macOS, Claude Code, `git`, `jq`, and `gh` signed in.
- For reviews, one of: OpenAI's Codex GitHub app on the repository (a ChatGPT plan with Codex code review), or the Codex CLI signed in, for local reviews. `mentat challenge` and `mentat weigh` also use the CLI.
- Optional: Grok Build (`grok`), signed in with `grok login`, adds a second review of each pull request's first head (`mentat review --grok`) and a second view in `mentat weigh`.
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

The plugin ships an output style, not forced: result first, about 100 words, no narration, and whatever needs you at the end, as numbered ❓ decisions with the recommendation marked 💡, and an action under a `Your action` heading. When you are present and the likely answers fit a few fixed options, a decision comes as an interactive prompt (`AskUserQuestion`) instead. In the terminal, `/output-style` picks it; in the desktop app, `outputStyle` goes in a settings file.

## Reviews

- Codex GitHub app: connect the repository to Codex in ChatGPT, install the app on it, and turn the app's automatic review off (the repository's Review code setting and Personal preferences); `mentat review` then asks for each review with an `@codex review` comment. Connect the GitHub account `gh` is signed in as to your ChatGPT account (ChatGPT Settings → Connectors → GitHub → Connect another account), or the app answers "To use Codex here, create a Codex account and connect to github". If the app does not answer within 20 minutes, Claude Code runs `mentat review --local`.
- Without the app: put a line in the repository's AGENTS.md saying reviews are local, and Claude Code goes straight to `mentat review --local`.
- Either way, the reviewer follows a `## Code Review Rules` section in AGENTS.md when there is one.

## Optional skills

- [`grilling`](https://skills.sh/mattpocock/skills/grilling) interviews you about a plan until you agree on it.
- [`the-fool`](https://skills.sh/Jeffallan/claude-skills/the-fool) challenges a plan or claim and ends with a stronger version.

Mentat offers each when it is installed.
