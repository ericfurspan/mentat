---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
---

The body has two readers: the maintainer, who wants what changed, the proof and the risk; and Codex and Grok, which review the diff against it. The status line and the note at the top are the maintainer's part. Keep it short.

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`. With an external backlog (`rules.md` Records) there is no issue: read the spec from the backlog through `mentat:backlog` (its `## Spec` section, or `## Agreed request` on an older item), write no `Closes #`, and never name the backlog's workspace or item in the body.
   An issue agreed under this workflow carries a `## Spec` section in the shape `mentat:backlog` gives (one sentence of intent; numbered requirements, each checkable, and one checked by hand says so; "Out of scope:"), written by Claude Code when the maintainer agrees and scaled to the change. Read it from the issue.
2. Use the repository's pull request template if it has one, adding any part below that it lacks; otherwise the template below. Where the repository has a `GLOSSARY.md`, use its terms.
3. The note's first sentence states the change's intent, the sentence Codex and Grok (or Claude, with Codex off) compare their own against. If you cannot state it in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit. After any push that changes what the diff does, update the body.
5. Rewrite the status line and the note in place whenever the body is updated and whenever the review loop stops (`mentat:review`, `mentat:claude-review`), so they say where things stand now. A wait on the maintainer written on the pull request (`rules.md`, "What goes to the maintainer") goes above the status line.

```markdown
**<State>.** <head commit>, tests <pass or fail>, CI <passed, failed, not finished or none>.

<A note to the maintainer, about a hundred words at most, in plain words, with no headings, labels or bullets. First sentence: what the change is for, its intent and not a list of edits. Then only what applies: why the change is made (for a bug fix, the builder's cause, or that it is unknown); whether a revert undoes it, and if not, what stays and why; anything Codex, Grok or Claude flagged that stayed unfixed, and any call made without the maintainer; where in the diff to look first. A small change gets two or three sentences.>

---

## Evidence

**Before:** <the failing check, the old output, or the old line>
**After:** <the passing check, the new output, or the new line>
**See it:** <how the maintainer can see the change: a command to run, a URL, or a repository-relative path; never a local machine path>

<For each numbered requirement of the spec, by number (an older issue or item, agreed before the section had that name and with no numbered list, is read as each requirement it states): the check that covers it and what was observed. One check may cover several. A hand check says who checked and what they saw.>

<The test command and its result on the head commit. Say so when a check is missing or could not run. Put the builder's material assumptions here or under Merge danger.>

## Merge danger

**Revert:** <a revert undoes it; or: a revert does not undo <what>, because <why>, such as deleted data, a release, a message sent, settings elsewhere, or an interface others use.>
**Blast radius:** <what breaks, and for whom, if this is wrong>

## Not in scope

<What this leaves alone that looks related, and anything in the diff beyond the request.>

Closes #<issue, when there is one; none with an external backlog>
```

The state is one of `Ready`, `In review`, `Blocked: <why>`, `Not reviewed: <why>` or `Stopped after five rounds`, and the line has no round number. For example, `**In review.** 75b1127, tests pass, CI not finished.` while the review runs, and `**Ready.** f155cd4, tests pass, CI passed.` at the final check.
