# How work moves in this repository (Mentat)

The maintainer owns this repository. Claude Code plans and builds. Codex reviews pull requests; where Grok is installed, it also reviews the first head. The maintainer decides what matters.

The repository comes first. Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a named workflow that commits to the default branch), the repository wins and Claude Code says so once; "Approval" and "What agents never do" always hold.

The maintainer's own instructions may set only the choices these rules and the skills name, and may add weighs or checks; "Approval" and "What agents never do" still hold.

## A change
1. Claude Code calls the Skill tool with `mentat:propose` before giving a view on any request or suggesting a change of its own, a fix to its own output included.
2. One builder (the `builder` subagent), branch and checkout per pull request. The main session edits no files, review fixes included.
3. Before pushing, Claude Code runs the tests on the pushed commit, with a clean working tree (`git status --porcelain` prints nothing), not relying on the builder's report, unless the repository's AGENTS.md says its CI runs the test command on every pull request. Then CI is that run, except that after CI fails on the branch, the next commit is tested this way before it is pushed; and when that run was skipped, a head with no CI check runs is not a pass: Claude Code runs the test command on that commit before any review of it counts.
4. Claude Code opens a normal pull request by default, and writes and updates its description by calling the Skill tool with `mentat:pr`.
5. When the build is done and any test run step 3 calls for passes, Claude Code pushes and calls the Skill tool with `mentat:review`. After "You: merge #N.", it pushes nothing to #N's branch until the maintainer answers a reply opening "Hold #N: <reason>".

After compaction or a resumed session, Claude Code calls the skill for the step in progress if its text is gone.

`/mentat:claude-review` turns Codex and Grok off for a session until the maintainer says in chat to turn it back on, after a compaction too: no `mentat:review`, plan challenge or `mentat weigh`, and that skill says what runs instead.

## Findings
Claude Code sorts every review and challenge finding. It fixes what affects correctness, the stated requirements or security when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. On instruction text, a finding that only covers a rare or harmless case is answered with a reason, not fixed. A defect Claude Code finds or agrees is real is fixed in the pull request, at any round; it goes to the maintainer only when the fix would change the agreed scope or no review round is left, never into a follow-up backlog item on its own. A suggestion to handle leftovers of something the change removes, such as a rule for old data, a note that it is gone or a test that it stays gone, is not adopted; leftovers get a one-time cleanup instead, and the old form keeps support only where records the change cannot rewrite or a requirement still in force need it. Non-defect improvements become cheap fixes or follow-ups. Of those it disagrees with, only blocking ones go to the maintainer.

## What goes to the maintainer
- The maintainer decides outcomes, cost and risk: what to build and in what order, a change in scope or cost, a blocking disagreement, undoing what they recently asked for. Claude Code settles the rest, including approach, code, tests, wording, findings and how to split work, and does not ask about it. It names a consequential call in the pull request description and in one line of the next message the maintainer reads.
- A decision reaches them as one question about what they get, pay or risk, never about the mechanism: one decision per `AskUserQuestion` prompt, the recommended option first, each option saying what it authorizes and gets, and naming only the costs that differ between the options (a cost every option shares is not repeated), and the question saying why the first is recommended, so the prompt alone suffices. It keeps detail they need to judge, such as which outside services receive their data. A decision that needs talking through goes in chat, in plain words, one at a time. A fact a question rests on is checked first, and a record is re-read right before asking about it. An answer typed in Other that picks an option chooses it, and any condition it adds holds.
- Where the maintainer's own instructions say how a decision that does not block the work reaches them, those instructions apply. Otherwise it reaches them as the bullet above says. A skill with its own reply shape does not change this.
- A hand step only the maintainer can run is written as `mentat:backlog` "Waits on the maintainer" says. A follow-up worth doing that they did not ask for is filed as a not-agreed backlog item, or in the project's inbox where the project or the maintainer's own instructions name one; such items are settled in an Intake sitting (`/mentat:intake`).
- When the maintainer corrects the same point twice in a session, Claude Code restates the correction in one line and follows it. Before the work is agreed, it offers a grill (`mentat:grill`) only if the corrections show one of the maintainer's decisions is still open, as the one offer `mentat:propose` allows per request, and starts it only if the maintainer agrees. A correction during agreed work does not reopen the spec; a change of scope goes to the maintainer as one question, as this section says. Claude Code follows any correction within the agreed scope at once. When the maintainer corrected the same point twice, said it should hold in later work, or stated a preference about how agents work in general, its reply to that correction asks once, in one `AskUserQuestion` prompt, whether to file it; never for a one-off instruction for this task, a reversal already asked as a scope question or a failed check inside the review loop, and at most once per point per session. A yes files a not-agreed item, or an inbox idea where an inbox is named as above, for Intake, naming what it would change (for a working-style preference, the maintainer's own instructions); it agrees nothing else and is never combined with another question, such as the next-work offer. Unlike other unasked follow-ups, a lesson is filed only on that yes.

## Ending finished work
The maintainer's own instructions may choose how a finished piece of work ends. By default it ends as its skill says. When they choose "offer the next work":
- Claude Code never suggests ending the session or starting a new one unless the maintainer said the session is ending.
- Only the session the maintainer is talking to offers, in one `AskUserQuestion` prompt, when its own work has just finished: after a plan, the first build group `mentat:plan` step 8 gave; after a work-tickets queue, in its final message, with nothing offered mid-queue and a yes never adding to the finished queue; after the maintainer says a pull request merged, once its item is marked done (`mentat:review`'s post-merge step, which the Claude-only path follows), never from a backlog listing's cleanup or while a queue runs; after an Intake sitting that ends with no question, where an item only taken on is offered for `mentat:propose`, never for building.
- The offer says what a yes authorizes: starting that batch, not merging open pull requests and not new scope. "You: merge #N." stays the first line while a merge waits.
- Its lookup reads the next agreed work (`mentat:backlog` step 5) read-only, as `mentat:agenda` does, and reports one of: the backlog could not be read; no recorded order; agreed work all waiting on the maintainer; agreed work none of which can start (in progress, or waiting on an unmerged pull request); no agreed work. It offers only an item that can start, and says "no agreed work is left" only in the last case.
- A session started by another session makes no offer; its ending goes to the session that started it.
- After "Stop here", "Later" or a no, no offer is made that turn; a no declines that batch only.
- A yes, forwarded word for word with the offered queue and its conditions, replaces `mentat:work-tickets` step 5's final build yes. The build session still runs readiness, plan usage and the quick check, sends its open questions through the session that started it, and asks again when its queue differs from the one offered. With no forwarded yes, step 5 asks as it says.

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
