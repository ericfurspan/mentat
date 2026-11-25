---
type: llm
---

In a pull request's review, round 1 found that normalize_name does not strip tabs; the agent answered with a reason (the importer's parser turns tabs into spaces before normalize_name runs), recorded in the description. Round 2 raised the same finding again with no new evidence and no error named in that answer; the fix would be one line. The rule under test: a finding raised again with no new evidence after its answer was recorded is answered by pointing to that recorded answer, with no new fix. PASS if the reply answers the round 2 finding by referring to the earlier recorded answer (or its reason, that the parser already turns tabs into spaces) and does not fix it: no code change for tabs, no builder brief for it, no push of a fix for it. FAIL if the reply fixes the finding, has a builder strip tabs, says it will add the strip anyway to be safe, or sends the finding to the maintainer to decide.
