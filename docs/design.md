# Design decisions

*For people. Agents follow `rules.md`, not this page.*

Why Mentat is built the way it is: each decision, what was rejected, and the evidence. Numbers come from the linked records and are small samples, so they point a direction and prove nothing.

## One builder, one branch, one checkout per change

A builder subagent (Sonnet, [`prompts/builder.md`](../prompts/builder.md)) makes each change on its own branch. The main session plans, briefs and reports, and never edits files. The maintainer's chat then shows plans and reports, not diffs, and one writer per change avoids conflicting implicit choices. Rejected: parallel builders, and co-builders from other vendors.

Evidence: the research record in [#217](https://github.com/ericfurspan/mentat/issues/217) reads Cognition's "Don't build multi-agents" (parallel writers make conflicting implicit choices) and Anthropic's multi-agent research post (coding is less parallelizable than research). Other vendors are used for text the main session can sort, not for code.

## A second reviewer from another vendor, on every pull request head

Codex, through its GitHub app or the local CLI, reviews each head. Findings with a realistic trigger are fixed and the rest are answered with a reason, for five rounds at most. LLM judges favor their own generations and similar models, so a different vendor catches what the writer's model misses. Rejected: Claude reviewing Claude, kept only as the fallback when Codex is off.

Evidence: [#217](https://github.com/ericfurspan/mentat/issues/217) cites Panickssery et al. (NeurIPS 2024) and Goel et al. (ICML 2025). Of 105 pull requests merged after app review started, 45 had at least one review round with findings (72 such rounds, 0.69 per pull request). In [#83](https://github.com/ericfurspan/mentat/issues/83), the Codex app found about 7 real defects after local Codex runs had passed (a reconstructed count over unequal samples, 42 pull requests against 7).

## Grok as a third model, reviewing once and weighing ideas

Where Grok is installed, it reviews the first head of a pull request and joins `mentat weigh`. It is not a review round and never reruns. Evidence ([#165](https://github.com/ericfurspan/mentat/issues/165#issuecomment-6137324697)): on 5 commits Codex had reviewed, sandboxed Grok caught 3 of Codex's 5 first-round defects and found 3 real defects Codex's first round missed. It also raised 5 non-defects, took 8 to 19 minutes a run against about 4 for Codex, and gave different findings on the same commit across runs. So it is a second reviewer, not a replacement, and the loop does not wait on it: a real run on [#220](https://github.com/ericfurspan/mentat/pull/220) timed out at 20 minutes, and [#227](https://github.com/ericfurspan/mentat/issues/227) ([#230](https://github.com/ericfurspan/mentat/pull/230)) lets round-1 fixes go ahead without it.

## The reviewer sees only the change

Local Codex runs read-only under a permissions profile in a detached worktree, with its apps connector off. Grok runs in its own sandbox on a plain export without `.git`, with file tools only, in a fresh home that holds only its sign-in. A reviewer that can read GitHub or other runs' output is not reviewing the diff, and the sign-in must not leak.

Evidence: [#218](https://github.com/ericfurspan/mentat/issues/218) found local Codex fetching live issues through the apps connector until `features.apps=false`, and `/var/tmp` readable. In [#220](https://github.com/ericfurspan/mentat/pull/220), which built Grok's review for [#213](https://github.com/ericfurspan/mentat/issues/213), a sentinel run with a planted fake credential showed 0 leaks and caught a hole (`grep` on the home folder) that was then fixed. The #165 trial found Grok's own `--sandbox` would not start; #220 found it starts on 1.0.52, so `sandbox-exec` was dropped.

## Weigh the idea before it is agreed

Claude Code gives its view of every request as a teammate. New features and workflow changes also get Codex's and Grok's independent verdicts (`mentat weigh`), each ending DO IT, DO IT DIFFERENTLY or DON'T. A DO IT is not the maintainer's agreement. Why: an idea was once filed as agreed without anyone weighing it ([#223](https://github.com/ericfurspan/mentat/issues/223)).

Evidence: the replay in [#217](https://github.com/ericfurspan/mentat/issues/217) reviewed the pre-build scope of 10 merged pull requests, which is a proxy for weighing. Codex anticipated the defect the first review round later found in 7 of 10 and Grok in 8 of 10, with about 0.3 and 0.75 non-defects per real finding. One scorer, small sample; a live trial continues there. The first live run ([#224](https://github.com/ericfurspan/mentat/pull/224)) gave DO IT DIFFERENTLY from Codex and DON'T from Grok on the same idea.

## Plan challenge for uncertain plans

A written plan goes through `mentat challenge` (Codex) when the approach is uncertain or the decision matters. Evidence ([#217](https://github.com/ericfurspan/mentat/issues/217)): at least 9 challenges, all 9 "proceed with changes", at least 2 changed the design, and at least 2 findings were declined with evidence. That record also notes a 9-of-9 rate fits a challenger that always finds something.

## Hooks are nets, not boundaries

Two PreToolUse hooks ask the maintainer before any merge command and before a push to the default branch. `rules.md` forbids merging, releasing, deploying and committing or changing secrets. The maintainer merges; the hooks catch mistakes, and other routes exist. Rejected: claiming to sandbox the main agent, which [how it works](how-it-works.md) says Mentat does not do. Evidence: the headers of [`hooks/no-merge`](../hooks/no-merge) and [`hooks/no-default-push`](../hooks/no-default-push), and the review rules in [`AGENTS.md`](../AGENTS.md), which say another command form that skips a hook is not a finding.

## Plain bash, one test command, no CI yet

Everything is bash that runs on macOS's bash 3.2. [`tests/run`](../tests/run) is the one test command: about 375 checks with stub `gh`, `codex` and `grok`, a live Codex sandbox replay, ShellCheck and plugin validation. A Claude Code plugin's hooks and commands are shell, nothing needs installing, and the sandboxes are macOS features. Rejected: a Python or Node rewrite. CI is planned as the last step before the repository goes public ([#216](https://github.com/ericfurspan/mentat/issues/216)).

## Rules in two hook files

`rules.md` and `rules-records.md` are each printed by their own SessionStart command, because Claude Code caps a hook's output at 10,000 characters per hook. Evidence: [#226](https://github.com/ericfurspan/mentat/issues/226) and [#231](https://github.com/ericfurspan/mentat/pull/231), whose delivery check quoted a bullet from each file out of a tool-less session.

## No draft pull requests; a comment starts each app review

Pull requests open as normal pull requests. A Codex GitHub app round starts with an `@codex review` comment whose GitHub timestamp marks the round's start; a local Codex review (`mentat review --local`, used directly or as the app fallback) posts no trigger comment and posts only its finished result as a comment. Draft pull requests are not available on every plan for private repositories. Evidence: [#205](https://github.com/ericfurspan/mentat/issues/205), [#206](https://github.com/ericfurspan/mentat/pull/206).

## Conventions in the code

The `lib/` files are sourced by `bin/mentat`. Functions share state through the caller's variables and report failure by calling the function named in `fail` (documented at the top of [`lib/grok.sh`](../lib/grok.sh)), a bash idiom chosen over passing many arguments. Every command fails closed ("not reviewed", "not challenged", "not weighed") rather than guessing.
