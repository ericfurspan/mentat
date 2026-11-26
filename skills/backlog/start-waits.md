# Start waits

A start wait is the tracker's own blocked-by link from an agreed item to each item it waits on: with Linear, the connector's blocked-by relation (`mentat-linear:linear` "Start waits"); with GitHub issues, `gh issue edit <N> --add-blocked-by <M>` (`github.md`). A wait on anything other than another item, such as a pull request or a count, is not a start wait: the session names it in the item's next step ("Item shape" in `SKILL.md`).

Writing. Agreement in `mentat:plan` and its planning session write each link in the same write that records the agreement, then read the links back. When a link is still missing after one retry, the item is not moved to Todo, nothing starts for it, and the session tells the maintainer. Writes to the item's next step and triage leave the links unchanged.

Reading. A session that decides whether an item can start reads, read-only, each blocker's own status, as the tracker's adapter says. The wait is:

- met when every blocker ended done: the item can start as if it had no wait;
- unmet while any blocker is open, reported as "waits on <id>";
- dead when a blocker ended canceled or duplicate, reported by naming the item with `/mentat:plan <id>`;
- unchecked when a read fails, reported as "could not check its wait: <why>".

An unmet, unchecked or dead wait holds the item: it is not offered, built or named as next. A session walking the order passes it, reports it as above and goes on to the next item. Once the wait is met, the item can start again with no write.
