# Glossary

Mentat's rules, skills and agents use one word for each idea below. This file governs the files rewritten to it: `tests/run` keeps a list of the rule, skill and agent files not yet rewritten, and fails when any other of them uses a word an entry's Avoid line names. Until a skill is rewritten, a heading or label its template requires is used as written, even where this file names another word; a rewritten file that cites such a heading puts it in a code span, which the check skips.

Machine-read names never change here: file names, setting keys, and subagent, skill and command names. An entry notes one where it differs from the entry's word.

Each entry gives the word to use as its heading, its meaning, and an Avoid line. `Avoid:` matches the words it names in any case, with their plural, -ed, -ing and hyphenated forms; `Avoid (whole phrase):` matches only the exact phrase; `Avoid: none` names nothing. An `Ambiguous:` line marks a word used in more than one sense: say which sense is meant. The check counts such words and never fails on them. A coined term that stays says why on a `Kept:` line.

## advice against

Claude Code's advice not to build an item, recorded on the item when the maintainer goes ahead anyway and quoted by the final check.

Avoid: none

## after-merge steps

What a session does once the maintainer says its pull request merged, such as the wait block's steps, marking the item done and deleting the merged branch.

Avoid: none

## agent records

The one comment on an item, first line `Agent records`, that holds what agents keep for it: the spec's fingerprint, assumptions, settlements and decisions lines.

Avoid: none

## agreement

The maintainer's yes to build a plan, or the orchestrator's default agreement, which commits the item and writes its spec.

Avoid: none

## agreement question

The one question that asks the maintainer to agree to a plan, with its named answers.

Kept: no plain phrase names this one question, and "approval" already names the maintainer's merge.
Avoid: approval question

## assumption

An unchecked fact a plan relies on that would change the design or the checks if false.

Avoid: material assumption
Machine-read name: the record line `Material assumptions:` keeps its form.

## backlog

Used in three senses: the tracker, the work in it, and the Backlog stage (accepted, not committed).

Ambiguous: say "tracker", "items" or "the Backlog stage" where the sense is not plain.
Avoid: none

## blocked-by link

The tracker's own link from an agreed item to each item it waits on before it can start. Other waits keep the word "wait".

Avoid: start wait
Machine-read name: `skills/backlog/start-waits.md`.

## brainstorm mode

The triage mode that turns the maintainer's text or link into lettered ideas for them to pick from, with no readers run.

Avoid: none
Machine-read name: the `brainstorm` argument of `/mentat-linear:triage`.

## brief

The main session's instructions to the builder for one change.

Avoid: none

## build session

A session that runs `mentat:build` on one or more agreed items.

Avoid: none

## builder

The subagent that edits, tests and commits one change in its own worktree; `mentat:build` also calls one builder per branch a helper until it is rewritten.

Avoid: none
Machine-read name: `mentat:builder`.

## decision

A choice that is the maintainer's: an outcome, scope, cost or risk. Claude Code settles every other choice itself.

Avoid: none

## fast track

The path that skips the code reviews for a change that cannot alter what code does or what an agent is told; tests, CI and the final check still run, and only the maintainer turns it on.

Kept: "skipped review" would lose that tests and the final check still run and that only the maintainer agrees to it.
Avoid: none
Machine-read name: `skills/review/fast-track.md`.

## final check

The review's last step once its loop ends ready: reading the diff, the description and the spec afresh from GitHub and correcting any claim that does not hold, before the Ready line.

Avoid: none

## fingerprint

The hash of an item's spec, recorded at agreement, that shows whether the spec changed since.

Avoid: none

## follow-up

A new item filed for work found during or after another change, such as a manual check that failed after the merge.

Avoid: none

## forward

To pass a message, answer or write from one session on to another session or to the maintainer, word for word where the sending file says so.

Avoid: relay
Heading: the section headings "Relays" and "Relayed writes" stay until their files are rewritten; cite them in a code span until then.

## go-ahead

