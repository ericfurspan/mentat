---
name: consult
description: "Consults Codex, Grok and Claude Code on any question the maintainer wants several views on, and answers in five short lines at most: the consensus first, then what each model adds. Started by the maintainer, with the question after the command."
disable-model-invocation: true
---

The maintainer wants several points of view on one question before trusting the answer. This runs once, then normal work resumes. The question is the text the maintainer typed after the command; if there is none, ask for it and stop.

1. Write the question to a file: the maintainer's words and the context they gave, nothing of Claude Code's own view. Put it in the repository's ignored working folder when the repository names one (`work/` here), otherwise in a temporary folder; never in an unignored path of a working tree. The text goes to OpenAI and xAI and may be searched for: if it holds anything private, say so and stop.
2. Write Claude Code's own one-line answer to the question into a second file, using its own web tools where they help, before the next step, so that the three views are independent.
3. Run `mentat consult <question file>` with its output saved beside the question. It takes a few minutes; Codex and Grok run in parallel, each with the web and nothing else.
4. If Grok's reason in the Views section, the text after `not consulted:`, starts with `Grok's sign-in` or `Grok is not signed in`, do not reply with the views yet: ask the maintainer to run `grok login`, in a message that ends the turn, and once they say it is done, run step 3 again.
5. Read the output. Reply in five lines at most, each about 25 words or fewer, then one link, and nothing else; this skill sets the reply's shape while it runs:
   - `Consensus: <the answer to act on>`. When the views split, say so and name who disagrees on what. A claim none of them could verify is named here.
   - `Codex: <what Codex adds: from its CONSULT line, with the main reason its reply gives for it, or where it differs>` or `Codex: not consulted (<reason>)`
   - `Grok: <what Grok adds: from its CONSULT line, with the main reason its reply gives for it, or where it differs>` or `Grok: not consulted (<reason>)`
   - `Claude: <what Claude Code's line from step 2 adds>`
   - Then one link to the saved output.
   A model line does not repeat the consensus; when a model adds nothing beyond it, its line is `<Model>: agrees.` When neither tool delivered, the Consensus line says the consultation did not happen, and the fifth line asks how to proceed, before the link.

Consult is not a step in a change: it does not weigh an idea or challenge a plan, and `/mentat:codex-review-off` does not turn it off. A consult never counts as a review.
