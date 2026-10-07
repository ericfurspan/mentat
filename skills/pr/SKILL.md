---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
---

The pull request body has two readers. The maintainer reads it to see what changed, how it was proven and how risky the merge is. Codex reads it as the requirements to review the diff against. Write it so both get that from the top of the page.

## Steps

1. Read the diff and the linked issue, not from memory: before the pull request exists, the branch against its base on the GitHub remote (`git diff <remote>/<base>...HEAD`, after fetching it); after, `gh pr diff <pr>`. The issue is `gh issue view <issue>`, a different number from the pull request.
2. Pick the shape. If the repository has a pull request template, fill its sections and fold each part below into the nearest one, adding any part it has no place for. Otherwise use the template below.
3. Where the repository has a `GLOSSARY.md`, use its terms.
4. Write each section. Done when every claim matches the diff on the head commit and Evidence names the head commit's test result.
5. After any push that changes what the diff does, update the body the same way.

## Template

```markdown
## Summary

<One or two sentences: what was asked, and what this changes.>

<Optional: one small visual with a one-line lead-in saying what it shows, next to the sentence it supports.>

## Evidence

**Before:** <failing check, old output, or screenshot>
**After:** <passing check, new output, or screenshot>

<Test command and its result on the head commit.>

## Merge danger

**Door:** <one-way or two-way>. <Why, when it is not obvious.>
**Blast radius:** <what breaks, and for whom, if this is wrong>

## Not in scope

<What this leaves alone that looks related. Anything in the diff beyond the request, named.>

Closes #<issue, when there is one>
```

## Sections

### Summary

Plain prose first: what was asked and what the change does, in the words a reviewer would check the diff against. For whether to add a visual, which kind, and where, read [visuals.md](visuals.md).

### Evidence

Show a before and after.

- A visual change: screenshots, when the environment can take them.
- A behavior change: the check that failed before and passes now, named or sketched as pseudocode, or the output that changed.
- A change to instructions or docs: the key line before and after.

Then the test command and its result on the head commit. When there is no test command, or a check is missing or could not run, say so here.

### Merge danger

A **two-way door** is undone by reverting the pull request. A **one-way door** leaves something a revert does not undo: data deleted or migrated, a release published, a message sent, settings changed on another system, a format or interface others already depend on.

The **blast radius** names who or what is affected if the change is wrong, concretely: one script, CI only, every session in every repository that installs this.

### Not in scope

Name what was left alone on purpose, so the reviewer does not flag its absence, and anything the diff adds beyond the request, so the maintainer sees it.