What lets a build start on agreed items: "Agree and build now", the maintainer's typed `/mentat:build`, a yes to a next-work offer, or a handover.

Avoid: none

## grill

A guided talk in which the maintainer answers open decisions one at a time.

Kept: it is the command's name, `/mentat-lead:grill`, which the maintainer types.
Avoid: none

## handover

A session message from a starting session that names an item and its spec's fingerprint; it is the go-ahead to build that item.

Avoid: none

## held item

An item the orchestrator has the go-ahead to build but has not handed over yet, because of its blocked-by links, the pause count, the maintainer's word to pause new builds or a hold.

Avoid: none

## hold

Used in several senses: the "Hold #N" message that keeps a pull request from being pushed to, an item kept from starting, and the orchestrator keeping an item for a build session.

Ambiguous: say which hold is meant where it is not plain.
Avoid: none

## issue

Used in two senses: a GitHub issue, which is an item where GitHub issues are the tracker, and a problem.

Ambiguous: say "item" for work and "problem" for a fault; keep "issue" for a GitHub issue by name.
Avoid: none

## item

One piece of work in the tracker: a Linear issue or a GitHub issue.

Avoid: ticket

## item shape

The fixed parts of an item's description, in a fixed order, that keep items alike.

Avoid: none

## main session

The session that plans a change and briefs its builders, then branches, pushes and opens the pull request; it edits no files itself, whether the maintainer talks to it or another session started it.

Avoid: none

## maintainer

The person who owns the repository, decides outcomes, scope, cost and risk, and merges every pull request.

Avoid: none

## manual check

A requirement the maintainer checks by hand, which holds the pull request back from merge until they report it, or runs after the merge where the spec says so.

Avoid: hand check

## merge wait

With an external backlog, the wait from an item's Ready line until its pull request merges or closes, marked as the tracker's adapter says, with no wait block.

Avoid: none

## next-work offer

The question at the end of a turn that offers to start the next agreed items.

Kept: it names the offer by what it offers, and its rules live in `next-work.md`.
Avoid: none

## not-ready option

The answer to a question that says the maintainer is not ready to decide or wants to talk first; it records nothing.

Kept: no shorter plain phrase says it.
Avoid: none

## notes file

The orchestrator's one working file, which records its build sessions, held and handed-over items, owed reports and open questions, so a later orchestrator session can take over.

Avoid: none
Machine-read name: `orchestrate-notes.md`.

## orchestrator

The session running `mentat-lead:orchestrate`, which plans items, hands them to build sessions and forwards their questions.

Avoid: none
Machine-read name: `mentat-lead:orchestrate`.

## owed report

A report the orchestrator owes the maintainer, such as an item agreed by default or a plugin update, given first and alone in its turn ahead of any open question. The orchestrate skill, until it is rewritten, calls these "tells".

Avoid: none

## pause count

The orchestrator's count of its open pull requests waiting from their Ready line to merge or close, which limits new handovers.

Kept: the orchestrate skill names it by its "Pause" section, and "waiting count" would blur it with waits on the maintainer.
Avoid: none

## plan

What a change will do and how its result will be checked, settled before the maintainer agrees; the proposal is the message that puts it to them.

Avoid: none
Machine-read name: `mentat:propose`, typed as `/mentat:propose`.

## plan check

One round of a fresh-context check of a plan, by the plan checker subagent, before the maintainer is asked to agree.

Kept: "plan review" would blur it with the reviews of a pull request.
Avoid: none
Machine-read name: `mentat:plan-checker`, `MENTAT_PLAN_CHECK_MODEL` and the reply's `PLAN CHECK VERDICT:` line.

## planning session

One run of `/mentat:propose` with no argument or one item id, which plans the project's open items, or that one item, in turn, then ends.

Avoid: none

## push notice

The one push notification a session sends, where it has a tool for it, when it first shows the maintainer a Ready line; a session another session started sends none.

Avoid: none

## quick check

A build session's check of each queued item before building: a fact in its spec that the current code contradicts, and a manual check only a worktree or branch copy could run.

