# Glossary

Mentat's rules, skills and agents use one word for each idea below. This file governs the files rewritten to it: `tests/run` keeps a list of the rule, skill and agent files not yet rewritten, and fails when any other of them uses a word an entry's Avoid line names. Until a skill is rewritten, a heading or label its template requires is used as written, even where this file names another word.

Machine-read names never change here: file names, setting keys, and subagent, skill and command names. An entry notes one where it differs from the entry's word.

Each entry gives the word to use as its heading, its meaning, and an Avoid line. `Avoid:` matches the words it names in any case, with their plural, -ed, -ing and hyphenated forms; `Avoid (whole phrase):` matches only the exact phrase; `Avoid: none` names nothing. An `Ambiguous:` line marks a word used in more than one sense: say which sense is meant. The check counts such words and never fails on them. A coined term that stays says why on a `Kept:` line.

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

## brief

The main session's instructions to the builder for one change.

Avoid: none

## build session

A session that runs `mentat:build` on one or more agreed items.

Avoid: none

## builder

The subagent that edits, tests and commits one change in its own worktree.

Avoid: none
Machine-read name: `mentat:builder`.

## fast track

The path that skips the code reviews for a change that cannot alter what code does or what an agent is told; tests, CI and the final check still run, and only the maintainer turns it on.

Kept: "skipped review" would lose that tests and the final check still run and that only the maintainer agrees to it.
Avoid: none
Machine-read name: `skills/review/fast-track.md`.

## fingerprint

The hash of an item's spec, recorded at agreement, that shows whether the spec changed since.

Avoid: none

## forward

To pass a message, answer or write from one session on to another session or to the maintainer, word for word where the sending file says so.

Avoid: relay
Machine-read name: the section headings "Relays" and "Relayed writes" stay until their files are rewritten.

## grill

A guided talk in which the maintainer answers open decisions one at a time.

Kept: it is the command's name, `/mentat-lead:grill`, which the maintainer types.
Avoid: none

## handover

A session message from a starting session that names an item and its spec's fingerprint; it is the go-ahead to build that item.

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

## main session

The session the maintainer talks to; it plans, briefs builders and edits no files itself.

Avoid: none

## maintainer

The person who owns the repository, decides outcomes, scope, cost and risk, and merges every pull request.

Avoid: none

## manual check

A requirement the maintainer checks by hand, which holds the pull request back from merge until they report it, or runs after the merge where the spec says so.

Avoid: hand check

## next-work offer

The question at the end of a turn that offers to start the next agreed items.

Kept: it names the offer by what it offers, and its rules live in `next-work.md`.
Avoid: none

## not-ready option

The answer to a question that says the maintainer is not ready to decide or wants to talk first; it records nothing.

Kept: no shorter plain phrase says it.
Avoid: none

## orchestrator

The session running `mentat-lead:orchestrate`, which plans items, hands them to build sessions and forwards their questions.

Avoid: none
Machine-read name: `mentat-lead:orchestrate`.

## plan check

One round of a fresh-context check of a plan, by the plan checker subagent, before the maintainer is asked to agree.

Kept: "plan review" would blur it with the reviews of a pull request.
Avoid: plan review
Machine-read name: `mentat:plan-checker`, `MENTAT_PLAN_CHECK_MODEL` and the reply's `PLAN CHECK VERDICT:` line.

## Ready line

The "🔔 Ready to merge: #N" line that says a pull request is ready for the maintainer to merge; every repeat keeps it word for word.

Kept: it names the line by the word every copy of it starts with.
Avoid: none

## second opinion

A plan's reading by outside tools (Codex, and Grok where installed) after its plan check.

Avoid: none
Machine-read name: `mentat second-opinion`.

## situation list

The list, in a plan, of each event, state or class of input the change must handle, with its outcome.

Kept: "test cases" and "input classes" each name only part of it.
Avoid: none

## sitting

One triage run with the maintainer: gather new ideas into the Inbox, then settle each one.

Kept: "session" already names a Claude Code session, and a sitting is a run inside one.
Avoid: none
Machine-read name: `/mentat-linear:triage`.

## spec

An item's agreed requirements, kept where the tracker's adapter says; the build and the review work from it.

Avoid: none

## spec fix

A build session's correction, before the first review, of a reference in an agreed spec to something that already exists.

Avoid: none

## stage

Where an item stands in Mentat's terms (Inbox, Backlog, Todo and the rest), which the tracker's adapter maps to its own statuses or labels.

Avoid: none

## tracker

The tool that holds the items: Linear, through the `mentat-linear` module, or GitHub issues.

Avoid: none
