---
name: propose
description: "Step 2 of a change: the teammate's view, any grill, the decisions, the weigh, the proposal and the maintainer's agreement, the spec, and when to call mentat:plan. Use before giving a view on any request that may change a repository, and after a compaction or a resumed session while this step is in progress."
---

`rules.md` step 2 calls this skill before any view. Its standing lines there hold throughout.

A small, clear request (one line, nothing for the maintainer to decide, such as fixing a typo) gets a one-line view and waits for the maintainer's yes: no backlog read, grill, decisions, `mentat weigh` or `mentat:plan`. Steps 6 and 7 still apply. Every other request follows steps 1 to 8.

1. Claude Code reads the code and the open backlog's titles and opening sentences (read only), then gives a teammate's view (worth doing or not, the cost, a better way, overlapping items and the plan around them, with evidence).
2. For a new feature or workflow change, when several open decisions depend on each other, it may first offer a grill (`mentat:grill`) to ask them, at most once per request, and starts it only if the maintainer agrees.
3. Otherwise, or for any the grill leaves open, it asks only the decisions the maintainer can make now, never one already answered, and decides or defers the rest; one it does not need in order to go on goes as "How it reaches them" says (`rules.md` "What goes to the maintainer").
4. Then it runs `mentat weigh` on a file with the idea, answers (with any grill's record, as `mentat:grill` defines it) and deferred choices (not its own view) and shows the replies as `mentat:backlog` "Replies in chat" says, and goes on. A `DO IT` is not the maintainer's agreement; they may agree on partial results. Agreed work is not weighed again.
5. The maintainer agrees once, to a proposal saying in their terms what changes for them, what it adds to or drops from the request, and how the result will be checked; build detail goes in the spec, not chat.
6. Claude Code may propose a fast track (no Codex or Grok review) for a change that cannot alter what code does or what an agent is told; only the maintainer turns it on, and the spec records it with its reason.
7. Once agreed, it writes the spec (shape in `mentat:pr`) in the backlog item (chat if none) and, unless the backlog is external, the pull request once open.
8. If the approach is uncertain, the decision matters or the maintainer asks for a challenge, it calls the Skill tool with `mentat:plan`.
