# Tracker: GitHub issues

For a repository whose AGENTS.md names no external backlog: its GitHub issues are the backlog.

- Stages (step 2). Where the repository uses stage labels (`idea`, `ready`, `in progress`, `waiting`), `idea` marks the Inbox, `ready` Todo, `in progress` In Progress and `waiting` a wait on the maintainer; Backlog is an open issue with no stage label. Without them, an Inbox issue's opening sentence says it waits in the Inbox, Todo is the issues in the pinned issue's order, Backlog is any other open issue, and In Progress is an issue with a branch or pull request. Done is a closed issue.
- The tracker's order (step 5): where the repository uses one, the pinned issue holds the order of agreed work, next first, without closed or parked issues. An entry whose issue waits on the maintainer points to the wait.
- Triage outcomes. Accept: the same issue becomes the item; remove `idea`, or rewrite the opening sentence so it no longer says it waits in the Inbox. Close: `gh issue close <N> --reason "not planned"`, with the reason in a comment. Merge: `gh issue close <N> --reason duplicate`, with a comment naming the target. Later: a dated comment; the issue stays open.
- An issue Claude Code files or the maintainer agrees opens with one sentence saying where the work came from, in the terms of the item shape's first bullet.
- When an issue closes with scope triage merged into it still not agreed, file that scope as its own issue, in Backlog, linking the closed one.
- Each issue gets one label for what it is, from the repository's own (GitHub defaults: `bug`, `enhancement`, `documentation`, `question`).
