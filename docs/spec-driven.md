# Mentat and spec-driven development

*For people. Agents follow `rules.md` and the skills in `skills/`, not this page.*

This page is for readers who know spec-driven development, as GitHub's [Spec Kit](https://github.github.com/spec-kit/) and AWS's [Kiro](https://kiro.dev/docs/specs/) describe it, and want to see where Mentat's steps fall. It links to the rules and skills instead of restating them.

## Where each phase falls

Spec Kit's phase names are used. Kiro's requirements, design and tasks map onto specify, plan and tasks.

| Phase | Mentat's step |
|---|---|
| Constitution | [`rules.md`](../rules.md) and each repository's AGENTS.md. |
| Specify | The `## Spec` section of the backlog item: one sentence of intent, numbered requirements that can each be checked, and what is out of scope ([`skills/backlog`](../skills/backlog/SKILL.md)). With a GitHub issue as the backlog, the issue carries a `## Spec` section in the same shape; older issues keep their text. |
| Plan | [`mentat:plan`](../skills/plan/SKILL.md) when the approach is uncertain or the decision matters. Otherwise the agreed spec is the plan. |
| Tasks | The builder's brief ([`prompts/builder.md`](../prompts/builder.md)). |
| Implement | The builder subagent, on one branch, running the test command before the pull request. |
| Converge | The pull request's Verification cites each requirement by number, with the check that covers it and what was observed ([`skills/pr`](../skills/pr/SKILL.md)). Codex and Grok then normally review the diff against the spec, and with an external backlog each review records the spec's fingerprint. Last comes the final check, which reads the diff, the description and the spec again ([`skills/review`](../skills/review/SKILL.md)). |

## The two backlog paths

- **External backlog:** the spec is a section of the backlog item. Claude Code passes it to Codex and Grok as a file, a separate input, with `--request`.
- **GitHub issues:** the issue carries a `## Spec` section in the same shape (older issues keep their text), the pull request closes it, and the reviews read it from the issue.

Either way, the pull request's Verification cites each requirement the agreed text states.

## What Mentat adds

- Each head is normally reviewed against the spec by models from other vendors, which did not write the code. Fast tracks, waived pushes and Claude-only mode are the exceptions.
- A merge left to a person. The rules tell the agent not to merge, and a hook asks before the merge commands it recognizes.

## Keeping the spec short and current

There is one spec per pull request, scaled to it: a bug fix is a few lines, and a batch of changes the maintainer agreed to has numbered requirements covering each change. It is fixed once agreed, changes only when the scope does, and with an external backlog every review fingerprints the text it judged, so a review of an older spec shows up as one. On the GitHub-issues path the reviews read the issue itself and no fingerprint is recorded.
