---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
user-invocable: false
---

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`. With an external backlog there is no issue: read the spec from the backlog through `mentat:backlog` (its `## Spec` section, or `## Agreed request` on an older item), write no `Closes #`, and never name the backlog's workspace or item in the body.
   An issue agreed under this workflow carries a `## Spec` section in the shape `mentat:backlog` gives (one sentence of intent; numbered requirements, each checkable, and one the maintainer checks by hand says so; "Out of scope:"), written by Claude Code when the maintainer agrees and scaled to the change. Read it from the issue.
2. Use the repository's pull request template if it has one, adding any part below that it lacks; otherwise the template below. Where the repository has a `GLOSSARY.md`, use its terms. Titles follow Conventional Commits.
3. The note's first sentence says what changes for the maintainer, in plain words, in about 25 words at most, with no file path, command or flag. It is the intent sentence Codex and Grok (or Claude, with Codex off) compare their own against. If you cannot state it in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit. After every push, rewrite the status line for the new head commit; when the push changes what the diff does, update the rest of the body too.
5. Rewrite the status line and the note in place whenever the body is updated and whenever the review loop stops (`mentat:review`, `mentat:claude-review`), so they say where things stand now. A wait on the maintainer goes first in the body, above `## Summary`, as `mentat:backlog` "Waits on the maintainer" says: when the wait is on a backlog item (external or a GitHub issue), only its one line saying the steps are on the backlog item; with no backlog item, the wait itself.

```markdown
## Summary

**<State>.** <head commit>, <rounds, when any>, <findings settled, when any>, tests <pass or fail>, CI <passed, failed, not finished or none>.

Why: <where the work came from, or "not recorded">

> [!<TYPE>]
> <Sentence 1: what changes for the maintainer, in plain words, at most about 25 words, not a list of edits.> <Sentence 2, only when something must be read before merging.>

<details>
<summary>Verification</summary>

| Requirement | Check | Observed |
|---|---|---|
| <number> | <the check that covers it> | <what was observed; a check that failed before the fix and passed after is the builder's report and gives both; a hand check says who checked and what they saw> |

<The test command and its result on the head commit. Any check missing or not run, and why. For a bug fix, the builder's cause, or that it is unknown. One line for each item to read before merging that the note's second sentence does not carry. The builder's material assumptions.>

**See it:** <how the maintainer can see the change: a command to run, a URL, or a repository-relative path; never a local machine path>

</details>

Closes #<issue, when there is one; none with an external backlog>
```

The `Why:` line says in plain, public-safe words where the work came from, such as asked by the maintainer in chat, from a backlog item the maintainer wrote, found by an agent while building, a subtask of a request named in public words, or proposed by an agent and agreed, with a date only when a record has one. Take it from the backlog item's opening sentence or the issue, never a guess, and never name the backlog's workspace or item (step 1); with no record it reads `Why: not recorded.` It is not the intent.

The note in the alert has at most two sentences, in plain words, with no headings, labels or bullets. The first says what changes, with no file path, command or flag (step 3). A second appears only when something must be read before merging, and carries the single sharpest item, in this order: a revert that does not fully undo the change (what stays and why, such as deleted data, a release, a migration or an interface others use) or a real blast radius (what breaks, for whom); a changed hook, CI workflow or agent instruction file whose behavior changes, named with the reason it deserves a look; anything in the diff beyond the request; a call made without the maintainer; a finding left unfixed, or a review that did not cover the change (a fast track, a waived push, a head not reviewed, Codex off, or a Grok limitation kept). Other such items go as lines in Verification. With no such hook, workflow or instruction file changed, nothing is written about it. Leave out a revert that fully undoes the change. Use the GitHub alert type that fits the note. The body has no other alert.

The Verification table has one row per numbered requirement of the spec, by number (an older issue or item, agreed before the section had that name and with no numbered list, is read as each requirement it states); one check may cover several.

The state is one of `Ready`, `In review`, `Blocked: <why>` or `Not reviewed: <why>`. The rounds clause, `round <n> of <limit>`, gives the review rounds completed so far: the `codex rounds` count from `mentat status <N>` against a limit of five plus any extra rounds a Verification line records the maintainer allowing, or, on the Claude-only path (`mentat:claude-review`), the `claude rounds` count against two. Grok's review is not a round. With no completed round, or on a fast track, the clause is left out. The findings clause, `<n> findings fixed, <n> answered`, counts the Verification's one line per finding fixed or answered; a count of zero is left out, and the clause too when both are. When `rules.md` step 3 left the test run to CI, `tests` reports the builder's run. For example, `**In review.** 75b1127, round 2 of 5, 3 findings fixed, 1 answered, tests pass, CI not finished.` while the review runs, and `**Ready.** f155cd4, round 1 of 5, tests pass, CI passed.` at the final check.
