---
name: pr
description: "Writing a pull request body. Use when opening a pull request, or when its diff changes and the description needs updating."
user-invocable: false
---

1. Read the diff and the spec, not from memory: before the pull request exists, `git diff <remote>/<base>...HEAD` after fetching; after, `gh pr diff <pr>`. Read the spec where `mentat:backlog` "Where the spec lives" says (with GitHub issues, `gh issue view <issue>`). With an external backlog, never name the backlog's workspace or item in the body.
2. Use the repository's pull request template if it has one: its summary section takes the Summary, its test section the Test plan and any See it line; the Status line goes first in the body, moved from wherever the template puts it, with any wait right below it; Decisions and Risks always goes under its own `## Decisions and Risks` heading, whatever risk or decision section the template has, since `mentat status` reads that heading; add Review details and `Closes #` (or `Refs #`) only where it has no place for them. Otherwise use the template below. Where the repository has a `GLOSSARY.md`, use its terms. Titles follow Conventional Commits; the title and body follow `records.md` in `mentat:backlog`'s folder. Open a normal pull request by default. Pass the body to `gh pr create` and `gh pr edit` with `--body-file`, naming a file written in an earlier call.
3. The Summary's opening sentence says what changes for the maintainer, in plain words, in about 25 words at most, with no file path, command or flag: the intent sentence the reviewers compare their own against. The second says why, the problem it fixes for the maintainer, in the same plain words. If you cannot state the change in one sentence, ask the maintainer before opening the pull request.
4. Every claim matches the diff on the head commit; a decision line's choice matches the diff, and an "agreed" or "agreed by default" mark matches the spec or the maintainer's decisions line it rests on. After every push, rewrite the Status line, the Test plan and the `Head:` line for the new head; when the push changes what the diff does, update the rest too.
5. Rewrite the Status line, Decisions and Risks and the Test plan's results in place whenever the body is updated and whenever the review loop stops (`mentat:review`), so they say where things stand now. A wait on the maintainer goes right below the Status line, as `mentat:backlog` "Waits on the maintainer" says: with a backlog item, only its one line saying the steps are on the item; with none, the wait itself.

```markdown
**Status:** <Ready | In review | Blocked: <why> | Not reviewed: <why>>

<A wait on the maintainer, when one exists (step 5).>

## Summary

<What changes for the maintainer, in one plain sentence of about 25 words, with no file path, command or flag. Then one plain sentence on why the change is needed.>

## Decisions and Risks

- Decision: <the choice, in about 12 words> (agreed | agreed by default | made without the maintainer)
- Risk: <one line of about 12 words per item to read before merging>

## Test plan

- <Each check run on the head commit and its result, the test command and CI included.>
- <Anything not checked, and why.>

**See it:** <only when there is something to try: a command, a URL or a repository-relative path; never a local machine path>

Closes #<issue, with GitHub issues; Refs # in its place when the spec marks a manual check as after the merge; none with an external backlog>

<details>
<summary>Review details</summary>

Head: <commit>

<One line per finding fixed or answered: reviewer, round, the finding, and its fix commit or its reason, such as settled by the maintainer.>
<A higher round limit, the maintainer's or the session's own (`../review/stop.md` "Round limit"); each completed manual check, who ran it and what was seen; the line of each review stop that asks the maintainer and each round limit question, kept from when it asks and `pending` until answered (`../review/stop.md` "Durable pause").>

| Requirement | Check | Observed |
|---|---|---|
| <number> | <the check that covers it> | <what was observed; a check that failed before the fix and passed after gives both, from the implementer's report; a manual check says who ran it and what was seen> |

</details>
```

The Status line holds only the state: `Ready`, `In review`, `Blocked: <why>` or `Not reviewed: <why>`.

## Writing Decisions and Risks

The section is on every pull request, saying none when empty: `mentat status` reads its heading as the calls section, and `mentat:review` holds Ready without it.

A decision line, of about 12 words at most, names one key design choice, where a plausible alternative would change behavior, data, an interface, cost or risk, at a high level and with no reasons. It is marked "agreed" when the agreed spec, or a decisions line on the item recording the maintainer's own answer (`../backlog/records.md` "Decision lines"), fixes it, "agreed by default" when the item's agent records hold the default-agreement line (`../backlog/records.md`), else "made without the maintainer". Five decision lines is a length target only; no key choice is dropped to meet it. The detail behind a line stays in the implementer's report and the item's records, given when the maintainer asks. A "made without the maintainer" mark never replaces asking the maintainer about outcome, scope, cost or risk (`rules.md`), except an outcome a skill lets the session settle, such as one the spec leaves open that `mentat:build` settles (steps 5 and 7).

Each other call made without the maintainer is also one decision line with that mark, once, and not also as a risk or in Review details (beyond a finding's line giving it as its reason, and the higher round limit line): each review stop the session settled itself, with its round (`../review/stop.md`); the session's own extra round at the round limit; and each real defect filed as a follow-up at the round limit on a head that may be Ready, saying it was filed (`../review/stop.md` "Round limit").

A risk line, aiming at about 12 words without dropping what this skill or a review skill has it name, names one item the maintainer must read before merging, in plain words:

- a revert that does not fully undo the change: what stays and why, such as deleted data, a release, a migration or an interface others use;
- what breaks, for whom;
- a changed hook, CI workflow or agent instruction file whose behavior changes, with the reason it deserves a look;
- anything in the diff beyond the request;
- a finding left unfixed (not one filed at the round limit), or a blocking finding answered instead of fixed;
- a review that did not cover the head or the current spec, or a reviewer that was incomplete: a fast track, a head not reviewed, or outside reviewers unknown (`mentat reviewers`); where they are on, an outside review that did not run on the head or ran on an older spec, or a listed reviewer that did not finish (a refusal for usage or billing named only as that reviewer being unavailable, its cause told in chat); never a review by Claude alone where outside reviewers are off;
- a manual check still open.

A decision's safety effect, or another consequence listed above, still gets its own risk line. Leave out a revert that fully undoes the change, and say nothing about hooks, workflows or instruction files when none changed in behavior.

## Writing the Test plan

The Test plan gives each check run on the head commit and its result, the test command and CI included, and anything not checked, and why. When `../build/helpers.md` "Testing" left the test run to CI, it reports the implementer's run.

The requirement table has one row per numbered requirement of the spec, by number (an older issue or item, agreed before the spec had that name and with no numbered list, is read as each requirement it states); one check may cover several.
