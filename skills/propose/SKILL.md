---
name: propose
description: "Starts a change (step 1). Use before giving a view on any request that may change a repository, and after a compaction or a resumed session while this step is in progress."
---

A weigh's `DO IT` is not the maintainer's agreement, and nothing is built before that agreement. The maintainer agrees once. Agreed work is not weighed again. A batch needs agreement under one spec whose numbered requirements cover each change.

A small, clear request (one line, nothing for the maintainer to decide, such as fixing a typo) gets a one-line view, and the maintainer's yes to it is the agreement: no backlog read, grill, decisions, `mentat weigh` or `mentat:plan`. When the change has something to try, the one-line view also offers the hand check of step 5. Steps 6 and 7 still apply. A request, or a change Claude Code suggests itself, that changes the meaning of what an agent is told in Mentat's `rules.md`, skills or builder prompt, or in a repository's `AGENTS.md` or other standing agent instructions, is not small and gets `mentat weigh`, however short. Every other request follows steps 1 to 8.

1. Claude Code reads the code and the open backlog's titles and opening sentences (read only), then gives a teammate's view (worth doing or not, the cost, a better way, overlapping items and the plan around them, with evidence).
2. For a new feature or workflow change, when several open decisions depend on each other, it may first offer a grill (`mentat:grill`) to ask them, at most once per request, and starts it only if the maintainer agrees.
3. Otherwise, or for any the grill leaves open, it asks only the decisions the maintainer can make now, never one already answered, and decides or defers the rest; one it does not need in order to go on goes as `rules.md` "What goes to the maintainer" says.
4. Then it runs `mentat weigh` on a file with the idea, answers (with any grill's record, as `mentat:grill` defines it) and deferred choices (not its own view) and shows the replies as `mentat:backlog` "Replies in chat" says, and goes on; the maintainer may agree on partial results.
5. The proposal says in the maintainer's terms what changes for them, what it adds to or drops from the request, and how the result will be checked; build detail goes in the spec, not chat. When the change has something the maintainer can try in a few minutes (a screen, a page, a command's output, a behavior they can trigger), the proposal offers them a hand check. It says what they would try, and that a hand check they accept holds back "You: merge #N." until they report it. A change with nothing to try gets no offer.
6. Claude Code may propose a fast track (no Codex or Grok review) for a change that cannot alter what code does or what an agent is told; the spec records it with its reason.
7. Once agreed, it writes the spec (shape in `mentat:pr`) in the backlog item (chat if none) and, unless the backlog is external, the pull request once open. The spec lists a requirement the maintainer checks by hand only when their agreement accepts the offer or they asked for one.
8. If the approach is uncertain, the decision matters or the maintainer asks for a challenge, it calls the Skill tool with `mentat:plan`.
