# Glossary

Mentat's rules, skills and agents use one word for each idea below. This file governs the files rewritten to it: `tests/run` keeps a list of the rule, skill and agent files not yet rewritten, and fails when any other of them uses a word an entry's Avoid line names. Until a skill is rewritten, a heading or label its template requires is used as written, even where this file names another word; a rewritten file that cites such a heading puts it in a code span, which the check skips.

Machine-read names never change here: file names, setting keys, and subagent, skill and command names. An entry notes one where it differs from the entry's word.

Each entry gives the word to use as its heading, its meaning, and an Avoid line. `Avoid:` matches the words it names in any case, with their plural, -ed, -ing and hyphenated forms. A coined term that stays says why on a `Kept:` line.

## agreement question

The one question that asks the maintainer to agree to a plan, with its named answers.

Kept: no plain phrase names this one question, and "approval" already names the maintainer's merge.
Avoid: approval question

## assumption

An unchecked fact a plan relies on that would change the design or the checks if false.

Avoid: material assumption
Machine-read name: the record line `Material assumptions:` keeps its form.

## blocked-by link

The tracker's own link from an agreed item to each item it waits on before it can start. Other waits keep the word "wait".

Avoid: start wait

## forward

To pass a message, answer or write from one session on to another session or to the maintainer, word for word where the sending file says so.

Avoid: relay

## implement

To carry out an agreed item: make its change, test it, get it reviewed and open its pull request.

Avoid: build, built
Machine-read name: `mentat:build`, typed as `/mentat:build`, and the agent records line `build: now`.
Heading: the answer `Agree and build now` stays until its file is rewritten; cite it in a code span until then.

## implementation session

A session that implements one or more agreed items.

Avoid: build session
Machine-read name: `mentat:build`, typed as `/mentat:build`, and `plugins/mentat-lead/skills/orchestrate/build-sessions.md`.

## implementer

The subagent that edits, tests and commits one change in its own worktree.

Avoid: builder
Machine-read name: `mentat:builder`, `MENTAT_BUILDER_MODEL` and `skills/build/helpers.md`.

## item

One piece of work in the tracker: a Linear issue or a GitHub issue.

Avoid: ticket

## manual check

Something the maintainer tries and reports on that changes nothing, such as a page or a command's output; it holds the pull request back from merge until they report it, or runs after the merge where the spec says so.

Avoid: hand check, hand test

## manual step

Something only the maintainer can do that changes something, such as a setting, a secret, an install or a sign-in; the work waits until they have done it.

Avoid: hand step, setup step
