# Build sessions

Read this, part of `SKILL.md` in this folder, at "Start", and again after a compaction. A section named in quotes is in this file or in `SKILL.md`.

## The build session

One build session per repository at a time. Before starting one, read the notes file and the host's list of the sessions this session started: a build session on that list, or one the notes file names by id, while it still runs by the host's view of it or its reply to the takeover message ("Notes"), is this session's one build session; hand work to it and start none. With the host's tools for starting and messaging a session, start one in its own worktree running `/mentat:build <ids>`, which is the go-ahead for those ids (`mentat:build` step 5), and write its id and those items with their spec fingerprints in the notes file. Without them, when the notes file records a build session the maintainer's command started, ask the maintainer whether it still runs, and if so give them the command for it as below. Otherwise give them the one fenced command to run, as `mentat:propose` "Starting a build" says, and record in the notes file a build session the maintainer's command started, with its items. That session then asks the maintainer itself, with no relays, and each later handover is the same command with the item's id, for them to type there.

## Pause

A pull request is waiting from its "Ready to merge" line until it merges or closes, held or not, read with `gh pr list --state open --limit 1000 --json number,body` in the repository, whatever the tracker: each open one whose Ready line the notes file records as relayed or whose backlog item's merge wait names it (`mentat:backlog` "Marking a wait"), and any other open one whose description's first line, its Status line (`mentat:pr`), reads `Ready`, `Not reviewed: fast track agreed by the maintainer` or `Not reviewed: last push waived by the maintainer`.

The limit N: read `MENTAT_READY_LIMIT` by name with `printenv MENTAT_READY_LIMIT`, never the whole environment; unset or empty, N is `3`. A value that is not a whole number of 1 or more counts as unset, said once.

While N pull requests are waiting, hand over no item and start no build session; builds in flight and planning go on. Otherwise hand over at most N minus the waiting ones at a time, counting each item from when it is handed over or put in a start command, or given to the maintainer in a command for a build session their command started, until the build session reports, or the maintainer says, it did not take it, or its pull request has its "Ready to merge" line, merges or closes. An item the count holds back is a held item ("Handing over").

## After merge

When the maintainer says #N merged for an item in the notes file, tell the build session that #N merged, forwarding their words and asking it to reply once its after-merge steps (`after-ready.md` in `mentat:review`'s folder) are done, so the held items are re-read on that reply's turn ("Handing over"), or, for one the maintainer's command started, ask the maintainer to say it there and to tell this session once they are done; when no build session runs, tell the maintainer no session will take them. Record it merged in the notes file.
