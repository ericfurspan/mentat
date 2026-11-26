# Every outside reviewer runs on the same schedule, under one time limit

Status: superseded in part by [0010](0010-outside-review-on-every-ready-head.md), for when outside reviewers run; the one time limit stands.

Each outside reviewer had its own schedule and settings: one reviewed every round, another only the first head and at review stops, with its own time limit and its own comments. Now every reviewer a repository lists in `MENTAT_REVIEWERS` runs through one adapter, in parallel, once on each head Claude's local review finds clean, and `MENTAT_REVIEW_TIMEOUT_SECONDS` is the one time limit for every reviewer, because one schedule makes adding or removing a reviewer a list change rather than new review rules, and gives the maintainer one result per head to read. The cost is that a reviewer that used to run on every round now waits for a clean Claude round, and a slower reviewer can no longer be given more time than the rest.
