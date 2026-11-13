---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
user-invocable: false
---

1. Read the diff and the linked issue, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`; the issue with `gh issue view <issue>`. With an external backlog there is no issue: read the spec from the backlog through `mentat:backlog` (its `## Spec` section, or `## Agreed request` on an older item), write no `Closes #`, and never name the backlog's workspace or item in the body.
   An issue agreed under this workflow carries a `## Spec` section in the shape `mentat:backlog` gives (one sentence of intent; numbered requirements, each checkable, and one the maintainer checks by hand says so; "Out of scope:"), written by Claude Code when the maintainer agrees and scaled to the change. Read it from the issue.
2. Use the repository's pull request template if it has one: fill its summary section with the Summary and its test section with the Test plan and any See it line, put the Status line on the first line of the body, moved from any place the template gives it, with any wait right below it, add Decisions, Risks and Review details only where it has no place for them, and add `Closes #` as below where it has no place for it. Otherwise use the template below. Where the repository has a `GLOSSARY.md`, use its terms. Titles follow Conventional Commits.
3. The Summary's opening sentence (in a repository's template, the opening sentence of its summary section) says what changes for the maintainer, in plain words, in about 25 words at most, with no file path, command or flag. It is the intent sentence Codex and Grok (or Claude, with Codex off) compare their own against. The second sentence says why the change is needed, in plain words: the problem it fixes for the maintainer, with no file path, command or flag, and nothing else. If you cannot state the change in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit; in a Decisions line, the chosen behavior matches the diff and an "agreed" mark matches the spec. After every push, rewrite the Status line, the Test plan and the `Head:` line in Review details for the new head commit; when the push changes what the diff does, update the rest of the body too.
5. Rewrite the Status line, Risks and the Test plan's results in place whenever the body is updated and whenever the review loop stops (`mentat:review`, `mentat:claude-review`), so they say where things stand now. A wait on the maintainer goes right below the Status line, as `mentat:backlog` "Waits on the maintainer" says: when the wait is on a backlog item (external or a GitHub issue), only its one line saying the steps are on the backlog item; with no backlog item, the wait itself.

```markdown
**Status:** <Ready | In review | Blocked: <why> | Not reviewed: <why>>

<A wait on the maintainer, when one exists (step 5).>

## Summary

<What changes for the maintainer, in one plain sentence of about 25 words, with no file path, command or flag. Then one plain sentence on why the change is needed: the problem it fixes for the maintainer.>

## Decisions

- <The choice, in about 12 words> (agreed | made in the build)

## Risks

- <One line of about 12 words per item to read before merging.>

## Test plan

- <Each check run on the head commit and its result, the test command and CI included.>
- <Anything not checked, and why.>

**See it:** <only when there is something to try: a command, a URL or a repository-relative path; never a local machine path>

Closes #<issue, when there is one; none with an external backlog>

<details>
<summary>Review details</summary>

Head: <commit>

<One line per finding fixed or answered: reviewer, round, the finding, and its fix commit or its reason.>
<Extra rounds the maintainer allowed; each completed hand check, who checked and what they saw; a review stop's line.>

| Requirement | Check | Observed |
|---|---|---|
| <number> | <the check that covers it> | <what was observed; a check that failed before the fix and passed after is the builder's report and gives both; a hand check says who checked and what they saw> |

Built with: session <model>, effort <effort> (read at each builder run); builder <model>, effort <effort> (configured).

</details>
```

The Status line holds only the state: `Ready`, `In review`, `Blocked: <why>` or `Not reviewed: <why>`.

Decisions has one line of about 12 words at most per key design choice, a choice where a plausible alternative would change behavior, data, an interface, cost or risk: the decision at a high level, with no reasons, marked "agreed" when the agreed spec fixes it, else "made in the build". Five lines is a length target only; no key choice is dropped to meet it. The detail behind a line (options weighed, reasons) stays in the builder's report and the item's records, given when the maintainer asks. With no key choice, leave the section out. A "made in the build" mark never replaces asking the maintainer about outcome, scope, cost or risk (`rules.md`).

Risks has one line per item the maintainer must read before merging, aiming at about 12 words without dropping what this rule or a review skill has it name, in plain words, each naming its item: a revert that does not fully undo the change (what stays and why, such as deleted data, a release, a migration or an interface others use); what breaks, for whom; a changed hook, CI workflow or agent instruction file whose behavior changes, named with the reason it deserves a look; anything in the diff beyond the request; a call made without the maintainer that is not a key design choice (a key one goes once, in Decisions); a finding left unfixed, or a P0 or P1 finding answered instead of fixed; a review that did not cover the head or the current agreed request, or a reviewer that was incomplete (a fast track, a waived push, a head not reviewed, Codex off, a Grok limitation kept, a Grok review on an older spec, or a Grok stop review on an older head or spec); and a hand check still open. A decision's safety effect, or another consequence listed above, still gets its own line. With no such hook, workflow or instruction file changed, nothing is written about it. Leave out a revert that fully undoes the change. With no such item, leave the section out.

The Test plan gives each check run on the head commit and its result, the test command and CI included, and anything not checked, and why. When `rules.md` step 3 left the test run to CI, it reports the builder's run.

The requirement table has one row per numbered requirement of the spec, by number (an older issue or item, agreed before the section had that name and with no numbered list, is read as each requirement it states); one check may cover several.

The `Built with:` line says which models built the pull request. The session values are the model and effort setting the build session read for itself at or right after each builder run, one entry per run when they changed; earlier entries stay as written. The builder values are what its definition sets, labeled as configured; a definition that sets no effort says `effort not set`. A value not read is `unknown`; nothing is inferred, from a model-family alias or from memory.
