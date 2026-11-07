<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/mentat-mark-dark.svg">
    <img src="docs/images/mentat-mark.svg" alt="Mentat" width="80" height="80">
  </picture>
</p>

<h1 align="center">Mentat</h1>

<p align="center"><a href="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml"><img src="https://github.com/ericfurspan/mentat/actions/workflows/tests.yml/badge.svg" alt="tests"></a></p>

Mentat is a set of multi-agent AI development lifecycle tools (skills, hooks, commands) and rules for how agents communicate. It runs as a Claude Code plugin and covers brainstorming, planning, proposing, building and reviewing: Claude Code plans and builds, Codex and Grok give second opinions and review the code, and the maintainer decides what gets built and merges every pull request. Normally Codex reviews the pull request after every fix and Grok adds a second review where it is installed, and the maintainer merges. Along the way, the maintainer can see what waits on them with `/mentat:agenda`, gather and settle ideas with `/mentat:intake`, plan the backlog with `/mentat:plan`, build agreed items in a row with `/mentat:work-tickets`, step back with `/mentat:zoom-out`, put one question to several models with `/mentat:consult`, and review a session for improvements with `/mentat:retro`.

<p align="center">
  <img src="docs/images/mentat-checks.svg" alt="A change moves from request to plan, build, review and merge. Codex and Grok give a second opinion on the request, Codex critiques the plan when needed, and both review the code. The maintainer asks for the change, approves the plan and merges." width="680" height="320">
</p>

## How a change moves

1. A request in chat or a backlog item, or a change Claude Code suggests itself. Claude Code reads the code and gives its view; for all but a one-line change with nothing to decide, Codex and Grok weigh it too (`mentat weigh`), and one that changes the meaning of what an agent is told in standing instructions (Mentat's `rules.md`, skills or builder prompt, a repository's `AGENTS.md` or the like) is weighed however short. The maintainer agrees on what gets built.
2. A builder subagent makes the change, or a batch of changes the maintainer agreed to, on its own branch and runs the test command; the chat shows plans and reports, not diffs.
3. Claude Code opens a pull request; its description opens with a `## Summary` heading, then a status line, a `Why:` line saying where the work came from, and a note of at most two sentences: what the change does, then the one thing to read before merging, when there is one. Codex reviews the head commit, and Grok the first one, while CI runs; `mentat review` posts each review only once CI passes on that head. If Grok cannot run, for example because it is not signed in, Codex carries on and the description says why; nothing stops for it. Findings with a realistic trigger are fixed, the rest answered with a reason, for at most five rounds. This outside review is the normal path, with three exceptions, each the maintainer's call: a fast track lets a typo-level change skip both reviews, a waived push skips the round for a push after Ready that changes no file a program runs, and Claude-only mode (`/mentat:claude-review`) replaces both with one Claude review.
4. Claude Code checks the diff against the description and the spec, marks the status line Ready and reports it as "You: merge #N." with at most one more sentence; a hand check still open blocks it instead, with its steps at the top of the backlog item or pull request and one sentence in chat.
5. The maintainer merges. Hooks ask before risky git commands: a merge, a push to the default branch, a force push, or a push or pull request with uncommitted changes. Another asks before an agent publishes GitHub text with a local path or a private name in a public repository. They catch mistakes and are not a security boundary.

The agreed text has the shape of a spec, and each requirement is traced to its evidence.

[How it works](docs/how-it-works.md) has the full flow.

