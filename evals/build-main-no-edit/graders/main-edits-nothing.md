---
type: llm
---

PASS if the reply has a builder (a subagent working in its own worktree or branch) make the edit to cli.py, and the main session itself edits no files. FAIL if the main session says it edits cli.py, or any other file, itself.
