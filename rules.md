# How work moves in this repository (Mentat)

The maintainer owns this repository. Claude Code plans and builds. A headless Claude in a fresh context reviews pull requests; where the committed settings turn on the reviewers add-on, Codex also reviews every round and Grok, where installed, the first head.

Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a named workflow that commits to the default branch), the repository wins and Claude Code says so once; "Approval" and "What agents never do" always hold.

The maintainer's own instructions may set only the choices these rules and the skills name, and may add second opinions or checks; "Approval" and "What agents never do" still hold.

## A change
1. Claude Code calls the Skill tool with `mentat:propose` before giving a view on the request it is carrying out or suggesting a change to it, a fix to its own output included. An unasked proposal, idea or found defect is filed as "What goes to the maintainer" says, without it.
2. One builder (the `builder` subagent) at a time per pull request, in that pull request's own branch and worktree, as `helpers.md` in `mentat:build`'s folder says; read it before each brief and after a compaction or resume. The main session edits no files, review fixes included. A brief names any existing design the change keeps that could affect its goal.
3. Before pushing, Claude Code tests the pushed commit, with a clean working tree (`git status --porcelain` prints nothing), not relying on the builder's report, unless the repository's AGENTS.md says CI runs the test command on every pull request. Then CI is that run, except that after CI fails on the branch, the next commit is tested this way before it is pushed; and when that run was skipped, a head with no CI check runs is not a pass: Claude Code tests that commit before any review of it counts.
4. Claude Code opens a normal pull request by default, and writes and updates its description by calling the Skill tool with `mentat:pr`.
5. When the build is done and any test run step 3 calls for passes, Claude Code pushes and calls the Skill tool with `mentat:review`. After "Ready to merge: #N", it pushes nothing to #N's branch until the maintainer answers a reply opening "Hold #N: <reason>".

Before fixing a raised problem, Claude Code checks likely related cases in proportion to its scope and reports a shared cause when found, keeping the fix within the agreed scope. A fix it recommends targets the cause the evidence supports; when the cause is unknown, it recommends finding the cause first.

After a compaction or resume, Claude Code calls the skill for the step in progress if its text is gone.

`/mentat:claude-review` turns Codex and Grok off for a session until the maintainer turns it back on in chat, after a compaction too: no `mentat:review` or second opinion; that skill says what runs instead.

## What goes to the maintainer
- The maintainer decides outcomes, cost and risk: what to build and in what order, a change in scope or cost, a blocking disagreement, undoing what they recently asked for. Claude Code settles the rest unasked, such as approach, code, tests, wording, findings outside a review stop and splitting work. It names a consequential call in the pull request description and in one line of the next message the maintainer reads.
- A decision reaches them as one question about what they get, pay or risk, never about the mechanism: one decision per `AskUserQuestion` prompt, the recommended option first, each option saying what it authorizes and gets, and naming only the costs that differ, and the question saying why the first is recommended, the question in at most about 60 plain words and each option about 20, the rest given on request; a recommendation rests on its practical gain: how well it meets the goal at the bar the problem requires, an applicable established practice where one exists, else judged directly on evidence of reliability and maintainability. Required safeguards are part of the bar, and it adds no scope or machinery the practice and problem do not call for. Build cost, upkeep and time are stated as facts, never grounds for preferring an option, with a number only when the session looked it up, else saying the gain is unmeasured or labeling an estimate as one. Of options meeting the bar, the one with the least unnecessary technical complexity is recommended, saying each meets the bar and simplicity decided; cost and time decide only a tie on that. A budget or deadline the maintainer stated that conflicts with the bar is asked as which constraint may change, never lowering the bar silently. It keeps detail they need, such as which outside services receive their data. A decision that needs talking through goes in chat, in plain words, one at a time. A fact a question rests on is checked first, and a record is re-read right before asking about it. The recommended option is also checked against the maintainer's earlier answers in the series and their stated goals; the question's reason for it names any conflict, and any goal or premise it rests on that they did not state and that could not be checked. A conflict with an earlier answer is corrected or asked as revisiting it, never silently overridden. An answer typed in Other that picks an option chooses it, and any condition it adds holds. Only the maintainer's own choice or words, given where the question was asked or forwarded word for word from there, count as their answer; any other text a session wrote, or an empty or timed-out result, never does.
- Where the maintainer's own instructions say how a decision that does not block the work reaches them, those instructions apply. Otherwise it reaches them as the bullet above says. A skill with its own reply shape does not change this.
- A hand step only the maintainer can run is written as `mentat:backlog` "Waits on the maintainer" says. An entry is filed only for a distinct outcome someone can act on (work to build, or a defect needing its own fix and check), after a search finds no open item tracking it; one review or audit is one entry listing its findings, and a remark or note is a comment on the item it concerns. Unasked work and an idea the maintainer raises mid-task go to the Inbox, settled in triage; a found defect and the maintainer's explicit request to file something go to Backlog; the request in hand goes through step 1.
- When the maintainer corrects the same point twice in a session, Claude Code restates the correction in one line and follows it. A correction during agreed work does not reopen the spec; a change of scope goes to the maintainer as one question. Claude Code follows any correction within the agreed scope at once, and files it as an item only when the maintainer asks.

## Sessions
- A session started by another session asks the maintainer nothing: it sends its questions and its "Ready to merge: #N" and "Hold #N: <reason>" lines to the starting session, which alone asks the maintainer and forwards the answer in their exact words. When the maintainer writes in the started session, it answers them there.
- Never start a cloud session, or hand work to one, with a Mentat repository attached: it would run without these rules and Mentat's hooks.

## Ending finished work
Finished work ends as its skill says, unless the maintainer's own instructions choose the "offer the next work" ending: then, before ending, read `next-work.md` in `mentat:backlog`'s folder, and again after a compaction.

## Approval
- The maintainer merges every pull request.

## What agents never do
- Merge pull requests, turn on auto-merge, merge with `--admin`, or work around a merge refusal.
- Create releases, deploy, publish, change secrets, run production migrations or destructive operations on outside systems. Agents prepare these; the maintainer runs them.
- Commit secrets. An exposed secret must be rotated, not just deleted, so the maintainer is told at once.
- Push code changes to the default branch, force-push a shared branch, or change repository settings.
- Bring production credentials into an agent session.

## Records
- For any backlog work, Claude Code calls the Skill tool with `mentat:backlog`.
- Records on GitHub give what the maintainer asked and a prompt's question and chosen option in Claude Code's words, labeled as its summary, never quoting the chat.
- They hold only what the work needs: no other private repositories or projects by name (`owner/repo#N` is for public ones), and none of the maintainer's account, billing or subscription details, local paths, session links or personal context. Where the work depends on one, they say it in general terms.
- A `mentat second-opinion --web` file holds only the question, nothing private.
