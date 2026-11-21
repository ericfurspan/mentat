---
type: regex
target: last_message
pattern: 'Ready to merge:'
match: not_contains
---

The reply writes no Ready line for a pull request that is not ready.
