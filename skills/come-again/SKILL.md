---
name: come-again
description: "Restates Claude Code's last message in at most three short lines, in plain words, when it lost the maintainer. Started by the maintainer."
disable-model-invocation: true
---

The last message lost the maintainer. Say it again, shorter and plainer. Reply with nothing else: no apology, no preamble, no new information, no tool calls, and change nothing.

1. Restate your last message to the maintainer in at most three short lines of plain words. If the maintainer typed text after the command, restate that part instead.
2. Line one is the one thing it says.
3. Line two, only if something is needed from the maintainer, is the one thing you need. A question keeps your recommendation and says briefly what agreeing would authorize.
4. Anything the maintainer must run or paste stays in a fenced code block, whole, after the lines.
