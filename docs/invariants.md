# Invariants

The guardrails and workflow rules each 1.0 rewrite stage must keep. A stage is reviewed against every line here: a rewrite that drops or loosens one is a finding, whatever the text it replaces, except narrowing an after-agreement ask toward the four stop conditions, as the line under "When a session stops for the maintainer" says.

Each line gives the rule, the file that holds it today and how it is checked: a behavior eval case under `evals/` by name (its score kept as `evals/README.md` "Keeps the score" says), or, for a line no eval case covers, "review only", read against the line by the reviewer, with any `tests/run` check that also covers it named beside it. A check named "`tests/run` text check" only shows that the rule's words are still there. A line marked "rare safety net" is kept whatever its fire count: it rarely fires, and that is not a reason to drop it.

## Plugin-wide rules

### Merge, push and secrets

| Rule | Source | Check |
|---|---|---|
| The maintainer merges every pull request; agents never merge or turn on auto-merge. | `rules.md` "Approval", "What agents never do"; also `AGENTS.md` | `merge-request-declined`; `tests/run` text check against `tests/fixtures/rules-safety.md` |
| Agents never use `--admin` or work around a merge refusal. | `rules.md` "What agents never do"; also `AGENTS.md` | `tests/run` text check against `tests/fixtures/rules-safety.md`; review only |
| Rare safety net: the merge hook denies `gh pr merge` (`--auto`, quoted flags and line continuations included), the REST merge paths and GraphQL merge, auto-merge and merge-queue mutations through `gh api` (also when the call holds one anywhere and hands `gh api` a variable, substitution, `--input` or `@file`, or builds a merge path from an expansion such as `"$p/merge"`), and MCP merge and auto-merge tools under any server, and fails closed when it cannot decide. | `hooks/no-merge`, `hooks/hooks.json`, `hooks/lib/verdict.sh` | `tests/no-merge.sh`, `tests/hook-contract.sh`; review only |
| Agents never push code to the default branch, force-push shared branches or change repository settings. | `rules.md` "What agents never do" | `tests/run` text check against `tests/fixtures/rules-safety.md`; review only |
| Rare safety net: the default-branch refusal: agents' pre-push hook refuses an update, force push or deletion of the remote's default branch, and the first branch pushed to a remote with none; a push to a local path or `file://` URL may update any branch. | `git-hooks/hooks/pre-push` | `tests/git-hooks.sh`; review only |
| A build branch is cut from origin's default branch with no upstream (`--no-track`), so a bare `git push` never aims at the default branch. | `skills/build/helpers.md` "Worktree" | `tests/worktree-branch.sh`; review only |
| Agents never commit, print or post secret values or bring production credentials into a session; exposed ones go to the maintainer at once, for rotation, not just deletion. | `rules.md` "What agents never do" | `tests/run` text check against `tests/fixtures/rules-safety.md`; review only |
| Rare safety net: the secret scan: agents' pre-commit and pre-push hooks refuse a staged or pushed likely secret, the pre-push hook in the outgoing commits' diffs and in their commit and tag messages, and refuse when the scan cannot run. | `git-hooks/hooks/pre-commit`, `git-hooks/hooks/pre-push`, `git-hooks/scan` | `tests/git-hooks.sh`; review only |
| The git hooks run the repository's own hooks after their own checks pass. | `git-hooks/own-hook.sh` | `tests/git-hooks.sh`; review only |
| Agents never create releases, deploy, publish, change secrets, or run production migrations or destructive outside operations, beyond preparing them. | `rules.md` "What agents never do" | `tests/run` text check against `tests/fixtures/rules-safety.md`; review only |

### Public text

| Rule | Source | Check |
|---|---|---|
| A pull request description holds no local paths. | `rules.md`, `skills/backlog/records.md` | `no-local-path-in-pr` |
| GitHub records (issues, pull requests, comments) are public-safe: Claude Code's words; no chat quotes, private repository or project names, local paths, account, billing or session details. | `rules.md`, `skills/backlog/records.md` | review only |
| A spec, and with an external backlog a pull request body, never names the backlog's workspace or item. | `skills/backlog/SKILL.md` "Agreement", `skills/pr/SKILL.md` step 1 | review only |
| Rare safety net: the public-text check: the `mentat-public-text` hook denies a listed `gh` write or GitHub MCP write whose text holds a private word or a local home path, or whose text it cannot read. | `plugins/mentat-public-text/hooks/public-text`, `plugins/mentat-public-text/hooks/hooks.json` | `tests/public-text.sh`; review only |

