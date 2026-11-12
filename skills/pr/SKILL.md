---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
user-invocable: false
---

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`. With an external backlog there is no issue: read the spec from the backlog through `mentat:backlog` (its `## Spec` section, or `## Agreed request` on an older item), write no `Closes #`, and never name the backlog's workspace or item in the body.
   An issue agreed under this workflow carries a `## Spec` section in the shape `mentat:backlog` gives (one sentence of intent; numbered requirements, each checkable, and one the maintainer checks by hand says so; "Out of scope:"), written by Claude Code when the maintainer agrees and scaled to the change. Read it from the issue.
2. Use the repository's pull request template if it has one: fill its summary section with the Summary and its test section with the Test plan and any See it line, add the Status line, Risks and Review details only where it has no place for them, and add `Closes #` as below where it has no place for it. Otherwise use the template below. Where the repository has a `GLOSSARY.md`, use its terms. Titles follow Conventional Commits.
3. The Summary's opening sentence (in a repository's template, the opening sentence of its summary section) says what changes for the maintainer, in plain words, in about 25 words at most, with no file path, command or flag. It is the intent sentence Codex and Grok (or Claude, with Codex off) compare their own against. A second sentence gives the reason only when it is not obvious, and nothing else. If you cannot state the change in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit. After every push, rewrite the Status line, the Test plan and the head and rounds in Review details for the new head commit; when the push changes what the diff does, update the rest of the body too.
5. Rewrite the Status line, Risks, the Test plan's results and the `Head:` line's round in place whenever the body is updated and whenever the review loop stops (`mentat:review`, `mentat:claude-review`), so they say where things stand now. A wait on the maintainer goes first in the body, above `## Summary`, as `mentat:backlog` "Waits on the maintainer" says: when the wait is on a backlog item (external or a GitHub issue), only its one line saying the steps are on the backlog item; with no backlog item, the wait itself.

```markdown
<A wait on the maintainer, when one exists (step 5).>

## Summary

<What changes for the maintainer, in one plain sentence of about 25 words, with no file path, command or flag. A second sentence only when the reason is not obvious.>

**Status:** <Ready | In review | Blocked: <why> | Not reviewed: <why>>

## Risks

- <One line per item to read before merging.>

## Test plan

- <Each check run on the head commit and its result, the test command and CI included.>
- <Anything not checked, and why.>

**See it:** <only when there is something to try: a command, a URL or a repository-relative path; never a local machine path>

Closes #<issue, when there is one; none with an external backlog>

<details>
<summary>Review details</summary>

Why: <where the work came from, or "not recorded">

Head: <commit>, round <n> of <limit>

<One line per finding fixed or answered: reviewer, round, the finding, and its fix commit or its reason.>
<Extra rounds the maintainer allowed; each completed hand check, who checked and what they saw; a review stop's line.>

| Requirement | Check | Observed |
|---|---|---|
| <number> | <the check that covers it> | <what was observed; a hand check says who checked and what they saw> |

Built with: session <model>, effort <effort> (read at each builder run); builder <model>, effort <effort> (configured).

</details>
```

The Status line holds only the state: `Ready`, `In review`, `Blocked: <why>` or `Not reviewed: <why>`.

Risks has one line per item the maintainer must read before merging, in plain words, each naming its item: a revert that does not fully undo the change (what stays and why, such as deleted data, a release, a migration or an interface others use); what breaks, for whom; a changed hook, CI workflow or agent instruction file whose behavior changes, named with the reason it deserves a look; anything in the diff beyond the request; a call made without the maintainer; a finding left unfixed, or a P0 or P1 finding answered instead of fixed; a review that did not cover the head or the current agreed request, or a reviewer that was incomplete (a fast track, a waived push, a head not reviewed, Codex off, a Grok limitation kept, a Grok review on an older spec, or a Grok stop review on an older head or spec); and a hand check still open. With no such hook, workflow or instruction file changed, nothing is written about it. Leave out a revert that fully undoes the change. With no such item, leave the section out.

The Test plan gives each check run on the head commit and its result, the test command and CI included, and anything not checked, and why. When `rules.md` step 3 left the test run to CI, it reports the builder's run.

The `Why:` line says in plain, public-safe words where the work came from, such as asked by the maintainer in chat, from a backlog item the maintainer wrote, found by an agent while building, a subtask of a request named in public words, or proposed by an agent and agreed, with a date only when a record has one. Take it from the backlog item's opening sentence or the issue, never a guess, and never name the backlog's workspace or item (step 1); with no record it reads `Why: not recorded.` It is not the intent.

The `Head:` line gives the head commit and `round <n> of <limit>`, the review rounds completed so far: the `codex rounds` count from `mentat status <N>` against a limit of five plus any extra rounds a Review details line records the maintainer allowing, or, on the Claude-only path (`mentat:claude-review`), the `claude rounds` count against two. Grok's review is not a round. With no completed round, or on a fast track, the round part is left out.

The requirement table has one row per numbered requirement of the spec, by number (an older issue or item, agreed before the section had that name and with no numbered list, is read as each requirement it states); one check may cover several.

The `Built with:` line says which models built the pull request. The session values are the model and effort setting the build session read for itself at or right after each builder run, one entry per run when they changed; earlier entries stay as written. The builder values are what its definition sets, labeled as configured; a definition that sets no effort says `effort not set`. A value not read is `unknown`; nothing is inferred, from a model-family alias or from memory.
