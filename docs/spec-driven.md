# Mentat and spec-driven development

*For people. Agents follow `rules.md` and the skills in `skills/`, not this page.*

This page is for readers who know spec-driven development, as GitHub's [Spec Kit](https://github.github.com/spec-kit/) and AWS's [Kiro](https://kiro.dev/docs/specs/) describe it, and want to see where Mentat's steps fall. It links to the rules and skills instead of restating them.

## Where each phase falls

Spec Kit's phase names are used. Kiro's requirements, design and tasks map onto specify, plan and tasks.

| Phase | Mentat's step |
|---|---|
| Constitution | [`rules.md`](../rules.md) and each repository's AGENTS.md. |
| Specify | The `## Spec` section of the backlog item: one sentence of intent, numbered requirements that can each be checked, and what is out of scope ([`skills/backlog`](../skills/backlog/SKILL.md)). With a GitHub issue as the backlog, the agreed text on the issue plays that part. |
| Plan | [`mentat:plan`](../skills/plan/SKILL.md) when the approach is uncertain or the decision matters. Otherwise the agreed spec is the plan. |
| Tasks | The builder's brief ([`prompts/builder.md`](../prompts/builder.md)). |
| Implement | The builder subagent, on one branch, running the test command before the pull request. |
| Converge | The pull request's Evidence cites each requirement by number, with the check that covers it and what was observed ([`skills/pr`](../skills/pr/SKILL.md)). Codex and Grok then review the diff against the spec, and each review records the spec's fingerprint. Last comes the final check ([`skills/review`](../skills/review/SKILL.md)). |

## The two backlog paths

- **External backlog:** the spec is a section of the backlog item. Reviews are local, and Claude Code passes the spec to Codex and Grok as a separate input with `--request`.
- **GitHub issues:** the issue holds the agreed text, the pull request closes it, and the reviews read it from the issue.

Either way, the pull request's Evidence cites each requirement the agreed text states.

## What Mentat adds

- Each head is reviewed against the spec by models from other vendors, which did not write the code.
- A merge only a person makes. The agent never merges.

## Keeping the spec short and current

There is one spec per change, scaled to it: a bug fix is a few lines. It is fixed once agreed, changes only when the scope does, and every review fingerprints the text it judged, so a review of an older spec shows up as one.
