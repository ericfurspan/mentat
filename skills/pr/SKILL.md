---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
---

The body has two readers: the maintainer, who reads the top first (the state, where the work came from and what the change does); and Codex and Grok, which review the diff against it and its record of what was checked. The status line, the `Why:` line and the note in the alert are the maintainer's part. Keep it short.

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`. With an external backlog (`rules.md` Records) there is no issue: read the spec from the backlog through `mentat:backlog` (its `## Spec` section, or `## Agreed request` on an older item), write no `Closes #`, and never name the backlog's workspace or item in the body.
   An issue agreed under this workflow carries a `## Spec` section in the shape `mentat:backlog` gives (one sentence of intent; numbered requirements, each checkable, and one checked by hand says so; "Out of scope:"), written by Claude Code when the maintainer agrees and scaled to the change. Read it from the issue.
2. Use the repository's pull request template if it has one, adding any part below that it lacks; otherwise the template below. Where the repository has a `GLOSSARY.md`, use its terms.
3. The note's first sentence states the change's intent for the maintainer, the sentence Codex and Grok (or Claude, with Codex off) compare their own against. If you cannot state it in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit. After every push, rewrite the status line for the new head commit; when the push changes what the diff does, update the rest of the body too.
5. Rewrite the status line and the note in place whenever the body is updated and whenever the review loop stops (`mentat:review`, `mentat:claude-review`), so they say where things stand now. A wait on the maintainer written on the pull request (`rules.md`, "What goes to the maintainer") goes above the status line.

```markdown
**<State>.** <head commit>, tests <pass or fail>, CI <passed, failed, not finished or none>.

Why: <where the work came from, or "not recorded">

> [!<TYPE>]
> <Sentence 1: what the change does for the maintainer, its intent, not a list of edits.> <Sentence 2, only when something must be read before merging.>

<details>
<summary>Checks</summary>

| Requirement | Check | Observed |
|---|---|---|
| <number> | <the check that covers it> | <what was observed; a check that failed before the fix and passed after gives both; a hand check says who checked and what they saw> |

<The test command and its result on the head commit. Any check missing or not run, and why. For a bug fix, the builder's cause, or that it is unknown. One line for each item to read before merging that the note's second sentence does not carry. The builder's material assumptions.>

**See it:** <how the maintainer can see the change: a command to run, a URL, or a repository-relative path; never a local machine path>

</details>

Closes #<issue, when there is one; none with an external backlog>
```

The `Why:` line says in plain, public-safe words where the work came from, such as asked by the maintainer in chat, from a backlog item the maintainer wrote, found by an agent while building, a subtask of a request named in public words, or proposed by an agent and agreed, with a date only when a record has one. Take it from the backlog item's opening sentence or the issue, never a guess, and never name the backlog's workspace or item (step 1); with no record it reads `Why: not recorded.` It is not the intent.

The note in the alert has at most two sentences, in plain words, with no headings, labels or bullets. The first is the intent (step 3). A second appears only when something must be read before merging, and carries the single sharpest item, in this order: a revert that does not fully undo the change (what stays and why, such as deleted data, a release, a migration or an interface others use) or a real blast radius (what breaks, for whom); anything in the diff beyond the request; a call made without the maintainer; a finding left unfixed, or a review that did not cover the change (a fast track, a waived push, a head not reviewed, Codex off, or a Grok limitation kept). Other such items go as lines in Checks. Leave out a revert that fully undoes the change. The body has no other alert.

The alert's type is the most serious that applies to the second sentence alone: `[!CAUTION]` when that sentence is a risky or irreversible step after the merge (a release, deleted data, a migration); `[!WARNING]` when it is a revert that does not fully undo the change or a real blast radius; `[!IMPORTANT]` for any other second sentence; `[!NOTE]` when there is none. Never `[!TIP]`.

The Checks table has one row per numbered requirement of the spec, by number (an older issue or item, agreed before the section had that name and with no numbered list, is read as each requirement it states); one check may cover several.

The state is one of `Ready`, `In review`, `Blocked: <why>`, `Not reviewed: <why>` or `Stopped after five rounds`, and the line has no round number. For example, `**In review.** 75b1127, tests pass, CI not finished.` while the review runs, and `**Ready.** f155cd4, tests pass, CI passed.` at the final check.
