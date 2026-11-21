---
type: regex
target: last_message
pattern: 'PR #88[^A-Za-z0-9\n]{0,6}ABC-63|ABC-63[^A-Za-z0-9\n]{0,6}PR #88'
match: contains
---

The reply names the pull request as PR #88 with its item id beside it.
