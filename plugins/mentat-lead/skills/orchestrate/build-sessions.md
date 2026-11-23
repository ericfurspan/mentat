# Build sessions

Read this, part of `SKILL.md` in this folder, at "Start", and again after a compaction. A section named in quotes is in this file or in `SKILL.md`.

## Build sessions

A build session is mid-run from its start until it sends its final message (`mentat:build` step 8); then its run has ended, which this session records in the notes file. A session whose run has ended takes no new items; a question it relayed that is still open is relayed and answered as before ("Relays"). A build session still runs, whether or not its run has ended, while the host's view of it or its reply to a message of this session's says so. Each build session keeps its own pull requests: their Ready and Hold lines, review fixes and after-merge steps stay with it, and the notes file records which session took each item.

With the host's tools for starting and messaging a session, each item free to hand over ("Handing over") that no hold in "Holds" holds goes as follows. While a build session is mid-run and no after-merge reply since its start reported a Mentat plugin update, the items join its queue, each by the handover message of "Handing over". When no build session is mid-run, a fresh build session starts for them, together, in its own worktree running `/mentat:build <ids>`, which is the go-ahead for those ids (`mentat:build` step 5), and its id and those items with their spec fingerprints go in the notes file. A fresh build session starts only on a turn the host lets start one: on a turn another session's message started, the items stay held until the maintainer's next turn, and never go to a session whose run has ended.

Without them, when the notes file records a build session the maintainer's command started, ask the maintainer whether it still runs, and if so give them the command for it as below. Otherwise give them the one fenced command to run, as `mentat:propose` "Starting a build" says, and record in the notes file a build session the maintainer's command started, with its items. That session then asks the maintainer itself, with no relays, and each later handover is the same command with the item's id, for them to type there.

An item handed over again whose branch or kept worktree an earlier build session holds goes back to that session while it still runs, by one message naming the item and its spec fingerprint and asking it to resume its own work on it. That is not a handover and starts no new run: a session whose run has ended stays ended and takes no new items. The item leaves the held items, the notes file records it as handed back to that session, and it is counted in "Pause", confirmed and reported not taken as a handed-over item is ("Handing over"). When that session no longer runs, tell the maintainer, as for an item not taken ("Handing over").

Runs, fresh sessions, hand-backs, "Holds" and the after-merge reply apply only with the host's tools; without them, the paragraph above beginning "Without them", "Pause", and "After merge" for a session the maintainer's command started say all.

## Holds

An item free to hand over is held (a held item, "Handing over") while any of these stands:

- A merge passed on to a build session waits for its after-merge reply ("After merge"): no build session starts and no item joins a run until it arrives. Each time the holds are read, read whether the session it is pending from still runs ("Build sessions"); when it no longer runs, the reply is no longer pending and the next hold stands.
- An after-merge reply named a failed plugin update, or no session will take a merge's after-merge steps ("After merge"): it is told to the maintainer and recorded in the notes file, and items stay held until their word.
- The build session mid-run had an after-merge reply since its start report a Mentat plugin update, a failed one included: new items stay held until its run ends, then go as "Build sessions" says.
- No build session is mid-run on unchanged rules, and this turn cannot start a session: held until the maintainer's next turn.
- The item shares a file with an open pull request of an earlier build session than the one it would go to, predicted from the specs as `mentat:build` step 6 does: held until that pull request is merged and its after-merge reply has arrived or, where no session took its after-merge steps, the maintainer's word came, or until it closes unmerged. Within one session a shared file is `mentat:build` step 6's job.

## Pause

A pull request is waiting from its "Ready to merge" line until it merges or closes, held or not, read with `gh pr list --state open --limit 1000 --json number,body` in the repository, whatever the tracker: each open one whose Ready line the notes file records as relayed or whose backlog item's merge wait names it (`mentat:backlog` "Marking a wait"), and any other open one whose description's first line, its Status line (`mentat:pr`), reads `Ready`, `Not reviewed: fast track agreed by the maintainer` or `Not reviewed: last push waived by the maintainer`.

The limit N: read `MENTAT_READY_LIMIT` by name with `printenv MENTAT_READY_LIMIT`, never the whole environment; unset or empty, N is `3`. A value that is not a whole number of 1 or more counts as unset, said once.

While N pull requests are waiting, hand over no item and start no build session; builds in flight and planning go on. Otherwise hand over at most N minus the waiting ones at a time, counting each item from when it is handed over or put in a start command, or given to the maintainer in a command for a build session their command started, until its build session reports, or the maintainer says, it did not take it, or its pull request has its "Ready to merge" line, merges or closes. An item the count holds back is a held item ("Handing over").

## After merge

When the maintainer says #N merged for an item in the notes file, tell the build session that took that item, as the notes file records, that #N merged, forwarding their words and asking it to reply once its after-merge steps (`after-ready.md` in `mentat:review`'s folder) are done, naming each step that failed and whether a Mentat plugin update ran. Record that reply as pending until it arrives ("Holds"), and re-read the held items on that reply's turn ("Handing over"). A reply that a plugin update ran, a failed one included, is recorded for each build session then mid-run; one naming a failed plugin update is told to the maintainer ("Holds"). For an item whose build session the maintainer's command started, ask the maintainer to say it there and to tell this session once they are done. When the session that took the item no longer runs, at the merge or before its reply ("Holds"), tell the maintainer no session will take its after-merge steps, and record in the notes file, in place of a pending reply, that items stay held until their word ("Holds"). Record it merged in the notes file.
