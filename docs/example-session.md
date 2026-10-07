# An example session

*For people. Edited excerpts from one real session in this repository on 2026-10-06, while Mentat was being built with Mentat. Messages are shortened, and cuts are marked [...]. Nothing is reworded.*

The maintainer works in chat with Claude Code, the lead agent. Codex reviews each pull request on GitHub. Things to notice:

- The maintainer's messages are short: a pick, a yes, a correction.
- Claude Code brings each decision with its recommendation, and asks one question at a time.
- Review rounds run without the maintainer. They hear when a pull request is ready, or when something needs them.

## Deciding what to build, and a correction

**Maintainer:** thoughts on this skill ? https://www.aihero.dev/skills-pr

**Claude Code:** Most of this skill is already in Mentat. One idea is worth taking: the "merge danger" line. [...] Should I open an issue for that?

**Maintainer:** yes, open the issue. Stop being so overly confident that our skills do things better because, frankly, in my experience, what we have currently does not work well. [...]

**Claude Code:** I opened [ericfurspan/mentat#61](https://github.com/ericfurspan/mentat/issues/61) and labeled it `idea`. You were right, and I overstated how much Mentat already covers. Its rules for writing pull requests are scattered across steps 2, 5 and 7 of `rules.md`, the pull request template and the output style. I'd only checked that the topics showed up somewhere, not whether the pull requests come out well.

## A stall the maintainer caught

**Maintainer:** Where are we waiting on? I trusted that you would follow up, but it's been forty minutes and I see nothing happening.

**Claude Code:** You were waiting on me, and that's my fault. CI on bb9a7f7 had passed, but I had nothing set up to wake me when it finished, so I sat idle until your message. [...]

The underlying gap: Mentat says to wait for CI before reviewing, but nothing does the waiting. If `mentat review` waited for CI itself, the step would run without me having to remember it. Should I open an issue for that?

**Maintainer:** yes, open the issue

That issue became `mentat review` waiting for CI on its own.

## Review rounds and the hard stop

From [ericfurspan/mentat#70](https://github.com/ericfurspan/mentat/pull/70), which added `/mentat:retro`. Rounds 2 to 4 each found a real problem, fixed without the maintainer.

**Claude Code:** [ericfurspan/mentat#70](https://github.com/ericfurspan/mentat/pull/70) hit the five-round hard stop with one finding still open, so I've stopped.

Each round since round 2 found one more credential format that retro's redaction missed. Round 5's was a bare GitLab token (`glpat-...`) pasted without a label. Patching one format at a time won't end this.

I recommend one more fix. It would blank out any long string of letters and digits, which ends this whole class of finding. The cost is that retros would also lose commit IDs. Then one final review round.

Should I make that fix and run the extra round, past the five-round limit, on this pull request?

**Maintainer:** yes go ahead

**Claude Code:** [ericfurspan/mentat#70](https://github.com/ericfurspan/mentat/pull/70) is ready to merge. The extra round you approved found nothing on 511514a, CI passed, and every review thread is answered. I've posted the final check and requested your review.

**Maintainer:** merged 70

## A decision that is the maintainer's

**Claude Code:** #70 is merged and the plugin is updated in both checkouts. Next in #22 is agents merging (#50). It changes Mentat's biggest rule, so I need one decision from you before I plan it.

My recommendation is opt-in per repository. A one-line "agents may merge" in a repository's AGENTS.md would let the agent merge its own pull request after the final check, once the review loop ends ready and CI passes. [...]

Should it be opt-in per repository, or on everywhere by default?

**Maintainer:** i guess opt-in. what do you think?

**Claude Code:** I'd go with opt-in too. Merging can be harder to undo than it looks, depending on the repository. [...] Opt-in means you turn it on only in repositories where a merge is cheap to reverse, and every other repository keeps asking you.

## A plan, challenged by Codex

**Claude Code:** The plan for #50 is ready for your yes. [...]

Codex found three real gaps in my draft, and the plan now fixes each one:

| Codex's finding | Fix in the plan |
|---|---|
| `gh pr merge` can turn on auto-merge or join a merge queue instead of merging | The agent merges through GitHub's merge API, pinned to the exact commit Codex reviewed. It merges at once or refuses. |
| A stale local copy could still show an opt-in you'd removed | The opt-in line is read fresh from GitHub at merge time, for the repository being merged. |
| A changed head could still be reported as ready to merge | A refusal because the head moved sends the agent back to review. Any other refusal comes to you. |

[...] Should I build it?

**Maintainer:** yes, build it
