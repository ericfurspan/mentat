# The plan check and the agreement question

Read this at `mentat:propose` step 4, and again after a compaction.

## The plan check

The plan check is one check, one round. Its idea file also holds the material assumptions and the failures that would become requirements known then (`mentat:propose` step 5), plus one line naming the failures considered and left out.

A reply is a plan check only when its last line is exactly one of the three `PLAN CHECK VERDICT:` lines. A reply without one, an error or an empty result never counts as a pass: Claude Code calls the checker once more with the same file, and when that gives no verdict either, the agreement question says the plan check did not happen and why. Claude Code settles each point of the reply, adopting it or not, as `mentat:backlog` "Replies in chat" shows; an adopted change is not checked again.

## The agreement question

The agreement question holds only what the maintainer gets; what it costs, naming any hand check offered (which holds back "Ready to merge: #N" until they report it, `mentat:propose` step 5) and any fast track proposed (`mentat:propose` step 6); each material assumption still standing and what changes if it is false, in a few words, this being where the maintainer sees them; the plan check's verdict when it is `DO IT DIFFERENTLY` or `DON'T`, with why in a few words and what was adopted; each tool of a second opinion the maintainer's own instructions add that disagreed (`DO IT DIFFERENTLY` or `DON'T`), with why in a few words; each open maintainer comment that bears on the agreement, named in a few words with its answer, where an objection to the options revises them or the question says why they stand (`mentat:backlog` "Reading an item"); and these facts: it names any such tool that gave no answer (it failed, timed out or is not installed), says when the plan check gave no verdict, and names each change adopted from it, which no check saw. It also says why the first option is recommended, as `rules.md` "What goes to the maintainer" requires; the replies blocks and the full proposal stay out of it. Everything it holds is given in plain words inside the word bound that section sets for the whole question; an item that does not fit is named in a few words and given in full by "Show the full proposal", never in text before the prompt.

Its options are "Agree and build now", "Agree, build later", "Show the full proposal" and "Not now", in that order; the first is recommended where the maintainer wants it built in this session. A choice the maintainer's own instructions add to this question takes the place of "Show the full proposal", which they can still ask for through Other. "Show the full proposal" prints in chat the plan check's replies block, and any second opinion's, as `mentat:backlog` "Replies in chat" says, never a saved reply file, and the full proposal (`mentat:propose` step 5).
