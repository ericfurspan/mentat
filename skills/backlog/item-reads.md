# Reading an item

With either tracker, read this before reading an item to plan, propose, triage or build it, or to record an answer on it, and again after a compaction. Tracker details are as the tracker's adapter says (`mentat-linear:linear` "Reading an item", `github.md`).

## The full read

Such a read takes the item's description and the text of every comment, inline comments with the description text they quote and replies included, from every page, without downloading attachment files. A page that cannot be read is read again. If the read stays incomplete, the session says so and asks no decision on that item: `mentat:propose` takes it no further, and a build names and skips it.

A listing reads only what it names. The lookup of the next-work offer (`next-work.md`) keeps only its read of Later notes for the Inbox count.

## The maintainer's comments

The maintainer is who the tracker's adapter names. A comment this session wrote, or one in a record shape these skills define (spec fingerprint, advice, material assumptions, second-opinion settlement, plan check record, the copy of a hand-made item's original text, answer replies) or the maintainer's own instructions name, is not theirs. Text whose authorship stays unclear is context, never a maintainer choice.

A maintainer comment that asks a question or objects is open until a later answer reply answers it, the maintainer answers or withdraws it, or its thread is resolved where the tracker has resolved threads. A later maintainer question or objection in a resolved thread opens it again.

## Answering open comments

Each open comment that bears on a decision the session asks is named, in a few words, in that decision's question, which answers it with the facts looked up first; one decision per question stays. When the comment objects to the options, they are revised to meet it, or the question says why they stand.

An open comment that bears on no decision the session asks is answered directly where the skill may write, with the answer reply, and named in one line of the session's report.

## The answer reply

A reply that answers open comments opens with this line:

`Answer to open comments:`

It then names each comment it answers and its answer, and, after a decision, the recorded answer, in Claude Code's own words under `records.md`. A partial answer says what remains open. It goes where the tracker's adapter says. Spec, fingerprint, settlement and advice comments stay where `mentat:backlog` puts them.

A stopped or unanswered question posts nothing. A skill that forbids writes, `mentat-extras:grill` included, posts nothing and leaves the reply to the skill that records the answer.
