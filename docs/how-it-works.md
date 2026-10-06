# How Mentat works

*For people. Agents follow `rules.md`, not this page.*

## How a change moves, in full

`rules.md` is the source of truth. In short:

1. Work starts from a chat request or an issue. Claude Code reads the repository's AGENTS.md files and the code, then writes down what it will build and how it will be checked. Uncertain or consequential plans get a Codex challenge first (`mentat challenge`).
2. One builder, one branch, one checkout per change. The repository's test command runs before the pull request opens and after every fix.
3. Every pull request opens as a draft. When it is built and CI passes, `mentat review` marks it ready, which starts OpenAI's Codex GitHub app review of that exact commit, and waits for the result. Where the app is not set up, `mentat review --local` reviews that commit with local Codex and posts the result on the pull request. Claude Code fixes findings that have a realistic trigger and answers the rest with a reason, then reviews again for the new commit. After three review rounds it checks in with you; ten is a hard stop.
4. When the latest review is clean, or every finding is fixed or answered with a reason, Claude Code answers any comments you left and posts a final check of that commit as one comment: what was asked and where the diff does it, test and CI results, what was not checked, and what most deserves your eyes. It is the author's own check, not an approval. Then it tells you the pull request is ready.
5. You merge it, the way your repository merges.

## The repository comes first

Mentat requires nothing of a repository's GitHub settings. Rulesets, required approvals, merge methods and CI are yours, and Mentat works within whatever you have. Where your AGENTS.md says something different from Mentat's rules on a preference, such as commit format, branch flow, or a workflow that commits to the default branch, your AGENTS.md wins.

If your repository requires an approval and the agent opens pull requests as you, GitHub will not let you approve your own pull request. Use a separate GitHub account for the agent in that case; Claude Code tells you when it happens.

## What holds, and how

### Claude Code hooks

- The SessionStart hook puts `rules.md` into every session's context, on startup, resume, clear, compact and fork.
- The merge hook asks you in a permission prompt before any `gh pr merge` command (including `--auto`), any call to the pull request merge API through `gh api`, and the desktop app's auto-merge tool. Claude Code's docs say a hook's "ask" still prompts in auto mode; behavior in bypass-permissions mode is not documented. It is a net for mistakes, not a security boundary: other routes to a merge exist.
- The reply hook checks each final reply when you have chosen the Mentat output style. The style asks for 100 words; over 250 outside fenced code blocks, an em dash or a blockquote gets one request to rewrite it. It reads `outputStyle` from your settings files (local, then project, then user) and asks once per turn, never cutting text itself.
- `bin/mentat` is on the Bash tool's PATH while the plugin is enabled.

### Instructions, not guarantees

`rules.md` asks agents never to merge, release, deploy, publish, change secrets or run production operations; never to commit secrets; never to push code changes to the default branch or change repository settings; and to keep production credentials out of agent sessions. An agent that ignores its instructions can still do what its GitHub access and your Mac allow. Mentat does not sandbox it; Claude Code's permission modes are the local control. To have GitHub enforce rules, see [Have GitHub enforce it](setup.md#have-github-enforce-it).

They draw on:

- [Anthropic's Claude Code best practices](https://code.claude.com/docs/en/best-practices): give the agent a check it can run, plan only when the approach is uncertain, keep instruction files short, and use an independent reviewer told to flag only what affects correctness or the stated requirements, because chasing every finding leads to over-engineering.
- [OWASP's AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html): least privilege for agent tools, human approval for high-impact or irreversible actions, and minimal sensitive data in agent context.
- [When Does a Second Model Help? Cross-Model Review in LLM Verification](https://arxiv.org/html/2610.01471) (Song, 2026): different models catch partly different errors, though capability differences make the benefit of diversity alone hard to isolate.

### Mentat's own choices

These are design choices, not proven results:

- You merge. Agents plan, build and answer reviews; the decision to merge stays with you.
- A different model family reviews the builder's work: Codex reviews what Claude Code builds.
- Reviews come from OpenAI's Codex GitHub app when it is set up, which posts under its own identity with comments on specific lines. It was chosen over a local review after a five-pull-request comparison ([issue 3](https://github.com/ericfurspan/mentat/issues/3)). The local review is the fallback and is labeled as one.
- Review findings are fixed only when they have a realistic trigger; gates stay small.
- macOS only, with scripts in plain bash that also runs on macOS's bash 3.2.

## Commands

| Command | What it does | Exit codes |
|---|---|---|
| `mentat review <PR>` | Marks the pull request ready, which starts the Codex app's review of the current head, and waits for the result | 0 no findings, 2 findings posted (printed), 1 not reviewed, 3 head moved |
| `mentat review --local <PR>` | Reviews the pull request's head with local Codex in a temporary checkout, and posts the result on the pull request if the head has not moved | same |
| `mentat challenge <plan-file>` | Codex challenges a written plan against the repository and ends with a verdict | 0 delivered (read the verdict), 1 not challenged |
| `mentat check [owner/repo]` | Checks, read-only, what Mentat itself needs: `git`, `gh` and `jq` installed, `gh` signed in, the repository readable. Warns when `codex` is missing or the repository has Actions secrets a branch workflow may read | 0 Mentat can work, 1 it cannot |

Usage errors exit 64.

Local Codex (`review --local` and `challenge`) runs under a permissions profile that lets it read only the checkout, its git directory and system and tool paths, with no writes and no network. Only basic environment variables (such as `HOME`, `PATH` and `USER`) reach it.

## What it does not do

- Linux, Windows, other Git hosts, organizations and team workflows.
- Running deployments or infrastructure.
- Checking or changing your repository's GitHub settings.

## Developing Mentat

`tests/run` is the one test command; it runs on macOS and in CI on Linux. This repository's own settings require the maintainer's Approve on every change.
