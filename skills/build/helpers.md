# Implementers

Read this before briefing an implementer and before each push, and again after a compaction or a resume. It covers every implementer run: an item's first round, CI fixes, review fixes and work after a hold alike.

## Briefs

The implementer is the `mentat:builder` subagent. Right before every call, read `MENTAT_BUILDER_MODEL` by name with `printenv MENTAT_BUILDER_MODEL`, never the whole environment, and pass its value as the call's model; unset or empty, the call sets no model and the agent's own runs.

A brief names the branch, the session's own checkout and the main checkout ("One implementer per branch"), the AGENTS.md files that apply, what to change and what to leave alone, how the result will be checked, the test command, and any existing design the change keeps that could affect its goal. A brief for an item carries the item's current assumptions list as given, read from its agent records right before the brief, when one stands (`../backlog/records.md` "Assumptions").

Before fixing a raised problem, check likely related cases in proportion to its scope and report a shared cause when found, keeping the fix within the agreed scope; a fix targets the cause the evidence supports, and with the cause unknown, finding it comes first. A correction during agreed work does not reopen the spec: follow one within the agreed scope at once, and file it only when the maintainer asks. An outcome the spec leaves open (what the maintainer gets, pays or risks) that the quick check did not settle is settled before that part is implemented and logged as `SKILL.md` step 5 says: a decisions line made without the maintainer and a pull request line. A change of scope, or a decision the spec or the maintainer reserved, goes to the maintainer as one question before that part is implemented.

## Worktree

The session makes no worktree for an implementer. Before the first round, `mentat worktree branch <branch>` cuts the item's branch from origin's default branch with no upstream, so a bare `git push` never aims at the default branch (`SKILL.md` step 6 says what each exit means). The branch carries the item id as the tracker's adapter says. Each implementer runs in a worktree the host makes for it, switches to the branch there and reports that worktree's absolute path, the `<path>` below.

The main session never changes its own directory into a worktree: it runs `git -C <path>` or a subshell `( cd <path> && ... )`. Once the round is finished and `git -C <path> status --porcelain` prints nothing, it pushes with `git -C <path> push -u origin <branch>`; the pushed head is `git -C <path> rev-parse HEAD`. Then it removes the worktree with `git worktree remove <path>`, never `--force`; a refusal keeps it, listed as unfinished, and no implementer starts on a branch while a worktree is on it. Between rounds a pull request has no worktree.

## One implementer per branch

A pull request has one implementer at a time, as `rules.md` asks of each pull request: each round is a fresh `mentat:builder`, started in the background, so the session stays free. The main checkout is the parent of `git rev-parse --path-format=absolute --git-common-dir`. While the implementer runs, the host's lock on its worktree is the lock; the session adds none. When its completion notice arrives, done, stopped or failed, run the main-checkout check.

A round is finished only when its report says the brief's work is done and committed. Any other report finishes nothing: nothing of that round is tested, pushed or reviewed, and the round goes on as "Unfinished" says, or, with no worktree on the branch, with a fresh implementer as "Recovery" says, told what stopped the round. Only a stop the session cannot resolve without the maintainer (a failed start-up check, a permission block) goes to them first, its worktree kept as it is until they answer. An implementer that ends with no report leaves its round unfinished, handled as "Recovery" says.

## Main-checkout check

Before each brief, run `mentat worktree snapshot` for the main checkout, and `mentat worktree snapshot <checkout>` for the session's own when it is another directory, and keep each line; on exit 2 or 64, start no implementer and tell the maintainer what it printed. After the implementer reports, run `mentat worktree verify "<line>" [<checkout>]` with each, the line quoted as one argument. Exit 0: unchanged (the branch and status are the noted ones, and `HEAD` is the noted one or moved only forward along origin's copy of the branch as last fetched); when it says the snapshot's checkout was not clean, the run's final message says the check was weaker. Exit 1, 2 or 64: start no further implementer, change nothing in either checkout, and tell the maintainer the paths and what it printed. The check does not see writes to ignored paths.