### Review

| Rule | Source | Check |
|---|---|---|
| After pushing, call `mentat:review`; a pull request is not called ready before its review runs. | `rules.md`, `skills/review/SKILL.md` | `review-after-push` |
| Reviewer isolation: fresh-context Claude reviews, headless, in a temporary worktree of the head, with read tools only, no shell and no plugins. | `rules.md`, `lib/review.sh`, `skills/review/SKILL.md` step 1 | `tests/review-local.sh`; review only |
| Codex's review runs in a sandbox that denies files inside the checkout that commonly hold credentials. | `plugins/mentat-reviewers/adapters/codex.sh` | `tests/review-codex.sh`; review only |
| Posting only after CI: each review waits for CI on its head and posts its result only once CI passes; a CI failure posts nothing and is no round; a head with no CI checks posts after about a minute's wait, or, with `--require-ci`, posts nothing and is no round. | `skills/review/SKILL.md` steps 1 and 2 and "Outside review", `lib/review.sh`, `lib/shared.sh`, `plugins/mentat-reviewers/lib/outside.sh` | `tests/review-local.sh`, `tests/review-outside.sh`, `tests/review-codex.sh`; review only |
| Where outside reviewers run, a Status Ready head has had its own outside review attempted, including a head whose local findings were all answered with nothing pushed; Ready is weaker only when that run failed, was held or did not finish. | `skills/review/SKILL.md` "When the loop ends", step 3, "Outside review" and "Final check", `skills/review/stop.md` "Round limit", `plugins/mentat-reviewers/lib/outside.sh`, `docs/adr/0010-outside-review-on-every-ready-head.md` | `tests/review-outside.sh` (the run is not refused on a head whose local review posted findings); review only |
| A failed review is no pass: a review that fails, times out or returns nothing is not a pass, and an INCOMPLETE result is not reviewed. | `skills/review/SKILL.md` steps 2 and 3 | `tests/review-local.sh`, `tests/status.sh`; review only |
| A plan check reply without a verdict line, an error or an empty result never counts as a pass. | `skills/plan/SKILL.md` step 6 | review only |
| The round limit: `MENTAT_REVIEW_ROUNDS` per pull request; a round is a local review that exits 0 or 2; after the last round no fix is pushed unless the limit is raised. | `skills/review/SKILL.md` "Hard stop", `skills/review/stop.md` "Round limit", `lib/review.sh` | `tests/review-local.sh`; review only |
| The session's extra round: after the last round the session raises the limit by one itself only when all four conditions of "Round limit" hold, and records it in Review details and in Decisions and Risks. | `skills/review/stop.md` "Round limit" | review only |
| A review stop is pending from round three on, after a completed round that posted findings (one raised again with no new evidence does not count, as `skills/review/findings.md` says), except the last round within the limit, which is no stop even when the limit is later raised; an ordinary stop is settled and recorded, and asked only when the findings, or a disproved assumption still open, show the goal or a required safeguard cannot be met without a scope change. | `skills/review/stop.md` | review only |
| Every review finding is sorted: fixed when it affects correctness, the requirements or security with a realistic trigger (on instruction text, not one that only covers a rare or harmless case), else answered with a reason; a real defect is fixed at a round before the last within the limit, its fix waiting while a stop is pending, and goes to the maintainer only when its fix would change the agreed scope or, at the round limit, the head cannot be Ready; a reviewer's blocking mark is a claim. | `skills/review/findings.md`, `docs/adr/0004-disputed-findings-follow-the-general-test.md` | review only |
| A disputed finding goes to the maintainer only when fixing or leaving it changes the agreed scope, the goal or a required safeguard; the rest are settled and logged in Review details. | `skills/review/findings.md`, `docs/adr/0007-review-stops-only-for-scope-goal-or-safeguard.md` | review only |
| The ledger: the description's Review details hold one line for each finding fixed or answered, with its fix commit or its reason; a finding raised again with no new evidence is answered by pointing to that line, except that one naming a specific error in that answer is sorted on whether the error holds, and one the maintainer settled is sorted again once the text it was about changed. | `skills/review/SKILL.md` step 4, `skills/pr/SKILL.md`, `skills/review/findings.md` | `tests/review-local.sh` (the reviewer prompt reads those lines); review only |
| Write "Ready to merge" only in `mentat:review`'s line for a ready pull request, or a word-for-word forward of it. | `rules.md`, `skills/review/SKILL.md` "Final check" | review only |
| After "Ready to merge: #N", push nothing to #N (work that belongs in #N) until the maintainer answers a "Hold #N" line, and rewrite its Status line to Blocked before that line. | `rules.md`, `skills/review/after-ready.md` | review only |
| A blocking finding answered instead of fixed, and each reason the review is weaker, gets a risk line in Decisions and Risks and a sentence in the Ready message. | `skills/review/SKILL.md` "Final check", `skills/pr/SKILL.md` | review only |
| Manual checks hold Ready: while a hand check before the merge is open, there is no "Ready to merge: #N", the Status line is Blocked and the wait is written. | `skills/review/ready-gate.md` | review only |
| Status headings: the description's first line is the Status line, holding only `Ready`, `In review`, `Blocked: <why>` or `Not reviewed: <why>`, rewritten after every push and whenever the review loop stops. | `skills/pr/SKILL.md`, `skills/review/SKILL.md` "When the loop ends" | review only |
| Status headings: the description keeps its sections (Summary, Decisions and Risks, Test plan, Review details), and Decisions and Risks, where calls made without the maintainer are logged, is on every pull request under that literal heading, even beside a repository template's own risk or decision section, saying none when empty. | `skills/pr/SKILL.md`, `skills/review/ready-gate.md` | `tests/status.sh` (`mentat status` reports a missing calls section, and accepts an older pull request's "Calls made without the maintainer" heading); review only |
| The review comment headings `mentat status` reads are still written as it reads them. | `lib/review.sh`, `lib/status.sh`, `plugins/mentat-reviewers/lib/outside.sh` | `tests/run` heading check, `tests/status.sh`; review only |
| The spec fingerprint: recorded at agreement from the spec read back from the tracker, recorded again when an agreed scope change rewrites the spec; each local review records the request's fingerprint, and a local review that did not cover the current spec needs another round (an outside review on an older spec is run again). | `skills/backlog/SKILL.md` "Agreement", `skills/review/SKILL.md` "Spec", "Outside review" and "Final check" | `tests/fingerprint.sh`, `tests/status.sh`; review only |

