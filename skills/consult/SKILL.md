---
name: consult
description: "Consults Codex, Grok and Claude Code on any question the maintainer wants several views on, and answers in five short lines at most: the consensus first, then what each model adds. Started by the maintainer, with the question after the command."
disable-model-invocation: true
---

The maintainer wants several points of view on one question before trusting the answer. This runs once, then normal work resumes. The question is the text the maintainer typed after the command; if there is none, ask for it and stop.

1. Write the question to a file: the maintainer's words and the context they gave, nothing of Claude Code's own view. Put it in the repository's ignored working folder when the repository names one (`work/` here), otherwise in a temporary folder; never in an unignored path of a working tree. The text goes to OpenAI and xAI and may be searched for: if it holds anything private, say so and stop.
2. Write Claude Code's own one-line answer to the question into a second file, using its own web tools where they help, before the next step, so that the three views are independent.
3. Run `mentat consult <question file>` with its output saved beside the question. It takes a few minutes; Codex and Grok run in parallel, each with the web and nothing else.
4. Read the output, the full replies and not only their `CONSULT:` lines. Reply in five lines at most, each about 25 words or fewer, and nothing else; this replaces the output style's first-line form while this skill runs:
   - `Consensus: <the answer to act on>`. When the views split, say so and name who disagrees on what. A claim none of them could verify is named here.
   - `Codex: <what Codex adds: its main reason, or where it differs>` or `Codex: not consulted (<reason>)`
   - `Grok: <what Grok adds: its main reason, or where it differs>` or `Grok: not consulted (<reason>)`
   - `Claude: <what Claude Code's line from step 2 adds>`
   - One link to the saved output.
   A model line does not repeat the consensus. When neither tool delivered, the Consensus line says the consultation did not happen, and the reply ends with the question of how to proceed.

Consult is not a step in a change: it does not weigh an idea or challenge a plan, and `/mentat:codex-review-off` does not turn it off. A consult never counts as a review.
