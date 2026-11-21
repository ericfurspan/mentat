# The next-work ending

Read this before ending finished work when the maintainer's own instructions choose the "offer the next work" ending, which then replaces the ending its skill gives, and again after a compaction.

- Claude Code never suggests ending the session or starting a new one unless the maintainer said the session is ending.
- Only the session the maintainer is talking to offers, in one question as `../propose/decisions.md` gives, when its own work has just finished: after the maintainer says a pull request merged, once its item is marked done (the post-merge step in `../review/after-ready.md`), never from a backlog listing's cleanup or while a queue runs.
- An offer of agreed work that can start says what a yes authorizes: starting that batch, not merging open pull requests and not new scope. A merge still waiting is named in one line, in plain words, without repeating a "Ready to merge: #N" line an earlier message gave.
- Its lookup reads the next agreed work (`mentat:backlog` "The order of agreed work") read-only, and reports one of: the backlog could not be read; no recorded order; agreed work all waiting on the maintainer; agreed work none of which can start (in progress, waiting on an unmerged pull request, or held by its start wait, `mentat:backlog` "Start waits"); no agreed work. It offers only an item that can start, naming each one it passed with its wait, and names each item in any status with the wait mark (`mentat:backlog` "Marking a wait") and a hand check after the merge in its wait block as waiting on the maintainer, not in progress or done.
- When no agreed item can start (all waiting, none able to start, none at all, or no recorded order), it reads nothing more and asks nothing: it says that outcome in one line, in its own words, naming each item it passed with its wait, and never says nothing is left or the backlog is empty. When the read of agreed work fails, it says so, offers nothing and never reports empty.
- A session started by another session makes no offer; its ending goes to its starting session (`mentat:build` "Started sessions").
- After "Stop here", "Stop" or a no, no offer is made that turn; a no declines that batch only.
- A yes to an offer of agreed work starts that build in this session, as `mentat:propose` "Starting a build" says; `mentat:build` still runs readiness, plan usage and the quick check.
