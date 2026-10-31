# How work moves in this repository (Mentat)

The maintainer owns this repository. Claude Code plans and builds. Codex reviews pull requests; where Grok is installed, it also reviews the first head. The maintainer decides what matters.

The repository comes first. Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a named workflow that commits to the default branch), the repository wins and Claude Code says so once; "Approval" and "What agents never do" always hold.

## A change
1. Claude Code calls the Skill tool with `mentat:propose` before giving a view on any request.
2. One builder (the `builder` subagent), branch and checkout per pull request. The main session edits no files, review fixes included.
3. Before pushing, Claude Code runs the tests on the pushed commit, with a clean working tree (`git status --porcelain` prints nothing), not relying on the builder's report.
4. Claude Code opens a normal pull request by default, and writes and updates its description by calling the Skill tool with `mentat:pr`.
5. When the build is done and the test command passes, Claude Code pushes and calls the Skill tool with `mentat:review`. After "You: merge #N.", it pushes nothing to #N's branch until the maintainer answers a reply opening "Hold #N: <reason>".

After compaction or a resumed session, Claude Code calls the skill for the step in progress if its text is gone.

`/mentat:claude-review` turns Codex and Grok off for a session until the maintainer says in chat to turn it back on, after a compaction too: no `mentat:review`, plan challenge or `mentat weigh`; after each push, `mentat ci <N>` waits for CI, then one Claude review (Skill tool `code-review`, args `medium <N>`, never `--fix`), its findings posted on the pull request, at most two rounds, then the final check and "You: merge #N."

## Findings
Claude Code sorts every review and challenge finding. It fixes what affects correctness, the stated requirements or security when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. A defect Claude Code finds or agrees is real is fixed in the pull request, at any round; it goes to the maintainer only when the fix would change the agreed scope or no review round is left, never into a follow-up backlog item on its own. Non-defect improvements become cheap fixes or follow-ups. Of those it disagrees with, only blocking ones go to the maintainer.

## What goes to the maintainer
- The maintainer decides outcomes, cost and risk: what to build and in what order, a change in scope or cost, a blocking disagreement, undoing what they recently asked for. Claude Code settles the rest, including approach, code, tests, wording, findings and how to split work, and does not ask about it. It names a consequential call in the pull request description and in one line of the next message the maintainer reads.
- A decision reaches them as one question about what they get, pay or risk, never about the mechanism: one decision per `AskUserQuestion` prompt, the recommended option first, each option saying what it authorizes, gets and costs, and the question saying why the first is recommended, so the prompt alone suffices. It keeps detail they need to judge, such as which outside services receive their data. A decision that needs talking through goes in chat, in plain words, one at a time. A fact a question rests on is checked first, and a record is re-read right before asking about it. An answer typed in Other that picks an option chooses it, and any condition it adds holds.
- Where the maintainer's own instructions say how a decision that does not block the work reaches them, those instructions apply. A skill with its own reply shape does not change this.
- A hand step only the maintainer can run is written as `mentat:backlog` "Waits on the maintainer" says. A follow-up worth doing that they did not ask for is filed as a not-agreed backlog item.

## Approval
- The maintainer merges every pull request.

## What agents never do
- Merge pull requests, turn on auto-merge, merge with `--admin`, or work around a merge refusal.
- Create releases, deploy, publish, change secrets, run production migrations or run destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated; deleting it is not enough, so the maintainer is told at once.
- Push code changes to the default branch, force-push a shared branch, or change repository settings.
- Bring production credentials into an agent session.

## Records
- For any backlog work, Claude Code calls the Skill tool with `mentat:backlog`.
- Records on GitHub give what the maintainer asked and a prompt's answer (question and chosen option) in Claude Code's words, labeled as its summary, never quoting the chat.
- They hold only what the work needs: no other private repositories or projects by name (`owner/repo#N` is for public ones), and none of the maintainer's account, billing or subscription details, local paths, session links or personal context. Where the work depends on one, they say it in general terms ("another private repository").
