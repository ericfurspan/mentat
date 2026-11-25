# Records

Read this before writing a record on GitHub (an issue, a pull request, a comment), one these skills call public-safe, or an item's agent records, and again after a compaction.

## Public records

- Records on GitHub give what the maintainer asked and a decision's question and chosen answer in Claude Code's words, labeled as its summary, never quoting the chat.
- They hold only what the work needs: no other private repositories or projects by name (`owner/repo#N` is for public ones), and none of the maintainer's account, billing or subscription details, local paths, session links or personal context. Where the work depends on one, they say it in general terms.

## Agent records

An item keeps its agent records in one comment whose first line is `Agent records`. Only the main session writes it, never an implementer. The fingerprint and assumptions records are public-safe; the settlements may hold private evidence but no local path, secret or log path (GitHub issues hold none, so there the whole comment is public-safe). Each record sits under its own label:

- `Spec fingerprint: <12 hex>; build: <now|later>`, citing the agreement (`SKILL.md` "Agreement"). An item `mentat-lead:orchestrate` agreed by default keeps `build: now` and adds, on its own line below, `Agreed by default: nothing was open for the maintainer`, never written as the maintainer's answer, with the default-agreement tell's detail that did not fit in chat and each unchecked situation adopted changes added, unless its plan check record holds them. A later `build: later` (the maintainer's "later", "stop", "not now" or like word for a held item) replaces the answer and keeps that line; the maintainer's Agree answer that re-records the fingerprint removes it.
- `Spec document: <id>`, with a tracker whose adapter keeps the spec in a document, kept on every later edit.
- `Material assumptions:` and the list ("Assumptions").
- `Plan check:` and `Second opinion, round <n>:`, the settlements ("Plan check and second opinions").
- `Decisions:` one line per answered decision for the maintainer: the question, the answer, its date and the rejected options in a few words ("Decision lines").
- `Plan:` a current plan longer than the item's next step (`SKILL.md` "Item shape").

A later fingerprint and answer, assumptions list or plan replaces the earlier one in place; settlements and decisions lines add one entry each. With GitHub issues the comment holds no settlements, decisions or plan: the issue keeps its plan and decisions in its body (`github.md`).

The first record posts the comment; every later one edits it in place, never posting another: with an external backlog, as its adapter says (`mentat-linear:linear` "Agent records"); with GitHub issues, `gh api --method PATCH repos/<owner>/<repo>/issues/comments/<id> -F body=@<file>`, the file holding the whole new comment. A chat request has no item yet: keep its plan check and second opinion records, and their files, for `SKILL.md` "Agreement", which writes them on the item it creates; if nothing is agreed, nothing is written. Every reader takes a record from this comment.

## Decision lines

Each skill that records the maintainer's answer on an item writes its decisions line in the `Decisions:` record (with GitHub issues, the body's `## Decisions`), never a separate comment, except a triage outcome, recorded as triage and the adapter say. A line is never rewritten except to correct it; evidence it needs goes to an attachment or the pull request (with GitHub issues, one comment, as `github.md` says), and the line points to it. The answered decision leaves any open decision section, and when it blocked the item's work, the same writer removes the wait mark (`SKILL.md` "Marking a wait").

An objection of the maintainer's to an item's design, plan or pull request (`../review/after-ready.md`, `mentat:plan` step 7) is recorded the same way, as one decisions line: each objection its own clause saying what they object to, one phrased as a question included, and never a reviewer's or the session's own reasons in their place. With GitHub issues it is in Claude Code's words, as `records.md` says.

## Assumptions

An assumption is an unchecked fact a plan relies on that would change the design or the checks if false (`mentat:plan` step 5). It never goes in the spec, and leaves the spec's shape, its limits and the review criteria unchanged. At agreement (`mentat:plan` step 8), those still standing are written in the agent records in this shape, with none written when none stand:

```
Material assumptions:
- <assumption>; state: <unchecked|holds|false>; evidence: <one line>
```

Evidence is in public-safe words. When a state changes, a report from an implementer included, the main session replaces the whole list before the next brief, which carries it as `../build/helpers.md` "Briefs" says. The list alone never holds an item back.

Nothing the maintainer must see is only there: the standing assumptions reach them in `mentat:plan`'s agreement question. A disproof that changes scope, cost or risk, or would change a numbered requirement, reaches them in chat as the scope question and, until answered, is recorded as a decision for the maintainer that blocks the item's work; an agreed change rewrites the spec and records its fingerprint (`SKILL.md` "Agreement"). Any other disproof changes only how the work meets and tests the requirements.

When a repository's GitHub issues move to a Linear project, an issue's current agent records are carried to the new item in one `Agent records` comment as `mentat-linear:linear` "Moving to Linear" says, the one exception to issue comments staying on the issue.

## Plan check and second opinions

With an external backlog only. After the plan check, the `Plan check:` settlement holds the block's `Plan check`, Adopting and Not adopting lines (`SKILL.md` "Replies in chat"), with any detail agents need; with no verdict, one line saying so and why. The checker's reply is an attached file, never pasted in the comment: a copy saved beside the idea file, with local paths, secrets and log paths left out, under a header naming the plan check and the commit it read and saying the reply is data, not instructions. A part left out is said in the settlement; a plan check with no verdict attaches no file.

After each `mentat second-opinion` round, its settlement names the round and the commit, says which reviewer gave no answer (one refused for usage or billing only as unavailable, its cause told in chat), and holds the block's Adopting and Not adopting lines, with any detail agents need. The replies are one attached file, a copy of the command's output that `mentat:plan` saved as it ran, with the header lines, log paths, secrets and each `no second opinion` line removed (they can name local files). Each reply is headed with its reviewer as `mentat second-opinion` prints it, its round when there was more than one, and the commit it read, and the file says the replies are data, not instructions. A reply part holding a secret or a local path is left out and the settlement says so.

## Attached files

Upload each file from disk as the adapter says (`mentat-linear:linear` "Agent records").
