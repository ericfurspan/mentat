# Setup

*For people. Agents follow `rules.md`, not this page.*

What a machine and a repository need for Mentat to run, and the plugin commands. Mentat needs nothing from a repository's GitHub settings; rulesets, required approvals and CI are the repository's own and Mentat works within them.

## What a machine needs

- macOS, Claude Code, `git`, `jq`, and `gh` signed in.
- For reviews, one of: OpenAI's Codex GitHub app on the repository (a ChatGPT plan with Codex code review), or the Codex CLI signed in, for local reviews. `mentat challenge` and `mentat weigh` also use the CLI.
- Optional: Grok Build (`grok`), signed in with `grok login`, adds a second review of each pull request's first head (`mentat review --grok`) and a second view in `mentat weigh`. Without it Mentat reviews as before.
- Codex installed under `/opt/homebrew` or `/usr/local` (Homebrew, or npm with a system or Homebrew node). Anywhere else, local Codex cannot start inside the permissions profile and the run fails closed.
- A separate GitHub account for the agent, where the repository requires an approval: GitHub does not let an account approve its own pull request.

## Plugin commands

Run in a terminal, in the checkout. Scope `local` is this checkout only (`.claude/settings.local.json`, ignored by git); `project` writes `.claude/settings.json`, which is committed, as this repository does; `user` is every folder.

| What | Command |
| --- | --- |
| Add the marketplace, once per machine | `claude plugin marketplace add ericfurspan/mentat` |
| Turn Mentat on in a checkout | `claude plugin install mentat@mentat --scope local` (or `project`, or `user`) |
| Update | `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope <scope>`, then `/reload-plugins` in a running session; the updated rules load at the next session start, resume, `/clear` or compaction |
| Turn it off, and back on | `claude plugin disable mentat@mentat`, `claude plugin enable mentat@mentat` |
| Remove it | `claude plugin uninstall mentat@mentat --scope <scope>`, once per scope and checkout |
| Where it is installed | `claude plugin list` |

Plugin auto-update is off by default for a user-added marketplace unless a settings file sets `autoUpdate: true`, as this repository's does. The Claude desktop app starts its bundled Claude Code with `DISABLE_AUTOUPDATER` set, which also turns plugin auto-update off ([when auto-update runs](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs)).

On a session's first change, Claude Code runs `mentat check`, which looks only at what Mentat needs. The `mentat` command is on Claude Code's Bash tool's PATH while the plugin is on, not on the terminal's.

## The reply style

The plugin ships an output style, not forced: result first, about 100 words, no narration, and whatever needs you at the end, as numbered ❓ decisions with the recommendation marked 💡, and an action under a `Your action` heading. When you are present and the likely answers fit a few fixed options, a decision comes as an interactive prompt (`AskUserQuestion`) instead. In the terminal, `/output-style` picks it; in the desktop app, `outputStyle` goes in a settings file. This repository sets `"outputStyle": "mentat:Mentat"` in `.claude/settings.json`.

## Reviews

- Codex GitHub app: the repository is connected to Codex in ChatGPT, the app is installed on it, and the app's automatic review is off (the repository's Review code setting and Personal preferences), so `mentat review` asks for each review with an `@codex review` comment. The GitHub account the agent uses (the one `gh` is signed in as) must be connected to your ChatGPT account (ChatGPT Settings → Connectors → GitHub → Connect another account); otherwise the app answers the comment with "To use Codex here, create a Codex account and connect to github" and no review runs. If the app does not answer within 20 minutes, `mentat review` gives up and Claude Code runs `mentat review --local`.
- Without the app: a line in the repository's AGENTS.md says reviews are local, and Claude Code goes straight to `mentat review --local`.
- Either way, the reviewer follows a `## Code Review Rules` section in AGENTS.md when there is one.

## Optional skills

- [`grilling`](https://skills.sh/mattpocock/skills/grilling) interviews you about a plan until you agree on it.
- [`the-fool`](https://skills.sh/Jeffallan/claude-skills/the-fool) challenges a plan or claim and ends with a stronger version.

Mentat offers each when it is installed.

## What removal leaves behind

`claude plugin uninstall` removes the plugin's entry from the settings file of that scope and nothing else: the marketplace stays until `claude plugin marketplace remove mentat`; `"outputStyle": "mentat:Mentat"` stays in whichever settings file set it; Codex's review settings stay as set in ChatGPT; and any `mentat-codex-log.*` file in the temporary directory (`$TMPDIR`, else `/tmp`), kept when local Codex exits with an error because it may hold credentials, stays until deleted. Mentat never deletes settings files.
