# An example session

*For people. Edited excerpts from one real session in this repository on 2026-10-06, while Mentat was being built with Mentat. Messages are shortened, and cuts are marked [...]. Nothing is reworded, except that the name of a private repository is replaced in brackets.*

The maintainer works in chat with Claude Code, the lead agent. Codex reviews each pull request on GitHub. Things to notice:

- The maintainer's messages are short: a pick, a yes, a correction.
- Claude Code brings each decision with its recommendation, and asks one question at a time.
- Review rounds run without the maintainer. They hear when a pull request is ready, or when something needs them.

## Deciding what to build, and a correction

**Maintainer:** thoughts on this skill ? https://www.aihero.dev/skills-pr

**Claude Code:** Most of this skill is already in Mentat. One idea is worth taking: the "merge danger" line. I wouldn't install the skill itself. [...] If you want the merge-danger line, I'd add one line to the template and to the final-check comment. Should I open an issue for that?

**Maintainer:** yes, open the issue. Stop being so overly confident that our skills do things better because, frankly, in my experience, what we have currently does not work well. [...]

**Claude Code:** I opened [ericfurspan/mentat#61](https://github.com/ericfurspan/mentat/issues/61) and labeled it `idea`. You were right, and I overstated how much Mentat already covers. Its rules for writing pull requests are scattered across steps 2, 5 and 7 of `rules.md`, the pull request template and the output style. I'd only checked that the topics showed up somewhere, not whether the pull requests come out well.

## A stall the maintainer caught

**Maintainer:** Where are we waiting on? I trusted that you would follow up, but it's been forty minutes and I see nothing happening.

**Claude Code:** You were waiting on me, and that's my fault. CI on bb9a7f7 had passed, but I had nothing set up to wake me when it finished, so I sat idle until your message. [...]

The underlying gap: Mentat says to wait for CI before reviewing, but nothing does the waiting. If `mentat review` waited for CI itself, the step would run without me having to remember it. Should I open an issue for that?

**Maintainer:** yes, open the issue

The fix was built next. On its own pull request:

**Claude Code:** The new CI wait worked on its own pull request: round 1 logged "Waiting for CI on ee3c39f" and started the review once CI passed. Codex then found a real P1. A push during the wait could still get the app to review a commit that hadn't passed CI. I fixed it in e7b8bc2 with a new test, and round 2 is running now, waiting for CI first.

## Review rounds and the hard stop

From [ericfurspan/mentat#70](https://github.com/ericfurspan/mentat/pull/70), which added `/mentat:retro`. Each message arrived on its own while the maintainer did other things.

**Claude Code:** Codex round 2 on #70 raised a real P1: retro read whole session logs, so a credential in an old session would get pulled into the new one. I fixed it in 8521061. [...] Round 3 is running in the background.

**Claude Code:** Codex raised another valid P1 on #70: pattern matching missed some secret formats, like AWS secret keys. Rather than chase patterns, I took its suggestion to leave risky content out entirely. [...]

**Claude Code:** Round 4 on #70 found one more P1: a failed command's error text could still carry a credential into the transcript. I fixed it in edbdecd. [...] Round 5 is running, and it's the last one allowed. If it still finds problems, I'll stop and bring them to you instead of fixing further.

**Claude Code:** [ericfurspan/mentat#70](https://github.com/ericfurspan/mentat/pull/70) hit the five-round hard stop with one finding still open, so I've stopped.

Each round since round 2 found one more credential format that retro's redaction missed. Round 5's was a bare GitLab token (`glpat-...`) pasted without a label. Patching one format at a time won't end this.

I recommend one more fix. It would blank out any long string of letters and digits, which ends this whole class of finding. The cost is that retros would also lose commit IDs. Then one final review round.

Should I make that fix and run the extra round, past the five-round limit, on this pull request?

**Maintainer:** yes go ahead

**Claude Code:** [ericfurspan/mentat#70](https://github.com/ericfurspan/mentat/pull/70) is ready to merge. The extra round you approved found nothing on 511514a, CI passed, and every review thread is answered. I've posted the final check and requested your review.

The part most worth your eyes is `skills/retro/transcript`, since it decides what a retro can see. [...]

**Maintainer:** merged 70

## A decision that is the maintainer's

**Claude Code:** #70 is merged and the plugin is updated in both checkouts. Next in #22 is agents merging (#50). It changes Mentat's biggest rule, so I need one decision from you before I plan it.

My recommendation is opt-in per repository. A one-line "agents may merge" in a repository's AGENTS.md would let the agent merge its own pull request after the final check, once the review loop ends ready and CI passes. The merge hook would stop asking where that line exists and keep asking everywhere else. [...]

Should it be opt-in per repository, or on everywhere by default?

**Maintainer:** i guess opt-in. what do you think?

**Claude Code:** I'd go with opt-in too. Merging can be harder to undo than it looks, depending on the repository. If [another repository] deploys whenever something merges to `master`, an agent's merge there ships to production, and a revert doesn't take that back. Opt-in means you turn it on only in repositories where a merge is cheap to reverse, and every other repository keeps asking you.

Next I'll write the plan for #50 on that basis, have Codex challenge it, and bring it to you before building.

## A plan, challenged by Codex

**Claude Code:** The plan for #50 is ready for your yes. [...]

Codex found three real gaps in my draft, and the plan now fixes each one:

| Codex's finding | Fix in the plan |
|---|---|
| `gh pr merge` can turn on auto-merge or join a merge queue instead of merging | The agent merges through GitHub's merge API, pinned to the exact commit Codex reviewed. It merges at once or refuses. |
| A stale local copy could still show an opt-in you'd removed | The opt-in line is read fresh from GitHub at merge time, for the repository being merged. |
| A changed head could still be reported as ready to merge | A refusal because the head moved sends the agent back to review. Any other refusal comes to you. |

Codex also pointed out you can keep required approvals. You approve, then the agent merges.

Should I build it?

**Maintainer:** yes, build it

Two review rounds later, each fixing a real P1:

**Claude Code:** [ericfurspan/mentat#71](https://github.com/ericfurspan/mentat/pull/71) is ready to merge. Codex found nothing on db169d6 in round 3, and CI passed there. Both earlier P1s are fixed: the merge has to be pinned to the reviewed commit, and it must be a pull request the agent's own account opened. I've posted the final check and requested your review.

The part most worth your eyes is the one exception in `hooks/no-merge`. Merging this changes nothing anywhere until a repository adds the opt-in line.

**Maintainer:** Merged
