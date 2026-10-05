# Mentat

How coding agents work in your GitHub repositories: Claude Code builds, Codex reviews, you approve.

Mentat is for one developer on macOS who runs coding agents on their own GitHub repositories. You talk to Claude Code. It plans, builds, opens pull requests and merges. Codex reviews each pull request. You decide what matters, and you approve changes to anything that guards the process.

It ships as a Claude Code plugin: the workflow rules (`rules.md`), an output style, a builder subagent and the `mentat` command.

## How a change moves

`rules.md` is the source of truth. In short:

1. Work starts from a chat request or an issue. Claude Code reads the code, then writes down what it will build and how it will be checked. Uncertain or consequential plans get a Codex challenge first (`mentat challenge`).
2. One builder, one branch, one checkout per change. The repository's one test command runs before the pull request opens and after every fix.
3. Every pull request opens as a draft. When it is built and CI passes, `mentat review` marks it ready, which starts OpenAI's Codex GitHub app review of that exact commit, and waits for the result. Claude Code fixes findings that have a realistic trigger and answers the rest with a reason, then runs `mentat review` again for the new commit. After three review rounds it checks in with you; ten is a hard stop.
4. When the app's latest review is clean, or every finding is fixed or answered with a reason, Claude Code answers any comments you left and posts a final check of that commit as one comment: what was asked and where the diff does it, test and CI results, what was not checked, and what most deserves your eyes. It is the author's own check, not an approval. Then it requests your review and runs `mentat wait`.
5. On your Approve at the current head, it merges with `gh pr merge --squash --match-head-commit <sha>`.

## What enforces what

Mentat separates what is enforced from what is only asked of the agent.

### Enforced by GitHub

These hold whatever the agent does. `mentat setup` checks each one it can observe.

- A ruleset on the default branch: pull requests required with one approval, deletions and force pushes blocked, code owner review required, stale approvals dismissed on push, approval of the most recent push required, squash merges only, and a required check from GitHub Actions (named `test` in `ruleset.json`; any name counts).
- `.github/CODEOWNERS` gives every path to you alone, so changes to guarded files wait for your Approve.
- The agent account has write access, not admin, and cannot bypass the ruleset.

A Codex review is a comment, not a check, so GitHub does not block a merge on it. "The final commit is reviewed" is a rule the agent follows.

### Enforced by Claude Code

- The plugin's SessionStart hook puts `rules.md` into every session's context, on startup, resume, clear, compact and fork.
- The Mentat output style applies whenever the plugin is enabled (`force-for-plugin`), unless another enabled plugin also forces its own style and loads first. It is still an instruction, not a guarantee.
- The plugin's Stop hook checks each final reply. Over 100 words outside fenced code blocks, an em dash or a blockquote gets one request to rewrite it. It asks once per turn and never cuts text itself, so the first reply still shows above its rewrite.
- `bin/mentat` is on the Bash tool's PATH while the plugin is enabled.
- Claude Code's permission modes are the local control. Mentat does not sandbox the agent; it runs on your Mac with your Mac's access.

### Guidance Mentat follows

Instructions in `rules.md`, not guarantees: agents never release, deploy, publish, change secrets or run production operations; never commit secrets; never push to main or change repository settings; and keep production credentials out of agent sessions.

They draw on:

- [Anthropic's Claude Code best practices](https://code.claude.com/docs/en/best-practices): give the agent a check it can run, plan only when the approach is uncertain, keep instruction files short, and use an independent reviewer told to flag only what affects correctness or the stated requirements, because chasing every finding leads to over-engineering.
- [OWASP's AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html): least privilege for agent tools, human approval for high-impact or irreversible actions, and minimal sensitive data in agent context.
- [When Does a Second Model Help? Cross-Model Review in LLM Verification](https://arxiv.org/html/2610.01471) (Song, 2026): different models catch partly different errors, though capability differences make the benefit of diversity alone hard to isolate.

### Mentat's own choices

These are design choices, not proven results:

- A different model family reviews the builder's work: Codex reviews what Claude Code builds.
- Reviews come from OpenAI's Codex GitHub app, which posts under its own identity with comments on specific lines. It was chosen over a local review after a five-pull-request comparison ([issue 3](https://github.com/ericfurspan/mentat/issues/3)). It reviews on its own only when a pull request is marked ready, so a draft is not reviewed unless someone comments `@codex review`.
- A repository with any Actions, Dependabot or environment secret is refused: with write access, the agent could run a workflow on a branch before any review.
- Review findings are fixed only when they have a realistic trigger; gates stay small.
- macOS only, with scripts in plain bash that also runs on macOS's bash 3.2.

## Using Mentat in a repository

You need macOS, Claude Code, `git`, `jq` (the `mentat` command and the reply hook both use it; without it the hook does nothing), the Codex CLI signed in (`mentat challenge` runs it, and `mentat setup` reports a problem when it is missing), a ChatGPT plan with Codex code review, and `gh` signed in as a separate agent account. Protected branches and code owners on a private repository need GitHub Pro or above ([GitHub's plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)).

1. Before the agent has any access, import [`ruleset.json`](ruleset.json): Settings > Rules > Rulesets > New ruleset > Import a ruleset, open the file, review it and click Create. The file requires a check named `test`; if your CI check has another name, put that name in while reviewing, or the ruleset will wait for a check that never runs. `mentat setup` accepts a required GitHub Actions check of any name. A ruleset the repository already has can stay: rulesets add up and the stricter rule wins. GitHub refuses the import if a ruleset with the same name exists, so the file uses a name of its own. A personal repository cannot give a collaborator read-only access, so protection must exist before the agent can write.
2. Invite the agent account as a collaborator. It gets write access, never admin.
3. Connect the repository to Codex in ChatGPT and install OpenAI's Codex GitHub app on it, and in Codex's code review settings for it turn on automatic review for all pull requests, triggered on PR open. Leave exhaustive review and credit use off. Installing the app is not enough: without that setting it reviews only when you comment `@codex review`, and `mentat review` waits 20 minutes and reports not reviewed.
4. The agent opens a pull request with the repository's files:
   - `.github/CODEOWNERS` with `* @<you>`
   - a CI workflow that runs the one test command as a check, named `test` unless you changed the name in the ruleset
   - `AGENTS.md` naming that test command, with a `## Code Review Rules` section
   - `.claude/settings.json` that turns the plugin on:

   ```json
   {
     "enabledPlugins": { "mentat@mentat": true },
     "extraKnownMarketplaces": {
       "mentat": { "source": { "source": "github", "repo": "ericfurspan/mentat" }, "autoUpdate": true }
     }
   }
   ```

   Plugin updates: the Claude desktop app starts its bundled Claude Code with `DISABLE_AUTOUPDATER` set (seen with its bundled 2.1.286), and that turns plugin auto-update off, whatever `autoUpdate` says ([when auto-update runs](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs)). To update, run `claude plugin marketplace update mentat` and `claude plugin update mentat@mentat --scope project` in the repository, then restart the session.

   The ruleset requires one approval, and the agent cannot approve its own pull request, so this one already waits for your Approve, before CODEOWNERS exists.
5. After that pull request merges, the agent runs `claude plugin install mentat@mentat --scope project` once in a checkout that is on the default branch. On a machine that has never used Mentat, the marketplace must be known first: open a session in the checkout and accept the trust prompt, or run `claude plugin marketplace add ericfurspan/mentat`. The committed setting enables the plugin but does not download it ([install scopes](https://code.claude.com/docs/en/plugins/install)); on a branch without `.claude/settings.json` the install writes an untracked one. Then it runs `mentat setup <owner/repo>`. Agents start work only on "Setup OK", in a new session that shows Mentat's rules.
6. Once, by hand, you confirm the blocks hold: a direct push to the default branch and an unapproved merge must both fail.

## Removing Mentat from a repository

In this order, so each step is still allowed when you take it:

1. The agent opens a pull request that removes the `mentat@mentat` entry under `enabledPlugins` and the `mentat` entry under `extraKnownMarketplaces` in `.claude/settings.json`, leaving any other plugin's entries, and, if you want them gone, `.github/CODEOWNERS` and the `## Code Review Rules` section of `AGENTS.md`. It needs your Approve like any other.
2. In each checkout, run `claude plugin uninstall mentat@mentat --scope project`. To remove it from the whole machine, run `claude plugin marketplace remove mentat` instead.
3. Delete the imported ruleset: Settings > Rules > Rulesets > "Mentat rules for the default branch" > Delete ruleset.
4. Remove the agent account as a collaborator: Settings > Collaborators.
5. Turn off automatic review for the repository in Codex's code review settings, or uninstall the Codex GitHub app.

## Commands

| Command | What it does | Exit codes |
|---|---|---|
| `mentat review <PR>` | Marks the pull request ready, which starts the Codex app's review of the current head, and waits for the result | 0 no findings, 2 findings posted (printed), 1 not reviewed, 3 head moved |
| `mentat wait <PR>` | Waits for your response after your review is requested | 0 approved at the current head, 1 needs attention, 2 no response in four hours |
| `mentat challenge <plan-file>` | Codex challenges a written plan against the repository and ends with a verdict | 0 delivered (read the verdict), 1 not challenged |
| `mentat setup <owner/repo> [--check <name>]` | Checks, read-only, that a repository is ready for agents. Any required GitHub Actions check counts; `--check` asks for that one by name. If a rule is missing, it points to `ruleset.json` | 0 ready, 1 incomplete or refused |

Usage errors exit 64.

## What it does not do

- Linux, Windows, other Git hosts, organizations and team workflows.
- Running deployments or infrastructure.
- Local guards that police the agent.
- Checks it cannot observe with write access. `mentat setup` lists these every run: the Codex GitHub app, webhooks and deploy integrations, secret push protection on a private repository, default `GITHUB_TOKEN` permissions, self-hosted runners, cloud access through OIDC trust, and the one-time block test.

## Developing Mentat

`scripts/test` is the one test command; it runs on macOS and in CI on Linux. Every change to this repository waits for the maintainer's Approve.
