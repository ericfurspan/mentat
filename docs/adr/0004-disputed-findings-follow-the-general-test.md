# A disputed review finding goes to the maintainer only when its outcome is theirs

Status: superseded by [0007](0007-review-stops-only-for-scope-goal-or-safeguard.md).

A review finding Claude Code disagrees with, marked blocking or not, goes to the maintainer only when fixing or leaving it changes what they get, pay or risk, the test every other decision follows. This reverses the rule that sent every disputed blocking finding to them, because a reviewer's blocking mark is a claim, not a sign the choice is theirs, and a question with no real outcome for them stopped work without giving them a decision; a blocking finding answered instead of fixed still reaches them before they merge, as a Risks line and in the Ready message.
