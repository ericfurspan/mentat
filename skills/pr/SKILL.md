---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
---

The body has two readers: the maintainer, who wants what changed, the proof and the risk; and Codex, which reviews the diff against it. Keep it short.

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`.
2. Use the repository's pull request template if it has one, adding any part below that it lacks; otherwise the template below. Where the repository has a `GLOSSARY.md`, use its terms.
3. If you cannot state the change's intent in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit. After any push that changes what the diff does, update the body.

```markdown
## Summary

<One sentence: what the change is for, its intent and not a list of edits.>

<What was asked and what this changes, in a sentence or two. A table only where it says it faster.>

## Evidence

**Before:** <the failing check, the old output, or the old line>
**After:** <the passing check, the new output, or the new line>

<The test command and its result on the head commit. Say so when a check is missing or could not run. Put the builder's material assumptions here or under Merge danger.>

## Merge danger

**Door:** <two-way: a revert undoes it. One-way: it leaves something a revert does not undo, such as deleted data, a release, a message sent, settings elsewhere, or an interface others use.>
**Blast radius:** <what breaks, and for whom, if this is wrong>

## Not in scope

<What this leaves alone that looks related, and anything in the diff beyond the request.>

Closes #<issue, when there is one>
```
