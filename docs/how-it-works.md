# How Mentat works

*For people. Agents follow `rules.md` and the skills in `skills/`, not this page.*

## How a change moves, in full

From a request to a merge; the numbered steps below describe each part.

```mermaid
flowchart TD
    A["You ask"] --> B["Claude Code plans"]
    B --> C["Claude Code builds and opens<br/>a draft pull request"]
    C --> D["Codex reviews"]
    D -- findings --> E["Claude Code fixes or answers"]
    E --> D
    D -- ready --> F["You merge"]
```

`rules.md` holds what applies in every session and names a skill for each step below; each skill's file is the source of truth for that step.

1. Work starts from a chat request or an issue. Claude Code reads the repository's AGENTS.md files and the code, then writes down what it will build and how it will be checked. An uncertain or consequential plan gets a Codex challenge first ([`skills/plan`](../skills/plan/SKILL.md)).
2. One builder, one branch, one checkout per change. The repository's test command runs before the pull request opens and after every fix.
3. Every pull request opens as a draft, with a description that gives a short summary, before-and-after evidence and the merge danger ([`skills/pr`](../skills/pr/SKILL.md)).
4. When it is built, `mentat review` waits for CI on the head, then Codex reviews it, through OpenAI's Codex GitHub app or local Codex. Claude Code fixes findings that have a realistic trigger, answers the rest with a reason, and reviews again; a real defect is never left to a follow-up issue on its own, and five rounds is a hard stop. OpenAI's page says the Codex app flags only P0 and P1 issues (it has posted P2s here); a local review reports P0 to P3 and reads the issues the pull request closes as well as its description. When the loop ends ready, it posts a final check, the author's own check and not an approval, and tells you the pull request is ready. If the loop is blocked, not reviewed, or reaches five rounds without being ready, it tells you why and stops. A pull request that changes only prose people read, such as `docs/` pages or a README, skips the loop: Claude Code posts the final check and leaves the merge to you, even in an opted-in repository. With the Codex app, marking it ready still starts the app's review ([`skills/review`](../skills/review/SKILL.md)).
5. You merge it, the way your repository merges. Or opt the repository in, and Claude Code merges its own pull requests once the review loop ends ready ([Letting agents merge](setup.md#letting-agents-merge)).

After a session that went badly, `/mentat:retro` reads it and proposes fixes to the setup: checks over written rules, pointers, deletions. It changes nothing until you approve; approved fixes become issues or pull requests ([`skills/retro`](../skills/retro/SKILL.md)).

## The repository comes first

Mentat requires nothing of a repository's GitHub settings. Rulesets, required approvals, merge methods and CI are yours, and Mentat works within whatever you have. Where your AGENTS.md says something different from Mentat's rules on a preference, such as commit format, branch flow, or a workflow that commits to the default branch, your AGENTS.md wins.

If your repository requires an approval and the agent opens pull requests as you, GitHub will not let you approve your own pull request. Use a separate GitHub account for the agent in that case; Claude Code tells you when it happens.

## What holds, and how

### Claude Code hooks

- The SessionStart hook puts `rules.md` into every session's context, on startup, resume, clear, compact and fork.
- The merge hook asks you in a permission prompt before any `gh pr merge` command (including `--auto`), any call to the pull request merge API through `gh api`, and the desktop app's auto-merge tool. One exception: in a repository that opted in, a merge API call for that repository goes through Claude Code's normal permission rules without Mentat's prompt; the hook reads the opt-in from GitHub each time. Claude Code's docs say a hook's "ask" still prompts in auto mode; behavior in bypass-permissions mode is not documented. It is a net for mistakes, not a security boundary: other routes to a merge exist.
- The reply hook checks each final reply when you have chosen the Mentat output style. The style asks for 100 words; over 250 outside fenced code blocks, an em dash or a blockquote gets one request to rewrite it. It reads `outputStyle` from your settings files (local, then project, then user) and asks once per turn, never cutting text itself.
- The decisions pane (`hooks/decisions-pane.tsx`, a Claude Code mod) shows a band above the prompt with how many decisions wait on you, and a pane, opened by the band's Show button or `/decisions`, that lists them. The agent records each question with two tools, `open_decision` and `close_decision`; nothing forces it to. Answering in the pane sends your answer as a chat message, and Dismiss closes the entry. The pane approves, denies or changes no tool call.
- `bin/mentat` is on the Bash tool's PATH while the plugin is enabled.

### Instructions, not guarantees

`rules.md` asks agents never to merge (unless you opted the repository in), release, deploy, publish, change secrets or run production operations; never to commit secrets; never to push code changes to the default branch or change repository settings; and to keep production credentials out of agent sessions. An agent that ignores its instructions can still do what its GitHub access and your Mac allow. Mentat does not sandbox it; Claude Code's permission modes are the local control. To have GitHub enforce rules, see [Have GitHub enforce it](setup.md#have-github-enforce-it).

They draw on:

- [Anthropic's Claude Code best practices](https://code.claude.com/docs/en/best-practices): give the agent a check it can run, plan only when the approach is uncertain, keep instruction files short, and use an independent reviewer told to flag only what affects correctness or the stated requirements, because chasing every finding leads to over-engineering.
- [OWASP's AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html): least privilege for agent tools, human approval for high-impact or irreversible actions, and minimal sensitive data in agent context.
- [When Does a Second Model Help? Cross-Model Review in LLM Verification](https://arxiv.org/html/2610.01471) (Song, 2026): different models catch partly different errors, though capability differences make the benefit of diversity alone hard to isolate.

### Mentat's own choices

These are design choices, not proven results:

- You merge, by default. Agents plan, build and answer reviews; letting them merge is your choice, one repository at a time.
- A different model family reviews the builder's work: Codex reviews what Claude Code builds.
- Reviews come from OpenAI's Codex GitHub app when it is set up, which posts under its own identity with comments on specific lines. It was chosen over a local review after a five-pull-request comparison ([issue 3](https://github.com/ericfurspan/mentat/issues/3)). The local review is the fallback and is labeled as one.
- Review findings are fixed only when they have a realistic trigger; gates stay small.
- macOS only, with scripts in plain bash that also runs on macOS's bash 3.2.

## Commands

| Command | What it does | Exit codes |
|---|---|---|
| `mentat review <PR>` | Waits for CI on the pull request's head (up to 30 minutes; with no CI, about a minute), then marks the pull request ready, which starts the Codex app's review of that head, and waits for the result. The result is read from the app's summary comment, which names the reviewed commit; when that comment is missing or unreadable, the review is "not reviewed" and Claude Code falls back to `--local` | 0 no findings, 2 findings posted (printed), 1 not reviewed, 3 head moved, 4 CI did not pass (failing or unfinished checks printed) |
| `mentat review --local <PR>` | Waits for CI the same way, then reviews the pull request's head with local Codex in a temporary checkout, and posts the result on the pull request if the head has not moved | same |
| `mentat challenge <plan-file>` | Codex challenges a written plan against the repository and ends with a verdict | 0 delivered (read the verdict), 1 not challenged |
| `mentat check` | Checks, read-only, what Mentat itself needs: `git`, `gh` and `jq` installed, `gh` signed in, the repository readable. Prints the installed `codex` version. Warns when `codex` is missing or the repository has Actions secrets a branch workflow may read | 0 Mentat can work, 1 it cannot |

Usage errors exit 64.

Local Codex (`review --local` and `challenge`) runs under a permissions profile that lets it read only the checkout, its git directory and system and tool paths, with no writes and no network for the commands it runs. Codex itself still talks to OpenAI, and its web search runs on OpenAI's side, outside that profile: local reviews turn search off, and `mentat challenge` keeps Codex's cached search (OpenAI's index, no live fetches) to check current practice. Inside the checkout, files that commonly hold credentials (`.env` files, private keys such as `*.pem` and `id_ed25519`, `.netrc`, `.npmrc`, `.pypirc`) are denied to it as well. This protects files kept out of git; a credential committed to the repository stays readable through git history, as it is to anyone with the repository, and must be rotated. Only basic environment variables (such as `HOME`, `PATH` and `USER`) reach the commands it runs. Codex must be installed under `/opt/homebrew` or `/usr/local`; anywhere else it cannot start and the command reports not reviewed or not challenged.

## What it does not do

- Linux, Windows, other Git hosts, organizations and team workflows.
- Running deployments or infrastructure.
- Changing your repository's GitHub settings, or checking any beyond whether it has Actions secrets.

## Developing Mentat

`tests/run` is the one test command; it runs locally on macOS and in CI on both macOS and Linux. This repository's own settings require the maintainer's Approve on every change.
