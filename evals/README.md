# Behavior evals

A small suite of behavior tests for Mentat's core rules, run with `claude plugin eval`. It exists so a rewrite of the instruction text can show, stage by stage, that sessions still behave the same way.

## What it covers

Each case directory holds a `prompt.md` (the prompt, after a short frontmatter) and graders in `graders/`. Each case tests one decision point of the core plugin's `rules.md` or a core skill, and its `description:` line names the rule and the kind of incident it comes from. All data in the cases is invented.

Each run is one fresh, single-turn session with only the core plugin loaded, so its session-start hook puts `rules.md` in context. A case that needs a state, such as a build in progress or a pull request after its Ready line, sets it up in its prompt. No case is granted a shell tool; a case that would need one is left out.

It does not cover:

- Module skills. A module run does not load the core rules, and a core run did not load a module when a case named one in its `plugins:` list.
- Behavior over several turns. There is no scripted conversation.
- The maintainer's own instructions. User settings and CLAUDE.md files are not loaded in eval runs.

`tests/run` makes no model calls; it only checks that each case has a prompt and at least one grader.

## Running it

From the repository root, with Claude Code 2.1.326 or later:

```
claude plugin eval . --ablation none --runs 3 --no-publish --trust-plugin --max-cost-usd 15 --model claude-opus-5-5 --judge-model claude-haiku-5-5 --json <file outside the repository>
```

- `--max-cost-usd` is a list-price estimate, checked before each run starts. Runs already in flight can carry the total past it, and it does not limit plan usage.
- A run that hits the cap, times out or errors gives no score for the cases it did not finish.
- Results and reports are never published or committed. `--no-publish` keeps the report local, `--json` writes outside the tree, and `evals/results/` is ignored by git.

## The baseline

`evals/baseline.md` holds the baseline for the suite's four cases, made in this way:

1. One run with the no-plugin arm (`--ablation with-without` in place of `--ablation none`). A case that passes without the plugin is dropped, unless the pull request gives a reason to keep it.
2. Then two runs of the command above on the same commit, Claude Code version, model and judge. A case is steady when its pass count is the same in both runs and at least 2 of 3. Unsteady cases are fixed or dropped before merge.

`baseline.md` holds only the case names and pass counts, the commit, the model, the judge, the Claude Code version, the date, and whether the session-start hook printed a PROBLEM line.

## Keeps the score

For a rewrite stage, compare each steady case at the stage's head with its baseline:

- The case keeps its score when its pass count at the head is not lower than its baseline.
- A case below its baseline gets 3 more runs. With a baseline of 3 of 3, it keeps its score when it passes at least 5 of the 6 runs; with a baseline of 2 of 3, at least 4 of the 6.
- The comparison uses the baseline's Claude Code version, model and judge. When any of them differs, the stage first runs the suite on its base commit in the same sitting and compares against that run instead.
- A stage that renames something a grader names edits that grader in the same pull request, names the edit, and runs the case on the base commit with the old name and on the head with the new one.

This rule is the default. It is confirmed or tightened from the baseline's numbers before the first rewrite stage, and never changed after a stage's result.
