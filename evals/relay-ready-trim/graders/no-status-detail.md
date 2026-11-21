---
type: regex
target: last_message
pattern: '4m12s|[Rr]ound 2|CI passed'
match: not_contains
---

The relay leaves out the round count and the CI result.