Avoid: none

## readiness

A build session's check, before it builds an item, that the item is committed, has a spec whose fingerprint matches the recorded one, and holds no blocking decision.

Avoid: none

## ready gate

The check, once the reviews are done, that no manual check is open before the Ready line; an open one sets the Status line to Blocked.

Kept: it names the one point that decides between the Ready line and Blocked.
Avoid: none

## Ready line

The "🔔 Ready to merge: #N" line that says a pull request is ready for the maintainer to merge; every repeat keeps it word for word.

Kept: it names the line by the word every copy of it starts with.
Avoid: none

## redirect

Sending a go-ahead given in another session to the orchestrator's one build session, while an orchestrator runs for the repository.

Avoid: none

## review

Used in several senses: the `mentat review` run on a pull request, a Codex or Grok review, the review step that takes a pull request to ready, and the repository owner's review on GitHub.

Ambiguous: say which review is meant where it is not plain.
Avoid: none

## review depth line

The line right after the Ready line that says whether to review the pull request closely, with reasons, or skim it.

Avoid: none

## Review details

The folded section of a pull request's description that holds its review record, its requirement table and the models that built it.

Avoid: none

## review stop

A pause after a review round, from round three on, that posted findings: the session settles whether to go on, or asks the maintainer.

Avoid: none

## round limit

The number of review rounds a pull request gets; after the last one no fix is pushed unless the maintainer, or the session's one extra round, raises it.

Avoid: none
Machine-read name: `MENTAT_REVIEW_ROUNDS`.

## second opinion

A plan's reading by outside tools (Codex, and Grok where installed) after its plan check.

Kept: it is plain English and the command's name.
Avoid: none
Machine-read name: `mentat second-opinion`.

## settlement

The record of how a plan check's or second opinion's points were taken: what was adopted, what was not and why.

Avoid: none

## situation list

The list, in a plan, of each event, state or class of input the change must handle, with its outcome.

Kept: "test cases" and "input classes" each name only part of it.
Avoid: none

## sitting

One triage run with the maintainer: gather new ideas into the Inbox, then settle each one.

Kept: "session" already names a Claude Code session, and a sitting is a run inside one.
Avoid: none
Machine-read name: `/mentat-linear:triage`.

## skeptic's pass

A check, on the session's own model, of an existing item's records against the code and the item's goal, questioning every assumption and decision still in force.

Kept: no plain phrase says that it doubts every recorded premise, and "check" and "review" already name other steps.
Avoid: none

## small request

A clear one-line request with nothing for the maintainer to decide, which gets a one-line view in place of the full plan.

Avoid: none

## spec

An item's agreed requirements, kept where the tracker's adapter says; the build and the review work from it.

Avoid: none

## spec fix

A build session's correction, before the first review, of a reference in an agreed spec to something that already exists.

Avoid: none

## stage

Where an item stands in Mentat's terms (Inbox, Backlog, Todo and the rest), which the tracker's adapter maps to its own statuses or labels.

Avoid: none

## starting session

The session that started another session; the started session sends it its questions, its waits and its Ready and Hold lines, and only the starting session asks the maintainer.

Avoid: none

## Status line

The first line of a pull request's description, which says where it stands, such as Blocked or Not reviewed, and is rewritten after every push.

Avoid: none

## tracker

The tool that holds the items: Linear, through the `mentat-linear` module, or GitHub issues.

Avoid: none

## wait block

The heading at the top of an item's description saying it waits on the maintainer, with the numbered steps and the `Ends when:` line under it.

Kept: it names the heading, steps and end line together as one part of the item shape.
Avoid: none

## wait on the maintainer

Agreed work that cannot go on until the maintainer acts, such as a test or setup step only they can run, its item marked waiting; a wait block holds the steps, and a merge wait is the kind that ends at the merge.

Avoid: none

## waived round

A review round the maintainer agreed to skip after the Ready line, for a push that changes no file a program runs; CI and the final check still run.

Avoid: none
