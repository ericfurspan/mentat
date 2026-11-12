# Second opinion rounds and the agreement question

Read this from `mentat:propose` step 4 before the first `mentat second-opinion` round, and again after a compaction.

## Rounds

It runs another round only when the last round's settlement adopts a change to the idea's requirements, scope or approach; a wording-only change does not count. The rounds stop when a settlement adopts no such change, or after three rounds in all. Each later round's file holds the whole revised idea, with its answers and deferred choices, and no earlier replies or summary of them. A round in which no tool gives a verdict stops the rounds.

## The agreement question

That question holds only what the maintainer gets; what it costs, naming any hand check offered (which holds back "Ready to merge: #N" until they report it, `mentat:propose` step 5) and any fast track proposed (`mentat:propose` step 6); each tool that disagreed (`DO IT DIFFERENTLY` or `DON'T`), with why in a few words; each open maintainer comment that bears on the agreement, named in a few words with its answer, where an objection to the options revises them or the question says why they stand (`mentat:backlog` "Reading an item"); and these facts: it names any tool that gave no answer (it failed, timed out or is not installed), says when the last adopted change had no second opinion, and says when a round did not happen because no tool gave a verdict. It also says why the first option is recommended, as `rules.md` "What goes to the maintainer" requires; the replies blocks and the full proposal stay out of it.

Its options are "Agree and build now", "Agree, build later", "Show the full proposal" and "Not now", in that order; the first is recommended where the maintainer wants it built in this session. "Show the full proposal" prints in chat every round's replies block as `mentat:backlog` "Replies in chat" says, never the saved command output, and the full proposal (`mentat:propose` step 5).
