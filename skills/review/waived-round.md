# Waived round

After a head reached Ready, Claude Code may propose skipping the review round of a push the maintainer asked for when the diff from the last reviewed head to the pushed head changes no file a program runs, sources or fetches (scripts, hooks, `bin/`, `lib/`, configuration, lockfiles, workflow files, a URL a program fetches); Markdown read by agents may be in it. The proposal names the changed files in one line: before "You: merge #N.", in chat, and the waived push (its `mentat ci` and the final check) runs before that line; after it, in the hold's reply.

- Skip only on the maintainer's yes for that push, judged on the diff actually pushed. Any doubt, a pushed diff that differs from the proposal, or a change to the spec runs the normal round.
- Run no `mentat review` or `mentat review --grok`, and on the Claude-only path no Claude round (overriding its rule that a new head after a hold gets one). Run `mentat ci <N>` (exits as in `fast-track.md`), then the final check on the new head. The status line is `Not reviewed: last push waived by the maintainer`; the note names the last reviewed head, the waived head and the changed files; the sentence after "You: merge #N." says the last push was not reviewed, waived by the maintainer. A waived push uses no round.
- Each waived push is measured from the last head a review covered.
