#!/usr/bin/env bash
# Each behavior eval case, a directory directly under evals/ other than results/ (local run
# output, ignored by git), has a prompt.md and at least one grader in graders/*.md, and there
# is at least one case. Makes no model calls; it never runs the suite. Takes the evals
# directory as its one argument (default evals). Prints PASS/FAIL per check; exits 1 on any FAIL.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
pass() { printf 'PASS: evals %s\n' "$1"; }
fail() { printf 'FAIL: evals %s\n' "$1"; failures=$((failures + 1)); }

dir=${1:-evals}
cases=0
for c in "$dir"/*/; do
  [ -d "$c" ] || continue
  c=${c%/}
  [ "${c##*/}" = results ] && continue
  cases=$((cases + 1))
  if [ -f "$c/prompt.md" ]; then
    pass "$c has prompt.md"
  else
    fail "$c must have prompt.md"
  fi
  graders=0
  for g in "$c"/graders/*.md; do
    [ -f "$g" ] && graders=$((graders + 1))
  done
  if [ "$graders" -gt 0 ]; then
    pass "$c has $graders grader(s)"
  else
    fail "$c must have at least one grader in graders/*.md"
  fi
done
if [ "$cases" -gt 0 ]; then
  pass "$dir holds $cases case(s)"
else
  fail "$dir must hold at least one case directory"
fi

[ "$failures" -eq 0 ]
