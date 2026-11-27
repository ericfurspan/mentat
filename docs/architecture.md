# Architecture

<!-- loop picture -->

## Parts

- `rules.md`: the core rules, which `hooks/session-start` prints into every session.
- `skills/`: one skill per workflow step: `plan`, `backlog`, `build`, `pr` and `review`.
- `agents/`: the implementer (`builder.md`) and the plan checker (`plan-checker.md`).
- `hooks/`: the session-start hook and the merge hook (`no-merge`).
- `git-hooks/`: the git hooks for agents' `git`, which you set up yourself ([setup](setup.md#git-hooks)).
- `bin/mentat` and `lib/`: the `mentat` command, which runs reviews and holds the checks that give the same answer every time.
- `plugins/`: the optional modules: `mentat-reviewers`, `mentat-public-text`, `mentat-linear` and `mentat-lead`.

## The loop

You plan a change with Claude (`/mentat:plan`). A fresh agent checks the plan, unless the request is small and clear, and you agree once; the spec goes on the item. An implementation session gives each item an implementer in its own worktree, opens one pull request per item and runs review rounds: `mentat review` runs fresh-context Claude on each head, up to the round limit, and, with `mentat-reviewers`, the outside reviewers the repository lists. Each finding is fixed or answered. A ready pull request gets a "Ready to merge" line, and you merge it. With `mentat-lead`, the orchestrator is the one session you talk to: you plan with it, and it hands agreed items to implementation sessions. It may agree to an item by default when nothing on it is open for you, and records it as agreed by default, not as your answer.

## Code and prompts

Code enforces these:

- `hooks/no-merge` denies `gh pr merge`, merges and auto-merge through `gh api`, and MCP merge tools, and denies when it cannot decide.
- The git hooks, where set up, refuse a staged or pushed likely secret and a push that updates a non-local remote's default branch.
- The `mentat-public-text` hook denies a listed `gh` or GitHub MCP write whose text holds a private word or a home path.
- `mentat review` runs Claude headless in a temporary worktree of the head with read tools only, waits for CI on the head before it posts, refuses a round past `MENTAT_REVIEW_ROUNDS` and runs a publish check before it posts.
- `mentat fingerprint`, `mentat worktree` and `mentat state` compute spec fingerprints, make and check branches and worktrees, and keep the orchestrator's state; `mentat check` reports the setup.

Everything else is prompts: `rules.md`, the skills and the agent files tell agents when a plan comes first, what goes to you, how to sort findings and when a pull request is ready. [invariants.md](invariants.md) lists each guardrail and rule, the file that holds it and how it is checked.

The hooks are nets for mistakes, not security boundaries: another command form can get past them.

## Prompt size

Measured 2026-11-27: the words in Mentat's prompt files before the 1.0 rewrite and at this page's base. The files are `rules.md`, every `.md` file under `agents/`, `skills/` and `plugins/*/skills/`, leaving out `CREDITS.md`. In git pathspecs, `*` also matches `/`, so `skills/*.md` takes every subfolder. Run from the root of a clone, for each commit:

```bash
git grep -h -I -e '' <commit> -- rules.md 'agents/*.md' 'skills/*.md' 'plugins/*/skills/*.md' ':(exclude)*CREDITS.md' | wc -w
```

| Commit | What it includes | Files | Words |
| --- | --- | --- | --- |
| `bada73e` | No rewrite stage: the last merge before #531 (#530). | 36 | 40014 |
| `6608a62` | All eight rewrite stages: #531 fingerprint and worktree checks into the `mentat` command; #533 the orchestrator's state store into it; #532 behavior evals; #534 the invariant checklist; #536 outside reviewers behind one adapter, review skill short; #546 `/mentat:plan` and `rules.md` short; #538 implement, backlog, pr and agent prompts short; #540 the orchestrator and Linear modules. Also the other merges from #531 on (#535, #539, #542, #543, #545 and #547 to #553). | 22 | 28235 |

The two file sets differ: the planning skill was renamed to `skills/plan`, several backlog and review files are gone, and the retro skill was removed. Part of the drop is text that moved into the `mentat` command ([decision record 0005](adr/0005-deterministic-checks-live-in-the-mentat-command.md)), and not all of it comes from the rewrite stages.

These counts measure text size, not behavior. They are not the session-start budget `tests/run` checks (`word_budget`), which counts only what every session loads: `rules.md` and the skill and agent descriptions that load.

## Behavior evals

[`evals/baseline.md`](../evals/baseline.md) records commit `18e40dc`: ten cases, two runs, every case 3 of 3 in each, model `claude-opus-5-5`, judge `claude-haiku-5-5`. It keeps no without-plugin numbers, and the cases leave out modules, behavior over several turns and anything that needs a shell ([evals/README.md](../evals/README.md)).
