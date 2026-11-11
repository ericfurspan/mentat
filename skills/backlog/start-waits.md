# Start waits

A start wait is one line in an agreed item's description, in its item shape slot, opening `Starts after:`. It names one condition, in one of these forms:

- `Starts after: <item id> done`: that item ends completed, not canceled or duplicate. The tracker's adapter says how it reads this.
- `Starts after: <owner/repo>#<N> merged`: that pull request is merged.
- `Starts after: count <what> in <where> <opened|merged> after <YYYY-MM-DD> reaches <N>`: the number of `<what>` in `<where>` opened or merged after that date reaches `<N>`, read in full (every page).

Writing. Agreement in `mentat:propose` and a planning session in `mentat:plan` add the line in the same write that records that an agreed item must wait on one of these conditions. Writes to `## Current plan`, triage and the Linear adapter's refinement of hand-made items leave the line unchanged. A session that finds the wait met may remove the line when it next writes the item; nothing depends on that.

Reading. A session that decides whether an item can start reads its wait then, read-only. The wait is:

- met when its condition holds: the item can start as if it had no line;
- unmet while its condition does not hold, reported as "waits on <condition>";
- unchecked when a read it needs fails, reported as "could not check its wait: <why>";
- dead when the line matches no form, the prerequisite item ended canceled or duplicate, or the pull request closed without merging, reported by naming the item with `/mentat:plan <id>`.

An unmet, unchecked or dead wait holds the item: it is not offered, built or named as next. A session walking the order passes it, reports it as above and goes on to the next item. Once the wait is met, the item can start again with no write.