### Planning and build

| Rule | Source | Check |
|---|---|---|
| Call `mentat:plan` before giving a view on a change. | `rules.md`, `skills/plan/SKILL.md` | `plan-before-view` |
| Call `mentat:plan` before suggesting a change. | `rules.md`, `skills/plan/SKILL.md` | review only |
| Nothing is built before the maintainer's agreement; the one exception is an item `mentat-lead:orchestrate` agrees by default when nothing is open for the maintainer, recorded as agreed by default, never as their answer. | `skills/plan/SKILL.md` opening and step 8, `plugins/mentat-lead/skills/orchestrate/SKILL.md` "Planning", `skills/backlog/SKILL.md` "Agreement", `docs/adr/0002-orchestrator-agrees-by-default.md` | `tests/run` text check; review only |
| One agreement, after the plan check: the plan check's `DO IT` is not the agreement; the maintainer agrees once, asked after the plan check unless `mentat-lead:orchestrate` agrees by default; agreed work whose spec is unchanged and that takes in no scope still needing agreement, such as scope triage merged into it, gets no further plan check; a small, clear request (as `skills/plan/SKILL.md` defines it) is agreed from its one-line view with no plan check. | `skills/plan/SKILL.md` opening, step 7 and "Small requests" | review only |
| A request that changes the meaning of what a repository's `AGENTS.md` tells agents is not small and gets the plan check, however short. | `skills/plan/SKILL.md` "Small requests" | `instruction-change-not-small` |
| A request that changes the meaning of what an agent is told in Mentat's `rules.md`, skills or implementer prompt, or in other standing agent instructions, is not small and gets the plan check, however short. | `skills/plan/SKILL.md` "Small requests" | review only |
| Objections recorded: an objection in the reply to the agreement question is recorded on the item, and such a reply that names no Agree answer is not an agreement. | `skills/plan/SKILL.md` step 7 | `objection-in-agreement-reply`; `tests/run` text check |
| Objections recorded: objections to the design, plan or pull request are recorded on the item in one decisions line, each its own clause, also when made in any talk after the agreement question, at a hold or at a close without merging, and are not an agreement. | `skills/plan/SKILL.md` step 7, `skills/review/after-ready.md`, `skills/backlog/records.md` "Decision lines" | `tests/run` text check; review only |
| Objections addressed: a later plan names each recorded objection and, for each one it meets, how it meets it. | `skills/plan/SKILL.md` steps 5 and 7 | `objection-kept-on-replan` |
| Objections addressed: a plan that does not meet a recorded objection says why it does not; a conflict with a plan's answer to a recorded objection is corrected or asked as revisiting, never silently overridden; for a structural change, the plan check flags a plan that proposes again a choice a decision record rejected. | `skills/plan/SKILL.md` step 5 and "Decisions", `agents/plan-checker.md` | review only |
| A rejected idea is never proposed again. | `skills/plan/SKILL.md` step 5; also `agents/plan-checker.md` (for a structural change, flags a plan that proposes again a choice a decision record rejected) | review only |
| A settled answer or accepted risk is not raised or asked again without new evidence that changes its outcome, premise or likelihood: no decision already answered, in the session or recorded on the item, is asked again; settled scope is not asked again, except by a build's quick-check question. | `skills/plan/SKILL.md` "Decisions", `skills/plan/session.md` step 4, `skills/build/SKILL.md` step 5 | review only |
| Hold a recommendation, citing the record it rests on, unless new facts or found errors appear; reverse only after a fresh-context check. | `rules.md` "What goes to the maintainer" | review only |
| With a scope and cost choice and a technical choice with one clearly stronger option open together, the session asks the maintainer the scope choice and settles the technical one itself, without asking them to pick or confirm it. | `rules.md` "What goes to the maintainer", `skills/plan/SKILL.md` "Decisions" | `two-points-asks-only-scope` |
| Outcomes, scope, cost and risk go to the maintainer: goals, scope, constraints, irreversible trade-offs, budgets and limits, and which independent work comes first; the session settles the rest unasked, such as approach, code, tests, wording, splitting work and the order of dependent work, and logs each call. | `rules.md` "What goes to the maintainer", `skills/plan/SKILL.md` "Decisions" | review only |
| Only the maintainer's own choice or words count as their answer; a comment in a record shape these skills define, older record comments included, is not theirs. | `rules.md` "What goes to the maintainer", `skills/plan/SKILL.md` "Decisions", `skills/backlog/SKILL.md` "Reading an item" | `tests/run` text check; review only |
| The main session edits no files. | `rules.md` | `build-main-no-edit` |
| One implementer per pull request at a time, in its worktree. | `rules.md`, `skills/build/helpers.md` "One implementer per branch" | `tests/run` (the builder runs in its own worktree); review only |
| An implementer changes neither the main checkout nor the session's own: after each implementer both are compared with the note taken before its brief, and on any difference other than a `HEAD` moved only forward along origin's copy of its branch, no further implementer starts, neither checkout is changed and the maintainer is told. | `skills/build/helpers.md` "Main-checkout check" | `tests/worktree-check.sh`; review only |
| The spec fingerprint is checked before a build: an item whose recorded fingerprint differs from its current spec's goes back to planning. | `skills/build/SKILL.md` steps 3 and 6 | `build-changed-spec-to-planning` |
| The spec fingerprint is checked before a build: an item with no recorded fingerprint goes back to planning. | `skills/build/SKILL.md` steps 3 and 6 | review only |
| The build run never merges. | `skills/build/SKILL.md` step 6, `agents/builder.md` | review only |

