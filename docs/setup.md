# Turning Mentat on and off

*For people. Agents follow `rules.md`, not this page.*

Mentat needs nothing from your repository's GitHub settings. It works within whatever rules, approvals and CI you already have.

## What you need

- macOS, Claude Code, `git`, `jq`, and `gh` signed in.
- For reviews, one of:
  - OpenAI's Codex GitHub app on the repository (needs a ChatGPT plan with Codex code review), or
  - the Codex CLI signed in, for local reviews. `mentat challenge` also uses it.
- Codex installed under `/opt/homebrew` or `/usr/local` (Homebrew, or npm with a system or Homebrew node). Anywhere else, local Codex cannot start.
- Optional: a separate GitHub account for the agent. Recommended if your repository requires approvals, because GitHub does not let you approve a pull request you opened.

## Turning it on

Once per machine, add the marketplace:

```bash
claude plugin marketplace add ericfurspan/mentat
```

Then, in the repository's checkout, for yourself only (writes `.claude/settings.local.json`, which git ignores):

```bash
claude plugin install mentat@mentat --scope local
```

Or, to turn it on for everyone who clones the repository, use `--scope project`. That writes `.claude/settings.json`, which you commit. Each collaborator also runs `claude plugin marketplace add ericfurspan/mentat` and `claude plugin install mentat@mentat --scope project` once on their own machine.

Start a new session. On its first change, Claude Code runs `mentat check`, which looks only at what Mentat needs and shows any warnings.

### Choosing the Mentat reply style

Mentat ships an output style: result first, about 100 words, no narration. It is not forced on you. To use it in the terminal, pick Mentat with `/config` (Output style) or `/output-style`. In the desktop app, `/config` opens Settings instead of a menu, so set `outputStyle` in a settings file. To choose it for one repository, set `outputStyle` in that repository's `.claude/settings.json` or `.claude/settings.local.json` to the value `/config` saves; this repository uses `"mentat:Mentat"`. The reply hook checks replies only when this style is chosen.

### Reviews

- With the Codex GitHub app: connect the repository to Codex in ChatGPT, install the app on it, and in Codex's code review settings turn on automatic review for all pull requests, triggered on PR open. Without that setting it reviews only when you comment `@codex review`, and `mentat review` gives up after 20 minutes. Claude Code then runs `mentat review --local`.
- Without the app: add a line to the repository's AGENTS.md saying reviews are local, so Claude Code goes straight to `mentat review --local`.
- Either way, Codex follows a `## Code Review Rules` section in AGENTS.md if you add one.

### Plugin updates

Plugin auto-update is off by default for this marketplace, unless a settings file sets `autoUpdate: true`, as this repository's does. The Claude desktop app starts its bundled Claude Code with `DISABLE_AUTOUPDATER` set (seen with its bundled 2.1.286), which also turns plugin auto-update off ([when auto-update runs](https://code.claude.com/docs/en/plugins/loading#when-auto-update-runs)). To update, run `claude plugin marketplace update mentat` and `claude plugin update mentat@mentat --scope <the scope you installed with>`, then restart the session.

## Letting agents merge

By default you merge every pull request. To let Claude Code merge its own pull requests in one repository, add this line to the repository's AGENTS.md and merge it to the default branch:

```text
- Agents may merge their own pull requests.
```

Then, once a pull request's review loop ends ready and the final check is posted, Claude Code merges the commit Codex reviewed through GitHub's merge API. It never turns on auto-merge, and if GitHub refuses (a required approval you have not given, branch protection, a merge queue), it tells you and stops. Required approvals can stay: if it stops because your approval is missing, approve the pull request, then ask it to merge. Remove the line to turn it off; it takes effect at once.

This is a working rule the agent follows, not a guarantee. Opt in only where a merge is cheap to undo, including anything a merge deploys; for deployments, see the environment protection advice under [Have GitHub enforce it](#have-github-enforce-it).

## Turning it off

```bash
claude plugin disable mentat@mentat
```

Turn it back on with `claude plugin enable mentat@mentat`. Both find the scope Mentat is on. A running session keeps Mentat until it restarts.

## Removing it

```bash
claude plugin uninstall mentat@mentat --scope local
```

Use the scope you installed with. What remains:

- Local scope: `.claude/settings.local.json`, still ignored by git, with Mentat's entry removed.
- Project scope: the change to `.claude/settings.json` is yours to commit.
- On the machine: the marketplace, until you run `claude plugin marketplace remove mentat`.
- `"outputStyle": "mentat:Mentat"`, in whichever settings file you chose it in.
- Codex automatic review, if you set it up: turn it off, or disconnect the repository, in ChatGPT.

Mentat never deletes settings files. Remove any `## Code Review Rules` section or review line you added to AGENTS.md if you no longer want it.

## Have GitHub enforce it

Mentat's rules are instructions to the agent, not guarantees. If you want GitHub to stop an agent that ignores them, these are common choices, all yours to make:

- Give the agent its own GitHub account with write access, never admin.
- Add a ruleset on the default branch that requires a pull request and blocks force pushes, with no bypass for the agent's account ([about rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)).
- Require one approval in that ruleset, so pull requests the agent opens wait for your Approve.
- Keep secrets out of reach of workflows a branch can run, or protect them with environments.
