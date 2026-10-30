# How Mentat works

*For people. Agents follow `rules.md` and the skills in `skills/`, not this page.*

## What Mentat is made of

<p align="center"><img src="images/mentat-parts.svg" alt="Inside Claude Code: rules and skills loaded every session, the main session, a builder subagent, and merge and push hooks that ask the maintainer first. The mentat command runs Codex (OpenAI) and Grok (xAI)." width="680" height="400"></p>

## A change, in full

[Who does what](#who-does-what) lists each step, who does it and when. The file that owns a step holds its procedure:

1. Plan: the request, the maintainer's agreement and the spec. [`skills/propose`](../skills/propose/SKILL.md) for the view, the weigh and the agreement, [`skills/plan`](../skills/plan/SKILL.md) for a challenged plan, [`skills/backlog`](../skills/backlog/SKILL.md) for where the spec lives.
2. Build: [`prompts/builder.md`](../prompts/builder.md).
3. Pull request: [`skills/pr`](../skills/pr/SKILL.md).
4. Review and final check: [`skills/review`](../skills/review/SKILL.md), or [`skills/claude-review`](../skills/claude-review/SKILL.md) with Codex off.
5. Merge: the maintainer merges; [`skills/backlog`](../skills/backlog/SKILL.md) covers what follows.

## Who does what

The reference the other pages match.

| What | Who | When | How |
|---|---|---|---|
| Gives a view of a request | Claude Code | every request | chat |
| Requests a change, decides what gets built and agrees on the plan | the maintainer | every change | chat or an issue |
| Weighs an idea | Codex and Grok, in parallel | a new feature or workflow change, before the maintainer agrees | `mentat weigh` |
| Challenges a plan | Codex | an uncertain or consequential plan, after agreement and before the build | `mentat challenge`, through `skills/plan` |
| Builds and runs the test command | the builder subagent | every change and every review fix | one branch, one checkout |
| Runs the test command again, on a clean tree | Claude Code | before every push | the repository's test command |
| Pushes, opens and describes the pull request | Claude Code | every change | `git push`, `gh pr create`; the body from `skills/pr` |
| Reviews each head | Codex | every head, up to five rounds | `mentat review` |
| Reviews the first head | Grok, where installed | once per pull request, beside Codex's first round | `mentat review --grok` |
| Sorts findings and briefs the fixes | Claude Code | every round | `skills/review`, the builder subagent |
| Reviews when Codex is off | Claude (`code-review`) | after `/mentat:claude-review`, at most two rounds, once `mentat ci` passes | `skills/claude-review` |
| Does the final check | Claude Code | when the loop ends ready | reads the diff, the description and the spec; rewrites the status line |
| Merges | the maintainer | every pull request | |
| Marks the backlog item done, does the repository's own post-merge steps and reports in one line, then the next step | Claude Code | after the maintainer merges | `skills/backlog`, chat |

Outside the table, `/mentat:consult <question>` (the maintainer starts it) asks Codex, Grok and Claude Code one question and answers in five short lines at most, the consensus first, then what each model adds; it is no step in a change. Weigh judges a change to this repository's code at HEAD; consult answers any question, no repository, web on. `/mentat:grill` interviews the maintainer about a plan, one clickable question at a time; Claude Code may offer one when a request has several open decisions that depend on each other, and starts it only if the maintainer agrees. A confirmed grill is not agreement to build: a change still gets its weigh, whose file carries the grill's questions and answers, and the proposal, without asking its decisions again. When no change here follows, Claude Code offers once to send them for a consult.

## The repository comes first

Where a repository's AGENTS.md differs from `rules.md` on a preference (commit and title format, branch flow, labels, templates), the repository wins and Claude Code says so once. The rules on approval and on what agents never do always hold.

## What holds, and how

- The SessionStart hook puts `rules.md` into every session's context, on startup, resume, clear, compact and fork, including how decisions and steps reach the maintainer.
- The merge hook asks the maintainer before any `gh pr merge` command (including `--auto`), any call to the pull request merge API through `gh api`, and the desktop app's auto-merge tool.
- The push hook asks the maintainer before a `git push` that would change the default branch (read from `origin/HEAD`, else `main` and `master`): a refspec ending there, a delete of it, `--all`, `--mirror`, or a push with no refspec while it is checked out. It also asks before a force push on any branch (`--force`, `-f`, `--force-with-lease` or a `+refspec`), before a `git push` or `gh pr create` while `git status --porcelain` in the command's directory prints anything, and before `gh pr create --draft` or `-d`.
- `rules.md` tells agents never to merge, release, deploy, publish, change secrets, run production operations, commit secrets, push code changes to the default branch or change repository settings.
- Claude Code plans, briefs and reports and never edits files in the main session. One builder, one branch and one checkout per pull request (several changes share one only when the maintainer agreed to batch them, with one spec whose numbered requirements cover each change); the test command runs before the pull request opens and after every fix, and a bug fix starts with a check that fails on the bug ([`rules.md`](../rules.md) steps 3 and 4, [`prompts/builder.md`](../prompts/builder.md)).
- A pull request opens as a normal one, not a draft, with a `## Summary` heading over a status line (the state, the head commit, the tests and CI), a `Why:` line saying where the work came from (`not recorded` when no record says), and a note to the maintainer of at most two sentences: what the change does, then the sharpest thing to read before merging, if any, with the rest in the folded Verification; the status line and note are rewritten at every update ([`skills/pr`](../skills/pr/SKILL.md)).
- Review stops at five rounds. A loop that is blocked, not reviewed or out of rounds says why in the status line and stops. The final check is Claude Code's own, not a review or an approval; it marks the status line `Ready` and ends "You: merge #N." (an open hand check blocks it instead: the status line is `Blocked`, the steps go at the top of the backlog item or pull request, and chat names the check in one sentence with the link). With an external backlog, the item is then marked waiting on the merge ([`skills/review`](../skills/review/SKILL.md)).
- A Grok review that cannot run, a sign-in refusal included, never stops the loop: Codex carries on and the description says why ([`skills/review`](../skills/review/SKILL.md)).
- A change that cannot alter what code does or what an agent is told (typos, broken links, formatting) can skip the Codex and Grok reviews only on a fast track the maintainer agrees to. Tests, CI and the final check still run, and the status line reads `Not reviewed: fast track agreed by the maintainer` ([`skills/review`](../skills/review/SKILL.md)).
- With Codex off (`/mentat:claude-review`, which turns Grok off too, until the maintainer says in chat to turn Codex back on), there are no plan challenges and no `mentat weigh`, and one Claude `code-review` at medium effort replaces the review loop. The description says Claude reviewed the pull request, and if `code-review` cannot run, the status line says "Not reviewed" and why ([`skills/claude-review`](../skills/claude-review/SKILL.md)).
- The backlog is GitHub issues, unless the repository's AGENTS.md names an external backlog, and Linear is the one supported today. With an external backlog its item is the only record of a change, and no issue is opened on GitHub, which holds pull requests only ([`skills/backlog`](../skills/backlog/SKILL.md)).
- The spec is written to be safe in public: one sentence of intent, numbered requirements that can each be checked, and what is out of scope. The pull request cites each requirement by number. Older items call the spec "Agreed request". With an external backlog, Claude Code copies the spec unchanged and passes it with `--request`, so Codex and Grok judge the change against that text, apart from the description, without access to the backlog; with GitHub issues, the reviews read the issue the pull request closes and `--request` is not used ([`skills/backlog`](../skills/backlog/SKILL.md), [`skills/review`](../skills/review/SKILL.md); [spec-driven development](spec-driven.md) maps the steps to that practice).
- Local Codex (`review`, `challenge` and `weigh`) runs under a read-only permissions profile on the checkout, with credential files (`.env`, private keys, `.netrc`, `.npmrc`, `.pypirc`) denied and no network for the commands it runs. Web search is off for both reviewers. In `challenge` and `weigh`, Codex's search is cached (OpenAI's index, no live fetches); in `weigh`, Grok may use its backend web search (on xAI's side, nothing fetched from this machine; the local fetch tool is denied) and says which claims it checked. `consult` runs both tools with no files or repository at all and with web search on (Codex live, Grok backend; the local fetch tool stays denied). Codex's own global instruction file, when the user has one, loads in every Mentat Codex run, consult included.

The hooks catch mistakes; they are not a sandbox, and Claude Code's permission modes remain the local control.

## Commands

| Command | What it does | Exit codes |
|---|---|---|
| `mentat review [--local] [--request <file>] <PR>` | Waits for CI on the pull request's head (up to 30 minutes; with no CI, about a minute), reviews the head with local Codex in a temporary checkout, and posts the result if the head has not moved. Before posting, any path inside the temporary checkout is rewritten to its repository-relative path, and a link to one points to that file at the reviewed commit on GitHub, so no machine-local path is posted. A reply ending `REVIEW RESULT: INCOMPLETE - <reason>` is posted and counts as not reviewed (exit 1). `--request <file>` gives Codex the agreed request, in its own data block beside any linked issue; the file is read once, before the wait for CI, and a missing, unreadable or blank file is not reviewed (exit 1, nothing posted). The posted comment has an `Agreed request fingerprint` line: the first 12 hex characters of the SHA-256 of the request text (trailing newlines removed), or `none`. Each round posts a new comment: a heading line with the result and the fingerprint, then the bullets and the full reply folded under it, then the `REVIEW RESULT` line again, outside the fold, as its last line (the `--grok` review's comment has the same shape). `--local` means the same | 0 no findings, 2 findings posted (link printed), 1 not reviewed, 3 head moved, 4 CI did not pass (failing or unfinished checks printed) |
| `mentat review --grok [--request <file>] <PR>` | Waits for CI the same way, reviews the head with Grok (if installed) and posts the result (paths inside the export are rewritten as for `mentat review`); `--request <file>` works as for `mentat review` (the file is read before the start comment, and the fingerprint is in the posted review); an `INCOMPLETE` reply counts as not reviewed (exit 1). Posts a start comment first and refuses to run again when one from its own GitHub account is there, so Grok runs once per pull request. Grok runs in its own sandbox with file tools, no shell, no web, on an export of the head without `.git`. Time limit: `MENTAT_GROK_TIMEOUT_SECONDS` (default 1800). `MENTAT_GROK_REASONING_EFFORT`, when set, is passed to Grok as `--reasoning-effort` (unset leaves Grok's default; `weigh` uses the same variable). A failed run leaves a private log that is never printed. A sign-in that is expired or would expire before the time limit and 5 minutes of setup would end is first refreshed silently: Mentat runs `grok models` once in the user's own Grok home, which lets Grok renew it. It refuses at once only if that did not extend it, naming the time and the fix (`grok login` or any `grok` prompt outside Mentat), so Grok never starts on a sign-in that would run out mid-run, since it cannot refresh it inside the run | same |
| `mentat ci <PR>` | Waits for CI on the head the same way and reviews nothing. Used when Codex is off | 0 CI passed or there is none, 1 could not read, 3 head moved, 4 CI did not pass |
| `mentat status <PR> [--request <file>]` | Prints one line of the pull request's review state, read from the comments the review commands posted as the account `gh` is signed in as: the head commit, the number of local Codex rounds (an `INCOMPLETE` review is not one) and of Claude review rounds when there are any, whether the head is the last reviewed commit, the Grok state (none, running, done or did not finish) and the CI state on the head (none, running, passed or failed; read once, not waited for). `--request <file>` adds whether the last review's spec fingerprint matches the file's, computed as `mentat review --request` computes it. Read-only: posts, edits and pushes nothing | 0 printed, 1 could not read, 64 usage |
| `mentat challenge <plan-file>` | Codex challenges a written plan against the repository and ends with a verdict. Printed; with an external backlog, Claude Code then posts the reply on the item | 0 delivered (read the verdict), 1 not challenged |
| `mentat weigh <idea-file>` | Codex and Grok each judge an idea as of `HEAD` (uncommitted changes are not weighed, and the output says so), in parallel: worth doing, a simpler way, the risks. Printed; with an external backlog, Claude Code then posts each reply on the item. Grok may search the web (backend search, no local fetch) and names the claims it checked. Each ends with a verdict line (`DO IT`, `DO IT DIFFERENTLY - <how>` or `DON'T - <why>`) or a "not weighed" line with the reason. Time limits: `MENTAT_REVIEW_TIMEOUT_SECONDS` (Codex) and `MENTAT_GROK_TIMEOUT_SECONDS`; `MENTAT_GROK_REASONING_EFFORT` sets Grok's reasoning effort as in `review --grok`. A failed Grok run leaves a private log that is never printed; a Grok sign-in that is expired or would expire before the time limit and 5 minutes of setup would end is refreshed silently and refused at once only if that did not extend it, as in `review --grok`, so Grok never starts on a sign-in that would run out mid-run | 0 at least one verdict, 1 none (stderr tells Claude Code to give its view alone and say the weighing did not happen), 64 usage |
| `mentat consult <question-file>` | Codex and Grok each answer a question, in parallel, each in an empty folder with no files and no repository, with web search (Codex live, Grok backend; the local fetch tool stays denied). Runs from any folder, in a repository or not. Printed, never posted. Each ends with a `CONSULT: <one line>` or a "not consulted" line with the reason. Time limits and `MENTAT_GROK_REASONING_EFFORT` as in `weigh`; a failed Grok run leaves a private log that is never printed, and a Grok sign-in that is expired or would expire before the time limit and 5 minutes of setup would end is first refreshed silently (`grok models` in the user's own Grok home) and refused at once only if that did not extend it, so Grok never starts on a sign-in that would run out mid-run | 0 at least one answer, 1 none (stderr tells Claude Code to give its view alone and say the consultation did not happen), 64 usage |
| `mentat check` | Checks, read-only, that `git`, `gh` and `jq` are installed, `gh` is signed in and the repository is readable. Prints the `codex` version and fails when it is missing (`mentat ci` and `mentat review --grok` still run without it); prints the `grok` version when installed; warns when the repository keeps head branches after merge | 0 Mentat can work, 1 it cannot |

## What it does not do

- Linux, Windows, other Git hosts, organizations and team workflows.
- Running deployments or infrastructure.
- Changing a repository's GitHub settings. `mentat check` reads one, whether merged head branches are deleted, and changes nothing.

## Developing Mentat

`tests/run` is the one test command; it runs locally on macOS, and on GitHub Actions (macOS) for every pull request. Every change goes through the flow above, and the maintainer merges it.