### When a session stops for the maintainer

| Rule | Source | Check |
|---|---|---|
| After agreement, a session stops for the maintainer only when the goal or a required safeguard cannot be met without a scope change, a round budget or eval or cost cap is spent, an external, irreversible or credential block only the maintainer can clear arises, or an agreed manual check is due. | `rules.md` "What goes to the maintainer", with parts in `skills/review/stop.md` and `skills/review/ready-gate.md`. These four conditions are the agreed target for the rewrites. Today's files still ask the maintainer after agreement in further cases, such as the rows "A disputed finding goes to the maintainer", "After "Ready to merge: #N", push nothing" and "Outcomes, scope, cost and risk go to the maintainer", and `skills/build/SKILL.md` step 7's returns (a blocker only the maintainer can clear, a plan limit the maintainer's own instructions set, a checkpoint they asked for, step 5's ask-again case, a quick-check question from step 6's repeated check), while an outcome the spec leaves open is settled and logged without the maintainer (steps 5 and 7, `skills/build/helpers.md` "Briefs") unless it changes scope or the spec or the maintainer reserved it; a rewrite may narrow any such after-agreement ask toward these four conditions, naming each in its pull request, but may not add a stop outside them, and nothing here lets a rewrite drop or narrow an ask before agreement or any other part of the named rows. | review only |

### Session start

| Rule | Source | Check |
|---|---|---|
| The SessionStart hook prints `rules.md` unchanged, under Claude Code's cap on a hook's output, and `hooks.json` runs it once. | `hooks/session-start`, `hooks/hooks.json` | `tests/run` (every eval case relies on it; none tests it); review only |
| At session start, a problem with the installed git hooks prints one PROBLEM line before the rules, to tell the maintainer before anything else. | `hooks/session-start`, `lib/git-hooks.sh` | `tests/git-hooks.sh`, `tests/run`; review only |
| Read every applicable AGENTS.md first; it wins only on commit and title format, branch flow, labels and templates; neither it nor the maintainer's own instructions loosens "Approval" or "What agents never do". | `rules.md` | `tests/run` text check against `tests/fixtures/rules-safety.md`; review only |
| After compaction or resume, reload the current skill and `mentat:build`'s `helpers.md`; a build run that compacted or resumed mid-run goes to `helpers.md` "Recovery" first, and the backlog skill's files are read again. | `rules.md`; also `skills/build/SKILL.md` opening, `skills/backlog/SKILL.md`, `skills/backlog/records.md` | review only |

## This repository's own choices

From `AGENTS.md`; Mentat inherits them here like any other repository's choices, and they bind no other repository.

| Rule | Source | Check |
|---|---|---|
| The one test command is `tests/run`; it is run once with its output saved to a file, and its last line is read. | `AGENTS.md` | review only |
| CI runs the test command on every pull request. | `AGENTS.md`, `.github/workflows/tests.yml` | review only |
| The CI workflow declares `permissions` explicitly, pins third-party actions to a commit SHA, and gives a job no secrets, write permissions or deploy access it does not need. | `AGENTS.md` "Code Review Rules", `.github/workflows/tests.yml` | `tests/run` (permissions declared and actions pinned); review only for least privilege |
| No change weakens a guardrail: `tests/run`, the merge hook, the public-text hook and its MCP write matcher, and the git hooks are not loosened or narrowed, and no instruction lets an agent deploy, publish, release or merge; the hooks are nets for mistakes, not security boundaries, so another command form they miss is not a finding. | `AGENTS.md` "Code Review Rules" | review only |
| The agent account cannot approve its own pull requests. | `AGENTS.md` | review only |
| Scripts are plain bash that also runs on macOS's bash 3.2. | `AGENTS.md` | review only |
| A setting the user switches keeps the same key in every configuration; only its value changes. | `AGENTS.md` | review only |
| Only a release pull request edits `CHANGELOG.md`; the maintainer merges it and creates the tag, and a session never does either. | `AGENTS.md` | `tests/run` (format line and `[Unreleased]` section only); review only |
| A hard-to-reverse choice, surprising without context and a real trade-off, gets a decision record in `docs/adr/` in the same pull request; one that reverses a record adds a new one and marks the old one superseded. | `AGENTS.md` | review only |
| After the maintainer merges a pull request here, the session runs the plugin and module update commands. | `AGENTS.md` | review only |
| Working files go in `work/`, which git ignores. | `AGENTS.md` | review only |
