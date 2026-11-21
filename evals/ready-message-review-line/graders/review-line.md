---
type: regex
target: last_message
pattern: 'Review: skim \(no listed reason for closer review\)'
match: contains
---

The message carries the review-depth line for a pull request with no reason for closer review.
