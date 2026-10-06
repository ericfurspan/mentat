# Glossary

*Terms as Mentat uses them, for people and agents. Industry terms keep their usual meaning and are not listed.*

- **Maintainer**: the person who owns the repository, decides what to build and merges.
- **Builder**: the one agent that makes a change, on one branch in one checkout.
- **Review**: Codex checking a pull request's head commit against its description. Run by `mentat review`, through the Codex GitHub app or local Codex (`--local`).
- **Round**: one review of one head commit. A push starts a new round.
- **Finding**: one problem a review or challenge reports, ranked P0 (most severe) to P3.
- **Challenge**: Codex checking a written plan against the repository before it is built (`mentat challenge`). Never counts as a review.
- **Final check**: the author's own ten-line comment on the reviewed commit before the pull request is handed to the maintainer. Not a review or an approval.
- **Head commit**: the latest commit on the pull request's branch; reviews, tests and the final check all refer to it.
- **Test command**: the one command that checks the repository, named in AGENTS.md or shown by the repository (here, `tests/run`).
- **Draft**: a pull request still being built; `mentat review` marks it ready.
- **Merge danger**: how risky a merge is. A **two-way door** is undone by reverting; a **one-way door** leaves something a revert does not undo. The **blast radius** is who or what breaks if the change is wrong.
- **`idea` and `ready`**: issue labels for not yet ready to build and ready to build.
