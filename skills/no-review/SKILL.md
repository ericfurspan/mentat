---
name: no-review
description: "Turns Codex off for the rest of the session: no pull request reviews and no plan challenges. Started by the maintainer."
disable-model-invocation: true
---

The maintainer has turned Codex off for the rest of this session. Until they turn it back on in chat, these replace the review loop (`mentat:review`) and the plan challenge (`mentat:plan` step 2). Everything else in `rules.md` holds. After a compaction or a resumed session, Codex stays off; only the maintainer turns it back on.

When started, say in one line that Codex is off for this session. If a `mentat review` or `mentat challenge` is running, stop it and say so.

## Pull requests

1. Do not call `mentat:review` or run `mentat review` or `mentat review --local`.
2. Once the test command passes on the head, push and update the description (Skill tool, `mentat:pr`). Its Evidence says the pull request was not reviewed because the maintainer turned Codex off for this session.
3. Run `mentat ci <N>`, which waits for CI on the head (up to 30 minutes; with no CI, about a minute) and reviews nothing. 0: go on. 3: the head moved; run it again. 4: failing checks: fix them, run the test command, push, and run it again; CI still running at the timeout: tell the maintainer. 1: tell the maintainer.
4. Read the diff and the description from GitHub, not from memory, and correct any claim that does not hold. Post one comment, five lines at most: the commit checked and its test and CI results, "Not reviewed: Codex turned off by the maintainer", what was not checked, and what most deserves the maintainer's eyes. Start it with `Final check on <sha>`, the commit checked, so the Mentat band can find it.
5. Run `gh pr ready <N>`; if that fails, report it and stop. Tell the maintainer in chat that the pull request is ready to merge, unreviewed, and stop.

Never merge, even where the repository's AGENTS.md says agents may merge their own pull requests: that permission needs a review loop that ended ready, and none ran. The maintainer merges.

If OpenAI's Codex GitHub app is installed with automatic reviews, it may still review when the pull request is marked ready; that is the app's setting, not Mentat's. Tell the maintainer this once, the first time it applies. Do not wait for or act on such a review unless the maintainer asks.

## Plans

When `rules.md` step 2 calls for `mentat:plan`, still write the plan, but do not run `mentat challenge`. The handoff says the plan was not challenged because the maintainer turned Codex off.