## Testing

Before pushing, test the pushed commit with a clean working tree (`git -C <path> status --porcelain` prints nothing), not relying on the implementer's report, unless the repository's AGENTS.md says CI runs the test command on every pull request. Then CI is that run, except that after CI fails on the branch, the next commit is tested this way before it is pushed; and a head with no CI check runs is not a pass: test that commit before any review of it counts, in a test worktree at a temporary path outside every checkout (`git worktree add --detach <temporary path> <commit>`, the test command there with its output saved outside it, then `git worktree remove <temporary path>`; a refusal keeps it, listed for the maintainer), never in the main checkout or the session's own.

## Recovery

After a compaction or a resume, before any other step, find this session's work by its items' branches (its queue, or the item it agreed; a held item's branch is not its work, `SKILL.md` "Held items"), not by worktree paths. Read `git worktree list --porcelain`, and for each such branch the worktree on it, if any (`git -C <path> status --porcelain`, its commits not on origin's copy of the branch), and its pull request (`gh pr list --head <branch> --state all --json number,state,headRefOid`), with `mentat status <N>` for an open one.

An implementer is running only while the host's list of this session's subagents shows it running and its report is not yet in: wait for that report; if that list cannot be read, wait and tell the maintainer. For each branch with no running implementer, a round is unfinished when this session started it and it is not finished, by the session's own record, or when it is a queue item's first round with no pull request and no commit beyond the default branch's. Where the record cannot tell, start nothing on that branch, remove no worktree and tell the maintainer. With an unfinished round, a worktree on the branch is handled as "Unfinished", never removed as clean and pushed; with none, a fresh implementer gets that round's brief and is told of any earlier one that stopped. A round waiting on the maintainer's answer to a stop waits here too. With no unfinished round, a worktree on the branch is removed as "Worktree" says when clean and pushed, else handled as "Unfinished"; with none, go on with the step the pull request was at (its review, a wait on the maintainer, or after merge, where a merge only this read finds, with no word from the maintainer, starts no held item, `SKILL.md` "Held items"). Every other worktree is left untouched and listed for the maintainer; a host-made worktree whose implementer never switched is left to the host.

## Unfinished

An implementer's worktree is unfinished when it has uncommitted changes or commits not pushed, or its round is not finished. It is never reset, stashed, cleaned or force-removed. When its round is finished and `git -C <path> status --porcelain` prints nothing, start no implementer and go on with the step it waited for (test, push, removal). While its round waits on the maintainer's answer to a stop, keep it as it is. Otherwise continue that same implementer where the host still knows it. Where it does not, commit any uncommitted work as it stands with `git -C <path> add -A` and `git -C <path> commit`, a subject saying an earlier implementer stopped; then remove the worktree with `git worktree remove <path>` once `git -C <path> status --porcelain --ignored` prints nothing, and start a fresh implementer, told that an earlier one stopped and that its work stays where it fits the brief. Ignored files left there may be the stopped one's unreported work: keep the worktree, list it with those paths, and go on once the maintainer says to drop them. When a step is refused, keep the worktree and list it (path, branch, what is unfinished) in the recovery message and in the run's final message.

## After merge

When the maintainer says #N merged, or the recovery read finds it merged, run `mentat worktree cleanup <N> <branch>` for this session's branch only, never another session's. It checks the pull request merged with that head before changing anything, then removes a clean worktree on the branch and deletes the local branch, leaving the remote branch. Exit 0: done, or nothing was left. Exit 1: keep what it names (a failed check, a refused removal or a failed delete) and list the worktree and branch for the maintainer. Exit 2 (the pull request could not be read) or 64 (a usage error): change nothing and say so. A branch whose pull request closed without merging is kept and listed until the maintainer says to drop it.

## A separate session

An implementation runs in a separate session only as `mentat:plan` "Starting implementation" says.
