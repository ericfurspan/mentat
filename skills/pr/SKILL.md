---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
---

The body has two readers: the maintainer, who wants what changed, where to look and the risk; and Codex and Grok, which review the diff against it and its record of what was checked. The status line and the alert under it are the maintainer's part. Keep it short.

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`. With an external backlog (`rules.md` Records) there is no issue: read the spec from the backlog through `mentat:backlog` (its `## Spec` section, or `## Agreed request` on an older item), write no `Closes #`, and never name the backlog's workspace or item in the body.
   An issue agreed under this workflow carries a `## Spec` section in the shape `mentat:backlog` gives (one sentence of intent; numbered requirements, each checkable, and one checked by hand says so; "Out of scope:"), written by Claude Code when the maintainer agrees and scaled to the change. Read it from the issue.
2. Use the repository's pull request template if it has one, adding any part below that it lacks; otherwise the template below. Where the repository has a `GLOSSARY.md`, use its terms.
3. The note's first sentence states the change's intent, the sentence Codex and Grok (or Claude, with Codex off) compare their own against. If you cannot state it in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit. After every push, rewrite the status line for the new head commit and keep the "Look here first" lines matching it; when the push changes what the diff does, update the rest of the body too.
5. Rewrite the status line and the note in place whenever the body is updated and whenever the review loop stops (`mentat:review`, `mentat:claude-review`), so they say where things stand now. A wait on the maintainer written on the pull request (`rules.md`, "What goes to the maintainer") goes above the status line.

```markdown
**<State>.** <head commit>, tests <pass or fail>, CI <passed, failed, not finished or none>.

> [!NOTE]
> <A note to the maintainer, about a hundred words at most, in plain words, with no headings, labels or bullets. First sentence: what the change is for, its intent and not a list of edits. Then only what applies: why the change is made (for a bug fix, the builder's cause, or that it is unknown); whether a revert undoes it, and if not, what stays and why, such as deleted data, a release, a message sent, settings elsewhere, or an interface others use; when there is a real blast radius, what breaks, and for whom, if this is wrong; anything Codex, Grok or Claude flagged that stayed unfixed, and any call made without the maintainer. A small change gets two or three sentences.>
>
> Look here first: `<path>:<a>-<b>`, <up to two more>

## Not in scope

<What this leaves alone that looks related, and anything in the diff beyond the request.>

<details>
<summary>Checks</summary>

| Requirement | Check | Observed |
|---|---|---|
| <number> | <the check that covers it> | <what was observed; a check that failed before the fix and passed after gives both; a hand check says who checked and what they saw> |

<The test command and its result on the head commit. Any check missing or not run, and why. The builder's material assumptions.>

**See it:** <how the maintainer can see the change: a command to run, a URL, or a repository-relative path; never a local machine path>

</details>

Closes #<issue, when there is one; none with an external backlog>
```

"Look here first" gives one to three repository-relative paths with the lines that carry the change, as plain code text with no link or URL, so they read the same on the GitHub site and app. The body has no other alert.

The Checks table has one row per numbered requirement of the spec, by number (an older issue or item, agreed before the section had that name and with no numbered list, is read as each requirement it states); one check may cover several.

The state is one of `Ready`, `In review`, `Blocked: <why>`, `Not reviewed: <why>` or `Stopped after five rounds`, and the line has no round number. For example, `**In review.** 75b1127, tests pass, CI not finished.` while the review runs, and `**Ready.** f155cd4, tests pass, CI passed.` at the final check.
