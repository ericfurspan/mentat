# Replies in chat

After each `mentat second-opinion` round, with any backlog, the replies go in this block:

```
Codex: <label> - <reason>
Grok: <label> - <reason>
Adopting: <what Claude Code takes up>
Not adopting: <what> (<why>)
```

- One line per tool that ran or was due: Codex, and a Grok line only where `grok` is installed. A tool with no answer gets `no second opinion` and why, in public-safe words, never a log path.
- The label is `worth doing` for `DO IT`, `another way` for `DO IT DIFFERENTLY` and `not worth doing` for `DON'T`. The reason is the tool's own, in about 10 words, keeping any condition or required change even if longer: the text after the dash for `DO IT DIFFERENTLY` and `DON'T`, the reply's main point for `DO IT`. With nothing to summarize, the reason is `no reason given`; a label is never shown alone.
- Plain words, about 25 a line. Leave out an empty line; add nothing else.
- The block never goes in a decision prompt. In `mentat:propose` step 4 it is shown in chat only when the maintainer picks "Show the full proposal"; elsewhere it goes in the message.
- Each line of the block stays on its own line wherever the block is shown.
- A round that ends during `mentat:propose` step 4 prints nothing as it ends. "Show the full proposal" prints every round's block; with more than one round, each block gets a first line `Round <n>` as its one addition.
