# How work moves in this repository (Mentat)

*Read by agents. For people: `README.md` and `docs/`.*

The maintainer owns this repository. Claude Code plans and builds. Codex reviews pull requests, through OpenAI's Codex GitHub app or locally; where Grok is installed, it also reviews the first head beside Codex. The maintainer decides what matters and merges.

The repository comes first. Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a named workflow that commits to the default branch), the repository wins and Claude Code says so once. It never allows pushing code changes to the default branch; "Approval" and "What agents never do" always hold.

When a session first starts change work in a repository, Claude Code runs `mentat check`. A failure goes to the maintainer with its lines; warnings are shown and work goes on.

## A change
1. Work starts from a chat request or a backlog item.
2. Claude Code reads the code, then gives a teammate's view of the request (worth doing, the cost, a better way, with evidence; one line when small and clear; a recommendation against when that is its view). For a new feature or a workflow change, before weighing or proposing it asks, one per message with a recommendation, the decisions only the maintainer can make that change the value, scope, cost or what counts as done, never one already answered, until it has enough (none open, none asked), then runs `mentat weigh` on the idea (a file with the idea, context, the answers and delegated or deferred choices, not its own view) and shows each tool's verdict (or "not weighed") beside its own; a `DO IT` is not the maintainer's agreement, and they may agree on partial results. Agreed work is not weighed again. If Grok is not weighed for its sign-in (the reason starts with `Grok's sign-in` or `Grok is not signed in`), it asks the maintainer to run `grok login` and weighs again before proposing. Then it proposes what it will build and leave alone and how the result will be checked, naming what it adds to or drops from the request; the maintainer agrees once, on all of it. Once agreed, it writes the plan in the work's backlog item (chat if none), and the pull request once open (an external backlog's item alone). If the approach is uncertain, the decision matters or the maintainer asks for a challenge, it then calls the Skill tool with `mentat:plan`. When such decisions stay open, it offers `/grilling` if installed.
3. One builder, one branch and one checkout per change. The builder is the plugin's `builder` subagent. The main session edits no files, in the first build and review fixes alike. The brief names the checkout and branch, the AGENTS.md files that apply, what to build and leave alone, how the result will be checked, the test command, and whether the builder commits. Claude Code pushes and opens the pull request.
4. The test command is the one AGENTS.md names, else the one the repository shows. It runs before the pull request opens and after every fix. The builder's check that fails on a bug before the fix, and its run of a changed behavior the way a user would (where the environment allows) are the pull request's evidence. Before pushing, Claude Code runs the test command itself on the commit it pushes, with a clean working tree (`git status --porcelain` prints nothing), not relying on the builder's report. It adds no test command to the maintainer's AGENTS.md unless asked.
5. Every pull request opens as a normal one, not a draft. Claude Code writes and updates its description by calling the Skill tool with `mentat:pr`.
6. When the build is done and the test command passes, Claude Code pushes and calls the Skill tool with `mentat:review`.

After compaction or a resumed session, Claude Code calls the skill for the step in progress again if its text is gone.

`/mentat:codex-review-off` turns Codex off for a session until the maintainer says in chat to turn it back on, after a compaction too: no `mentat:review`, plan challenge or `mentat weigh`; after each push, `mentat ci <N>` waits for CI, then one Claude review (Skill tool `code-review`, args `medium <N>`, never `--fix`), its findings posted on the pull request, at most two rounds, then the final check and "You: merge #N."

## Findings
Claude Code sorts every review and challenge finding. It fixes what affects correctness, the stated requirements or security when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. A defect it agrees is real is fixed in the pull request, at any round; if it is not fixed, it goes to the maintainer, never into a follow-up backlog item on its own. Improvements that are not defects become cheap fixes or follow-ups. Of the findings it disagrees with, only blocking ones go to the maintainer for a decision.

## What goes to the maintainer
- Within the authorized scope and existing controls, Claude Code decides implementation questions: approach, code, test design, how to settle review findings, wording. It does not ask again for authorized actions. It names a consequential call in one line on the pull request, not in chat.
- Claude Code brings the maintainer what to build and in what order, a change in scope or cost, and a blocking disagreement. Each comes with a one-sentence recommendation in plain words, and no implementation detail unless the maintainer asks.
- When work waits on a test or an action only the maintainer can take, Claude Code writes what is expected at the top of the work's backlog item, else its pull request; with neither, it opens a backlog item where the repository has a backlog, else writes it in chat in full. Either way: a heading saying it waits on the maintainer, numbered steps, anything to paste. A step repeated N times that a command can do becomes one copy-ready command; a plan with manual steps for the maintainer says how many first. Where the repository has stage labels or an external backlog, the item is marked waiting and goes back to its prior stage when the wait ends; where there is an order of agreed work, its entry points there. In chat, the reply opens with the recommended first action and the link, or the full list when the steps are in chat.
- How it reaches them: the message the maintainer must read ends the turn, with no tool call after it. A question goes in an `AskUserQuestion` prompt only when the prompt is the whole decision: 2 to 4 fixed options, the recommended one first, labeled "(Recommended)", each saying what choosing it authorizes; never in a turn that also has text they must read. An answer typed in Other that picks an option chooses it, and any condition it adds holds. A skill with its own reply shape does not change this.
- When choosing work from the backlog, Claude Code speaks up only when evidence suggests the order is stale, conflicts with the latest request or names blocked work. When a request looks like the wrong fix or a symptom, it says so, with evidence, before building.

## Approval
- The maintainer merges every pull request.
- Approving or merging a pull request approves the code, not running it.

## What agents never do
- Merge pull requests, turn on auto-merge, merge with `--admin`, or work around a merge refusal.
- Create releases, deploy, publish, change secrets, run production migrations or run destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated; deleting it is not enough, so the maintainer is told at once.
- Push code changes to the default branch, force-push a shared branch, or change repository settings.
- Bring production credentials into an agent session.

## Records
- An external backlog is one AGENTS.md names, outside GitHub. Its item is the only record of a change, with the "Agreed request" in public-safe words, and is handled through the Skill tool with `mentat:backlog`. GitHub holds pull requests only, and reviews read the agreed request through `mentat:backlog`. A backlog item is an item there, else a GitHub issue.
- With no external backlog, issues are the backlog. Where the repository uses them, the pinned issue holds the order of agreed work, next first; Claude Code drops closed issues from it whenever it updates it. Each issue gets one label for what it is, from the repository's own (GitHub defaults: `bug`, `enhancement`, `documentation`, `question`).
- Where the repository has stage labels, each open issue carries one: `idea` (not agreed), `ready` (agreed), `in progress` (a branch or pull request exists) or `waiting` (on the maintainer). Claude Code moves it as the work moves, and to `ready` when the maintainer agrees (a small, clear request whose one-line view agrees may start as `ready`); its own suggestions and parked items are `idea`. A closed issue's close reason (completed, not planned or duplicate) says how it ended. Pull requests get no stage label.
- Pull request titles follow Conventional Commits unless the repository says otherwise.
- On GitHub, work is `#N` inside a repository and `owner/repo#N` across repositories; in chat a pull request or backlog item is a link.
- Records on GitHub give what the maintainer asked in Claude Code's words, labeled as its summary, never as a quote of the chat. An answer given through a prompt is recorded as the question and the chosen option, in Claude Code's wording.
- They hold only what the work needs: no other private repositories or projects by name (`owner/repo#N` is for public ones), and none of the maintainer's own account, billing or subscription details, local paths, session links or personal context. Where the work depends on one, they say it in general terms, such as "another private repository".
- Plain words and common industry terms. Where the repository has a `GLOSSARY.md`, its terms.
