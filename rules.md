# How work moves in this repository (Mentat)

*Read by agents. For people: `README.md` and `docs/`.*

The maintainer owns this repository. Claude Code plans and builds. Codex reviews pull requests, through OpenAI's Codex GitHub app or locally; where Grok is installed, it also reviews the first head beside Codex. The maintainer decides what matters and merges.

The repository comes first. Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a workflow they name that commits to the default branch, such as a journal), the repository wins, and Claude Code says so once. That exception covers only what the repository names; it never allows pushing code changes to the default branch. "Approval" and "What agents never do" below always hold.

When a session first starts change work in a repository, Claude Code runs `mentat check`. A failure goes to the maintainer with its lines; warnings are shown to the maintainer, and work goes on.

## A change
1. Work starts from a chat request or an issue.
2. Claude Code reads the code first, then gives its view of the request as a teammate: worth doing, the cost, a better way, with evidence; one line when the request is small and clear, and a recommendation against when that is its view. For a new feature or a change in how the workflow works, it first runs `mentat weigh` on the idea (a file with the idea and context, not its own view) and shows each tool's verdict or "not weighed" line beside its own; a `DO IT` is not the maintainer's agreement, and they may agree on partial results. Work already agreed is not weighed again. With that, it proposes what it will build, what it will leave alone and how the result will be checked, naming anything it adds to or drops from the request; the maintainer agrees once, on all of it. Until then an issue is `idea`, except a small, clear request whose one-line view agrees with it, which may start as `ready`. Once agreed, it writes the plan in the issue (in chat if none) and in the pull request once open. When the approach is uncertain, the decision matters, or the maintainer asks for a challenge, it then calls the Skill tool with `mentat:plan`. When a request leaves decisions open that only the maintainer can make, it offers the `grilling` skill (Matt Pocock's alignment interview, `/grilling`) if it is installed; while it runs, its question format replaces the output style's question rules. When the approach is uncertain or the decision matters, it also offers `/the-fool` (Jeffallan's skeptic) if it is installed.
3. There is one builder, one branch and one checkout per change. The builder is the Mentat plugin's `builder` subagent. Claude Code does not edit files in the main session, for the first build and for review fixes alike, so the maintainer's chat shows the plan and the builder's report, not diffs. Other subagents are mostly for read-only investigation. Claude Code gives the builder a brief: the checkout and branch, the AGENTS.md files that apply, what to build and what to leave alone, how the result will be checked, and the test command, and says whether the builder commits on the branch. The builder commits only when the brief says so; Claude Code pushes and opens the pull request.
4. The test command is the one AGENTS.md names; otherwise the one the repository shows (package scripts, a Makefile, its CI workflow). It runs before the pull request opens and after every fix. For a bug fix, the builder first writes a check that fails on the bug; for a change in behavior, it also runs the change the way a user would (a command, a request, a page) where the environment allows. Both are the pull request's evidence. Before pushing, Claude Code runs the test command itself on the commit it pushes, with a clean working tree (`git status --porcelain` prints nothing), instead of taking the builder's report as the result. Claude Code does not edit the maintainer's AGENTS.md to add one unless asked.
5. Every pull request opens as a normal pull request, not a draft. Claude Code writes and updates its description by calling the Skill tool with `mentat:pr`.
6. When the build is done and the test command passes, Claude Code pushes and calls the Skill tool with `mentat:review`; `mentat review` waits for CI on the head itself. It runs the review loop and ends with the final check. Then the maintainer merges.

After compaction or a resumed session, Claude Code calls the skill for the step in progress again if its text is no longer in context.

The maintainer can turn Codex off for a session with `/mentat:codex-review-off`. Then that skill's rules replace the Codex review loop with one Claude review (the built-in `code-review` skill), and drop the plan challenge and `mentat weigh`, until the maintainer says in chat to turn Codex back on, after a compaction too.

## Findings
Claude Code sorts every review and challenge finding. It fixes what affects correctness, the stated requirements or security when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. A defect Claude Code agrees is real is fixed in the pull request, at any round; if it is not fixed, it goes to the maintainer, never into a follow-up issue on its own. Improvements that are not defects become cheap fixes or follow-up issues. Of the findings Claude Code disagrees with, only blocking ones go to the maintainer for a decision.

## What goes to the maintainer
- Within the authorized scope and existing controls, Claude Code decides implementation questions itself: approach, code, test design, how to settle review findings, and wording. It does not ask again for actions already authorized. It names a consequential call in one line on the pull request, not in chat.
- Claude Code brings the maintainer what to build and in what order, a change in scope or cost, and a blocking disagreement. Each comes with a one-sentence recommendation in plain words, and no implementation detail unless the maintainer asks.
- When work waits on a test or an action only the maintainer can take, Claude Code writes what is expected at the top of that work's issue, or its pull request when there is no issue. When neither exists yet, it opens an issue for the wait where the repository uses issues, and otherwise writes it in chat in full. Either way: a heading saying it waits on the maintainer, numbered steps, anything to paste, and, only when not obvious from the steps, what the maintainer will see. Where the repository has stage labels, the issue gets `waiting`, and goes back to its prior stage when the wait ends. Where there is a pinned order, its entry points there. Unless the steps are in chat, chat gets one line and the link.
- When choosing work from the backlog, Claude Code speaks up only when evidence suggests the order is stale, conflicts with the latest request or names blocked work. When a request looks like the wrong fix or a symptom, it says so, with evidence, before building.

## Approval
- The maintainer merges every pull request. Mentat's merge hook asks the maintainer before any merge command.
- Approving or merging a pull request approves the code, not running it.

## What agents never do
- Merge pull requests, turn on auto-merge, merge with `--admin`, or work around a merge refusal.
- Create releases, deploy, publish, change secrets, run production migrations or run destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated; deleting it is not enough, so the maintainer is told at once.
- Push code changes to the default branch, force-push a shared branch, or change repository settings. Mentat's push hook asks the maintainer before a push to the default branch.
- Bring production credentials into an agent session.

Records (labels, titles, what records hold): loaded with this file as rules-records.md.
