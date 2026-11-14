# Material assumptions

With either tracker, read this before posting or reading an item's assumptions comment, and again after a compaction.

A material assumption is an unchecked fact a plan relies on that would change the design or the checks if false (`mentat:propose` step 5). Assumptions never go in the `## Spec` section; the spec's shape, its limits and the review criteria are unchanged by them.

## The comment

At agreement (`mentat:propose` step 7), the material assumptions still standing are posted on the item as one comment in this shape, with none posted when none stand:

```
Material assumptions:
- <assumption>; state: <unchecked|holds|false>; evidence: <one line>
```

Evidence is in public-safe words (`records.md`). When a state changes, including from a builder's report, the main session posts the whole list again in that shape before the next brief. The latest such comment stands.

A builder's brief for an item carries its latest assumptions comment as given, when one exists, read right before the brief. The comment alone never holds an item out of a build queue.

## What reaches the maintainer

The comment is the agents' record; nothing the maintainer must see is only there. The standing assumptions reach them in `mentat:propose`'s agreement question. A disproof that changes scope, cost or risk, or would change a numbered requirement, reaches them in chat as the existing scope question and, until answered, is recorded on the item as a decision for the maintainer that blocks its work (`../build/SKILL.md` step 3). An agreed change rewrites the spec and records its fingerprint ("Agreement" in `SKILL.md`). Any other disproof changes only how the build meets and tests the existing requirements.

## Moving GitHub issues to Linear

When a repository's GitHub issues move to a Linear project, an issue's latest assumptions comment is copied to the new item, the one exception to issue comments staying on the issue.
