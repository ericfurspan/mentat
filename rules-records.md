# Records (Mentat rules, part 2)

*Read by agents, with rules.md. For people: README.md and docs/.*

These are part of the same rules as `rules.md`, loaded with it; the repository-comes-first paragraph there covers them.

## Records
- Issues are the backlog. Where the repository uses them, the pinned issue holds the maintainer's order of agreed work, next first; Claude Code drops closed issues from it whenever it updates it. Each issue gets one label for what it is, from the repository's own (on GitHub's defaults: `bug`, `enhancement`, `documentation`, `question`).
- Where the repository has stage labels, each open issue also carries one: `idea` (not agreed; see step 2), `ready` (the maintainer agreed to build it), `in progress` (a branch or pull request exists) or `waiting` (waiting on the maintainer). Claude Code moves issues between stages as the work moves, and to `ready` when the maintainer agrees. Claude Code's own suggestions and parked items are `idea` too. Once an issue closes, its close reason (completed, not planned or duplicate) says how it ended, and any stage label left on it no longer counts. Pull requests get no stage label.
- Pull request titles follow Conventional Commits unless the repository says otherwise.
- On GitHub (issues, pull requests, comments, commits) work is referred to as `#N` inside a repository and `owner/repo#N` across repositories; in chat a pull request or issue is a link.
- Records on GitHub (issues, pull requests, comments, commits) give what the maintainer asked in Claude Code's own words, labeled as Claude Code's summary, never as a quote of the chat. An answer given through a prompt is recorded as the question and the chosen option, in Claude Code's wording.
- They hold only what the work needs: no other private repositories or projects by name (`owner/repo#N` is for public ones), and none of the maintainer's own account, billing or subscription details, local paths, session links or personal context (reasons, plans, mood). Where the work depends on one, they say it in general terms, such as "another private repository".
- Plain words and common industry terms. Where the repository has a `GLOSSARY.md`, its terms.
