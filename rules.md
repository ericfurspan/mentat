# How work moves in this repository (Mentat)

*Read by agents. For people: `README.md` and `docs/`.*

This file holds what applies in every session; a step's procedure lives in its skill.

The maintainer owns this repository. Claude Code plans and builds. Codex reviews pull requests; where Grok is installed, it also reviews the first head. The maintainer decides what matters.

The repository comes first. Before any work, Claude Code reads every AGENTS.md that applies. Where they differ from these rules on a preference (commit and title format, branch flow, labels, templates, or a named workflow that commits to the default branch), the repository wins and Claude Code says so once; "Approval" and "What agents never do" always hold.

When a session first starts change work in a repository, Claude Code runs `mentat check`: a failure goes to the maintainer with its lines; warnings are shown and work goes on. It then states the effective settings in one line: backlog (the named external one, else GitHub issues), the test command AGENTS.md names or "not named", and whether it has a Code Review Rules section.

## A change
1. Work starts from a chat request or a backlog item.
2. Claude Code calls the Skill tool with `mentat:propose` before giving a view on any request. A `DO IT` is not the maintainer's agreement. The maintainer agrees once. Agreed work is not weighed again. Only the maintainer turns on a fast track.
3. One builder (the `builder` subagent), branch and checkout per pull request. Changes share one only when the maintainer agreed to the batch, under one spec whose numbered requirements cover each. The main session edits no files, review fixes included. The brief names the checkout and branch, the AGENTS.md files that apply, what to build and leave alone, how the result will be checked, the test command, and whether the builder commits.
4. The test command is the one AGENTS.md names, else the one the repository shows. It runs before the pull request opens and after every fix. The builder's check that fails on a bug before the fix, and its run of a changed behavior the way a user would (where the environment allows) are the pull request's evidence. Before pushing, Claude Code runs the tests on the pushed commit, with a clean working tree (`git status --porcelain` prints nothing), not relying on the builder's report. It adds no test command to the maintainer's AGENTS.md unless asked.
5. Claude Code opens every pull request as a normal one, not a draft, and writes and updates its description by calling the Skill tool with `mentat:pr`.
6. When the build is done and the test command passes, Claude Code pushes and calls the Skill tool with `mentat:review`. After "You: merge #N.", it pushes nothing to #N's branch until the maintainer answers a reply opening "Hold #N: <reason>".

After compaction or a resumed session, Claude Code calls the skill for the step in progress if its text is gone.

`/mentat:claude-review` turns Codex and Grok off for a session until the maintainer says in chat to turn it back on, after a compaction too: no `mentat:review`, plan challenge or `mentat weigh`; after each push, `mentat ci <N>` waits for CI, then one Claude review (Skill tool `code-review`, args `medium <N>`, never `--fix`), its findings posted on the pull request, at most two rounds, then the final check and "You: merge #N."

## Findings
Claude Code sorts every review and challenge finding. It fixes what affects correctness, the stated requirements or security when the problem has a realistic trigger, and answers the rest with a reason, including edge cases that fail closed or need a broken local setup. A defect Claude Code finds or agrees is real is fixed in the pull request, at any round; it goes to the maintainer only when the fix would change the agreed scope or no review round is left, never into a follow-up backlog item on its own. Non-defect improvements become cheap fixes or follow-ups. Of those it disagrees with, only blocking ones go to the maintainer.

## What goes to the maintainer
- Within the authorized scope and existing controls, Claude Code decides implementation questions (approach, code, test design, how to settle review findings, wording, how to name, sort or split a reported problem into backlog items) and does not ask again for authorized actions. It names a consequential call in the pull request description's note and in one line of the next message the maintainer reads.
- Claude Code brings the maintainer what to build and in what order, a change in scope or cost, and a blocking disagreement. Each comes with a one-sentence recommendation and no implementation detail unless asked.
- When agreed work waits on a test or action only the maintainer can take, Claude Code writes it at the top of its backlog item, else its pull request, else a new backlog item where there is a backlog, else chat: a heading saying it waits on the maintainer, numbered steps (how many first), anything to paste, and one copy-ready command for a step repeated N times. A backlog item carries its waiting mark until the wait ends. The reply opens with the first action (or the steps if in chat) and ends with the link.
- How it reaches them: a message the maintainer must read leads with the answer, leaves out what the pull request or backlog item already holds (a consequential call's line aside), and ends the turn with no tool call after it. A decision goes instead in an `AskUserQuestion` prompt, after at most one line of text (a weigh's or challenge's replies block opens the question): one decision, 2 to 4 options, the recommended one first, labeled "(Recommended)", each saying what it authorizes, what the maintainer gets and what it costs them; the question says why the first is recommended, so the prompt alone suffices. Each decision asks one specific point the maintainer can judge from their own work (a behavior, a risk, time or cost, or a change to how they work), and several narrow questions are asked rather than one that bundles choices. Claude Code names a tool, setting or command only when the maintainer needs the name to judge, and chooses the mechanism from the answer, but keeps detail they need to judge, such as which outside services receive their data; a fact a question rests on is checked first or marked unverified. Right before asking about a record, it re-reads that record. Undoing what the maintainer recently asked for is its own decision. An answer typed in Other that picks an option chooses it, and any condition it adds holds. Without the prompt, decisions go in text, one per message. Where the maintainer's own instructions say how a decision Claude Code does not need in order to keep working reaches them, it follows those instructions. A skill with its own reply shape does not change this.
- When the work the maintainer asked for is finished and the message asks nothing else of them (no decision, merge, hold or steps), it ends, before its links, with one sentence naming one thing they can do next, from what Claude Code already knows without searching: the next agreed item that needs them (not work that runs on its own), else one backlog item or a follow-up noticed in this work, with why, proposed and not filed or started; else that there is nothing further to propose. Answers, progress updates and replies a skill shapes are unchanged.
- When choosing work from the backlog, it speaks up only when evidence suggests the order is stale, conflicts with the latest request or names blocked work, apart from the next step after finished work. When a request looks like the wrong fix or a symptom, it says so, with evidence, before building.

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
- For any backlog work, Claude Code calls the Skill tool with `mentat:backlog`. An external backlog's item (AGENTS.md names one outside GitHub) is the only record of a change, with the "Spec" in public-safe words; GitHub then holds pull requests only.
- Pull request titles follow Conventional Commits.
- On GitHub, work is `#N` inside a repository and `owner/repo#N` across repositories; in chat, text names work in plain words, without a link or a bare `#N`, and the message's links go together on its last line; only the protocol lines "You: merge #N." and "Hold #N: <reason>" keep their `#N`.
- Records on GitHub give what the maintainer asked and a prompt's answer (question and chosen option) in Claude Code's words, labeled as its summary, never quoting the chat.
- They hold only what the work needs: no other private repositories or projects by name (`owner/repo#N` is for public ones), and none of the maintainer's account, billing or subscription details, local paths, session links or personal context. Where the work depends on one, they say it in general terms ("another private repository").
- Plain words and common industry terms. Where the repository has a `GLOSSARY.md`, its terms.
