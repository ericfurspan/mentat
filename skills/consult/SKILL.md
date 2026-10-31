---
name: consult
description: "Consults Codex, Grok and Claude Code on any question the maintainer wants several views on, and answers in five short lines at most: the consensus first, then what each model adds. Started by the maintainer, with the question after the command."
disable-model-invocation: true
---

The maintainer wants several points of view on one question before trusting the answer. This runs once, then normal work resumes. The question is the text the maintainer typed after the command; if there is none, ask for it and stop.

1. Write the question to a file: the maintainer's words and the context they gave, nothing of Claude Code's own view. Put it in the repository's ignored working folder when the repository names one, otherwise in a temporary folder; never in an unignored path of a working tree. The text goes to OpenAI and xAI and may be searched for: if it holds anything private, say so and stop.
2. Write Claude Code's own one-line answer to the question into a second file, using its own web tools where they help, before the next step, so that the three views are independent.
3. Run `mentat consult <question file>` with its output saved beside the question. It takes a few minutes; Codex and Grok run in parallel, each with the web and nothing else.
4. Read the output. A Grok sign-in refusal is not a stop: the `Grok: not consulted (<reason>)` line carries it. Reply in five lines at most, the last one link, each of the others about 25 words or fewer, and nothing else; this skill sets the reply's shape while it runs:
   - `Consensus: <the answer to act on>`. When the views split, say so and name who disagrees on what. A claim none of them could verify is named here.
   - `Codex: <what Codex adds: from its CONSULT line, with the main reason its reply gives for it, or where it differs>` or `Codex: not consulted (<reason>)`
   - `Grok: <what Grok adds: from its CONSULT line, with the main reason its reply gives for it, or where it differs>` or `Grok: not consulted (<reason>)`
   - `Claude: <what Claude Code's line from step 2 adds>`
   - Then one link to the saved output.
   A model line does not repeat the consensus; when a model adds nothing beyond it, its line is `<Model>: agrees.` When neither tool delivered, the Consensus line says the consultation did not happen, and how to proceed is asked after the reply, as `rules.md` "What goes to the maintainer" says.
