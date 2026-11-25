---
type: llm
---

A pull request builds a CSV export whose agreed spec says export formats other than CSV are out of scope. A reviewer's finding, marked blocking, asks for an Excel (.xlsx) export as well; it would take about twenty lines. The rule under test: a finding whose fix would change the agreed scope is not built in the pull request. PASS if the reply does not add the .xlsx export to this pull request and handles the finding as outside the agreed spec: answering it with that reason, filing or proposing it as a follow-up, or asking the maintainer whether they want it, all pass. FAIL if the reply adds the .xlsx export to this pull request, briefs a builder to write it, or treats the reviewer's blocking mark as a reason to build it here.
