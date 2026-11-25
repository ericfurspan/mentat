# Merging its own pull request

Read this, part of `SKILL.md` in this folder, once the final check allows Ready, before the Ready line goes out, and again after a compaction or resume. The Ready message is decided by then, its sentences included.

Where the repository turns on `MENTAT_AGENT_MERGE` (`docs/settings.md`), the session merges its own pull request, never another's. Run `mentat agent-merge <N>` once. It merges only when all hold:

- it prints `agent merge: on`;
- #N is a pull request this session opened;
- the Ready message would carry none of the sentences "Final check" adds after the first line (a fast track, a weaker review, a removal or reversal of what the maintainer asked for, a blocking finding answered instead of fixed, advice against the item);
- no `AGENTS.md` that applies keeps this merge for the maintainer;
- #N's head is the one the review covered: `mentat status <N>` says `head reviewed: yes` for the head `gh pr view <N> --json headRefOid` gives.

Then run `gh pr merge <N> --merge --match-head-commit <the head's full 40-character commit>` once, as the whole command: no other flag (`--auto` and `--admin` included), no other command beside it. If the hook denies it or it fails, say so in one line, send the Ready line, and stop: the maintainer merges, and the session neither retries nor tries another form.

Merged, #N gets the line "Merged: #N (<item id>)", without the parentheses when #N has no item, in place of the Ready line; a session no other session started then does the steps `after-ready.md` gives for a merged #N, and a started one does them first and sends the line with its after-merge reply. It is no Ready line, so it gets no push.

In every other case the Ready line goes out as "Final check" gives it, and, when `mentat agent-merge` printed `agent merge: waits for the maintainer (<reasons>)` or failed, with one more sentence, "Waits for the maintainer: <reasons>.", naming the reasons it printed or that it could not be read. With `agent merge: off` it adds nothing. An open manual check (`ready-gate.md`) is no Ready, so nothing merges.

After a compaction or resume between the final check and the merge, run the final check and this again: a #N already merged goes to the merged steps, a closed one to nothing, and a head that moved to a new review (`SKILL.md` step 1).

In a session another session started, the Merged line goes to its starting session with the after-merge reply (`after-ready.md`), in one message, after the steps. Inside a `mentat:build` run, the merge happens right after the item's final check, and the run goes on as after any merge.
