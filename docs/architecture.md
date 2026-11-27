# Architecture

<!-- loop picture -->

## Parts

- `rules.md`: the core rules, which `hooks/session-start` prints into sessions where Mentat is on.
- `skills/`: one skill per workflow step: `plan`, `backlog`, `build`, `pr` and `review`.
- `agents/`: the implementer (`builder.md`) and the plan checker (`plan-checker.md`).
- `hooks/`: the session-start and merge (`no-merge`) hooks.
- `git-hooks/`: opt-in git hooks for agents' `git` ([setup](setup.md#git-hooks)).
- `bin/mentat` and `lib/`: the `mentat` command, which runs reviews and the checks that always give the same answer.
- `plugins/`: the optional modules: `mentat-reviewers`, `mentat-public-text`, `mentat-linear` and `mentat-lead`.

## The loop

You plan a change with Claude (`/mentat:plan`). A fresh agent checks the plan, unless the request is small and clear, and you agree once; the spec goes on the item. An implementation session gives each item an implementer in its own worktree, opens one pull request per item and, except on a fast track you agreed, runs review rounds: `mentat review` runs fresh-context Claude on each head, up to the round limit; with `mentat-reviewers` on in committed settings, `mentat review --outside` runs every listed, available outside reviewer once a head has nothing left to push. Each finding is fixed or answered. A ready pull request gets a "Ready to merge" line; you merge it. With `mentat-lead`, the orchestrator is the one session you talk to: you plan with it, and, where its host can start and message sessions, it hands agreed items to implementation sessions. It may agree to an item by default when nothing on it is open for you, and records it as agreed by default, not your answer.

## Code and prompts

Code enforces these, among others:

- `hooks/no-merge` denies `gh pr merge`, merges and auto-merge through `gh api`, and MCP merge tools, and denies when it cannot decide.
- The git hooks, where set up, refuse a staged or pushed likely secret and a push updating a non-local remote's default branch.
- The `mentat-public-text` hook denies a listed `gh` or GitHub MCP write holding a private word or home path.
- `mentat review` runs Claude headless in a temporary worktree of the head with read tools only, refuses a round past `MENTAT_REVIEW_ROUNDS`, and before posting waits for any CI on the head and runs a publish check.
- `mentat fingerprint`, `mentat worktree` and `mentat state` compute spec fingerprints, make and check branches and check worktrees, and keep the orchestrator's state; `mentat check` reports the setup.

Prompts carry the workflow: `rules.md`, the skills and agent files tell agents when a plan comes first, what goes to you, how to sort findings and when a pull request is ready. [invariants.md](invariants.md) lists each guardrail and rule, the file holding it and how it is checked.

The hooks are nets for mistakes, not security boundaries: another command form can get past them.

## Prompt size

Measured 2026-11-27: the words in Mentat's prompt files before the 1.0 rewrite and at this page's base. The files: `rules.md`, every `.md` file under `agents/`, `skills/` and `plugins/*/skills/`, except `CREDITS.md`. Run from a clone's root, for each commit:

```bash
git grep -h -I -e '' <commit> -- rules.md 'agents/*.md' 'skills/*.md' 'plugins/*/skills/*.md' ':(exclude)*CREDITS.md' | wc -w
```

| Commit | What it includes | Files | Words |
| --- | --- | --- | --- |
| `bada73e` | No rewrite stage: the last merge before #531 (#530). | 36 | 40014 |
| `6608a62` | All eight rewrite stages: #531 fingerprint and worktree checks into the `mentat` command; #533 the orchestrator's state store into it; #532 behavior evals; #534 the invariant checklist; #536 outside reviewers behind one adapter, review skill short; #546 `/mentat:plan` and `rules.md` short; #538 implement, backlog, pr and agent prompts short; #540 the orchestrator and Linear modules. Also the other merges from #531 on (#535, #539, #542, #543, #545 and #547 to #553). | 22 | 28235 |

The 22 files at `6608a62`, in shell brace form:

```text
rules.md agents/{builder,plan-checker}.md
skills/backlog/{SKILL,github,records}.md skills/build/{SKILL,helpers,redirect}.md
skills/plan/{SKILL,session}.md skills/pr/SKILL.md
skills/review/{SKILL,after-ready,findings,ready-gate,stop}.md
plugins/mentat-lead/skills/{grill/SKILL,orchestrate/SKILL,orchestrate/build-sessions}.md
plugins/mentat-linear/skills/{linear,triage}/SKILL.md
```

`bada73e` has these except `skills/plan/`'s two, plus four in the planning skill's older folder, another backlog file and these 11:

```text
plugins/mentat-lead/skills/retro/SKILL.md
skills/{backlog/{agent-records,assumptions,filing,item-reads,replies,spec-fixes,start-waits,waits},review/{fast-track,review-depth}}.md
```

Replace `-h` with `-l` and drop the final `wc` to list a commit's files.

Part of the drop is text moved into the `mentat` command ([decision record 0005](adr/0005-deterministic-checks-live-in-the-mentat-command.md)), and not all of it comes from the rewrite stages.

These counts measure text size, not behavior. They are not the session-start budget `tests/run` checks (`word_budget`), which counts what loads with every module on: `rules.md` and the skill and agent descriptions that load.

## Behavior evals

[`evals/baseline.md`](../evals/baseline.md) records commit `18e40dc`: ten cases, two runs, every case 3 of 3 in each, model `claude-opus-5-5`, judge `claude-haiku-5-5`. It keeps no without-plugin numbers, and the cases leave out modules, behavior over several turns and anything that needs a shell ([evals/README.md](../evals/README.md)).
