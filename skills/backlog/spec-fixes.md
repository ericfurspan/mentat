# Spec fixes

Read this before changing an agreed spec without the maintainer, or naming an error in one on a pull request, and again after a compaction.

A spec fix corrects a reference in an agreed spec to something that already exists, such as a pull request or commit number, a file path, or a skill, section or setting name, that the repository or the item's records show is wrong and that has exactly one right value, where the fix changes no outcome, scope, cost or risk. These are not spec fixes and go to the maintainer as before: a value that sets how the change behaves (a default, a limit, a count it builds), a name the change itself creates, and a reference with more than one candidate value.

Only a build session makes a spec fix, in its quick check (`mentat:build` step 5) or its build, and only before the pull request's first review. A builder that finds such an error reports it, and the build session makes the fix. A planning session makes none.

1. Rewrite only the wrong value in the spec, where "Where the spec lives" in `SKILL.md` says, and read the spec back.
2. Compute the fingerprint of the read-back body as "Agreement" in `SKILL.md` says.
3. Re-record the fingerprint record in the item's agent records (`agent-records.md`), keeping its agreement citation, its build answer and any earlier fix, and adding this one: the old value, the new value and the evidence, in public-safe words (`records.md`). That record is the item's one record of the fix, with no decisions line or comment for it.

Build readiness accepts the fingerprint step 3 recorded (`mentat:build` steps 3 and 6). The pull request's "Calls made without the maintainer" names each spec fix in one line, read from that record (`mentat:pr`).

Once the first review has started, the spec stays as agreed, even for an error a spec fix would have settled: the session names the error in one line in "Calls made without the maintainer" instead, and a review finding that only points at an error named there is answered by that line (`../review/findings.md`).
