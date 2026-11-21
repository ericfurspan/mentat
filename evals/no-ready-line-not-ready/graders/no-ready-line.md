---
type: regex
target: last_message
pattern: '^\W*Ready to merge: #72'
flags: m
match: not_contains
---

The reply writes no pasteable Ready line for a pull request that is not ready.
