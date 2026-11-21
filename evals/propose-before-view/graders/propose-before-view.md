---
type: regex
target: trace
pattern: '^(?:(?!\n(?=[^\n]*"type":"assistant")(?:(?!"name":"Skill"(?=[^\n]*mentat:propose))[^\n])*?"text":"(?:[^"\\]|\\.){120})[\s\S])*?"name":"Skill"(?=[^\n]*mentat:propose)'
match: contains
---

The trace reaches the Skill call for mentat:propose before any assistant text of 120 or more characters (as written in the trace), so the view comes after it. A short line announcing the plan may come first.
