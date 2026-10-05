# Setting up and removing Mentat

*For people. Agents follow `rules.md`, not this page.*

## Using Mentat in a repository

You need macOS, Claude Code, `git`, `jq` (the `mentat` command and the reply hook both use it; without it the hook does nothing), the Codex CLI signed in (`mentat challenge` runs it, and `mentat setup` reports a problem when it is missing), a ChatGPT plan with Codex code review, and `gh` signed in as a separate agent account. Protected branches and code owners on a private repository need GitHub Pro or above ([GitHub's plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)).

1. Before the agent has any access, import [`ruleset.json`](../ruleset.json): Settings > Rules > Rulesets > New ruleset > Import a ruleset, open the file, review it and click Create. The file requires a check named `test`; if your CI check has another name, put that name in while reviewing, or the ruleset will wait for a check that never runs. `mentat setup` accepts a required GitHub Actions check of any name. A ruleset the repository already has can stay: rulesets add up and the stricter rule wins. GitHub refuses the import if a ruleset with the same name exists, so the file uses a name of its own. A personal repository cannot give a collaborator read-only access, so protection must exist before the agent can write.
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
