---
type: regex
target: trace
pattern: '^(?:(?!\n(?=[^\n]*"type":"assistant")(?:(?!"name":"Skill"(?=[^\n]*mentat:propose))[^\n])*?"text":"(?:[^"\\]|\\.){120})[\s\S])*?"name":"Skill"(?=[^\n]*mentat:propose)'
match: contains
---

The trace reaches the Skill call for mentat:propose before any assistant text of 120 or more characters (as written in the trace). It is a deterministic check on the whole trace that catches only a long text before the call; it cannot tell a short view from a short announcement. `no-view-before-propose` judges the order on the trace and fails a view of any length given before the call.