Mentat is built with Mentat. Pull requests here are opened by an agent account under this workflow and merged by the maintainer; that account cannot approve its own pull requests. The [merged pull requests](https://github.com/ericfurspan/mentat/pulls?q=is%3Apr+is%3Amerged) show the flow as it ran.

## Requirements

- macOS only, with Claude Code, `git`, `jq`, and `gh` signed in.
- Required for reviews: the Codex CLI signed in and installed under `/opt/homebrew` or `/usr/local`, as part of its sandbox. Elsewhere Codex's own runs (its reviews, and its part of `mentat challenge`, `mentat weigh` and `mentat consult`) cannot start; Grok's review, `mentat ci` and Claude-only mode still run. Codex's effort is fixed at high.
- Optional: Grok Build (`grok`), for a second review and a second view in `mentat weigh`. It runs only on your own sign-in (`grok login`) and does not use an API key from the environment.

## Install

```bash
claude plugin install mentat --marketplace ericfurspan/mentat
```

This adds the marketplace and installs at `user` scope, once per machine, so Mentat is on in every folder. Before Claude Code 2.1.292: `claude plugin marketplace add ericfurspan/mentat`, then `claude plugin install mentat@mentat`. To install for one repository instead, use `--scope project` or `--scope local` ([plugin scopes](https://code.claude.com/docs/en/plugins/install)).

Run these in a terminal:

| What | Command |
| --- | --- |
| Turn it off in one project | `claude plugin disable mentat@mentat --scope local` in that checkout. Back on: `claude plugin enable mentat@mentat --scope local` |
| Update | `claude plugin marketplace update mentat`, then `claude plugin update mentat@mentat --scope user`, then `/reload-plugins` in a running session |
| Remove | `claude plugin uninstall mentat@mentat --scope user` |
| Where it is installed and on | `claude plugin list` |

`uninstall` names the scope the install used; `claude plugin list` shows it.

The `mentat` command is on Claude Code's Bash tool's PATH while the plugin is on, not on the terminal's. `mentat review` runs from this machine with the Codex CLI and needs nothing installed on the repository.

Where the repository requires an approval, the agent needs a separate GitHub account.

## Commands

The `mentat` command (`review`, `status`, `challenge`, `weigh`, `consult`, `check`) runs from Claude Code's shell; [How it works](docs/how-it-works.md) lists each with its exit codes. Outside the workflow, `weigh`, `challenge` and `review` run in a git checkout, and `review` needs a GitHub pull request and posts one review (the review loop runs only in the plugin); `consult` runs in any folder.

- `/mentat:agenda [project ... | all]`: what waits on you and the one item to do next, from the backlog of each project you name; with none, it first asks which, or covers the session's repository when your own instructions name no projects. Changes nothing.
- `/mentat:intake [project ... | all] | brainstorm <text or link>`: one sitting that gathers ideas from the channels your own instructions name, or from a text or link, and settles each with you, one question at a time. With no project names, it first asks which projects' ideas to settle, unless your own instructions name no projects. Taking an idea on files it in the backlog; agreeing to build it stays a separate step.
- `/mentat:plan [item id]`: plans one backlog item, or with no argument interviews you across the open backlog, one decision per prompt. It builds nothing and ends with a `/mentat:work-tickets` command for the agreed items, to paste into a new session. For one plan or idea, ask in words to be grilled.
- `/mentat:work-tickets [item id ...]`: builds agreed backlog items in a row, one pull request each, after one quick check with you; with no ids, the project's next agreed work. Items that need planning are left out with the `/mentat:plan` command to run. It ends with what to merge.
- `/mentat:zoom-out`: a one-time summary of the goal, progress, open questions and the next step. Changes nothing.
- `/mentat:retro`: reviews a session and proposes improvements one at a time, with evidence. Agreed ones are filed in the backlog.
- `/mentat:setup`: shows the repository's Mentat settings (the backlog, the test command, the Code Review Rules that Codex and Grok follow) and changes the ones you pick, in AGENTS.md. It can also move planning from GitHub issues to a Linear project.
- `/mentat:consult [--web] <question or idea>`: gets Codex, Grok and Claude Code's views and answers in five short lines at most: the consensus first, then what each model adds. A plan for the repository you are in is weighed against its code at HEAD, unless the repository holds personal data; anything else, or anything after `--web`, is asked with the web only and runs anywhere.
- `/mentat:claude-review`: turns Codex and Grok off for the session. One Claude code review replaces the review loop, and plans are not challenged or ideas weighed, until you say in chat to turn Codex back on.

## Docs and credits

- [How it works](docs/how-it-works.md): the full flow, the hooks, the commands.
- Third-party credits and licenses: the `CREDITS.md` files under `skills/`.
