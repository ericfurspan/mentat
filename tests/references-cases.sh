#!/usr/bin/env bash
# shellcheck disable=SC2016
# The file-reference check (tests/references.sh) behaves as specified on invented skill files:
# each case runs a copy of it in its own temporary repository holding only that case's files.
# Prints PASS/FAIL per check; exits 1 on any FAIL.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
pass() { printf 'PASS: references cases %s\n' "$1"; }
fail() { printf 'FAIL: references cases %s\n' "$1"; failures=$((failures + 1)); }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
script=$PWD/tests/references.sh

# repo: a new repository with a copy of the check and an empty rules.md and AGENTS.md; prints its path.
repo() {
  local r
  r=$(mktemp -d "$tmp/repo XXXXXX") || return 1
  mkdir -p "$r/tests" && git init -q "$r" && cp "$script" "$r/tests/references.sh" \
    && : >"$r/rules.md" && : >"$r/AGENTS.md" && printf '%s\n' "$r"
}

# put <repo> <path> <text>: writes the text, one line, to the path in the repository.
put() {
  mkdir -p "$1/$(dirname "$2")" && printf '%s\n' "$3" >"$1/$2"
}

# run_check <repo>: runs the check there.
run_check() {
  out=$("$1/tests/references.sh" 2>&1)
  rc=$?
}

# expect <what> <exit status> <text the output must hold>: the last run_check gave both.
expect() {
  if [ "$rc" = "$2" ] && printf '%s\n' "$out" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1 (exit $rc, wanted $2 and the text: $3)"
    printf '%s\n' "$out"
  fi
}

# A path from the repository root in a skill file is checked: one that exists passes.
r=$(repo) || exit 1
put "$r" skills/sample/SKILL.md 'Read `skills/other/notes.md` first.'
put "$r" skills/other/notes.md 'Notes.'
run_check "$r"
expect "a root-relative path in a core skill file that exists passes" 0 "PASS: references skills/sample/SKILL.md names skills/other/notes.md, which exists"

# One that is missing fails, in a core or a module skill file.
r=$(repo) || exit 1
put "$r" skills/sample/SKILL.md 'Read `skills/other/missing.md` first.'
run_check "$r"
expect "a root-relative path in a core skill file that is missing fails" 1 "FAIL: references skills/sample/SKILL.md names skills/other/missing.md, but it is missing"
r=$(repo) || exit 1
put "$r" plugins/mentat-sample/skills/demo/SKILL.md 'Read `skills/other/missing.md` first.'
run_check "$r"
expect "a root-relative path in a module skill file that is missing fails" 1 "FAIL: references plugins/mentat-sample/skills/demo/SKILL.md names skills/other/missing.md, but it is missing"

# A CREDITS.md path that cites another repository, in parentheses right after its link, is not checked;
# one that names a file here is.
r=$(repo) || exit 1
put "$r" skills/sample/CREDITS.md 'Adapted from [sample/skills](https://example.com/sample/skills) (`skills/upstream/SKILL.md`); `skills/other/CREDITS.md` has the details.'
put "$r" skills/other/CREDITS.md 'Credits.'
run_check "$r"
expect "a CREDITS.md path citing another repository is skipped and a local one is checked" 0 "PASS: references skills/sample/CREDITS.md names skills/other/CREDITS.md, which exists"
r=$(repo) || exit 1
put "$r" skills/sample/CREDITS.md 'Adapted from [sample/skills](https://example.com/sample/skills) (`skills/upstream/SKILL.md`); `skills/other/CREDITS.md` has the details.'
run_check "$r"
expect "a CREDITS.md path naming a missing file here fails" 1 "FAIL: references skills/sample/CREDITS.md names skills/other/CREDITS.md, but it is missing"

# A file name with an underscore is checked too: a missing one fails.
r=$(repo) || exit 1
put "$r" skills/sample/SKILL.md 'Read `../backlog/agent_records.md` first.'
run_check "$r"
expect "a relative path to a missing file whose name holds an underscore fails" 1 "FAIL: references skills/sample/SKILL.md names ../backlog/agent_records.md, but skills/sample/../backlog/agent_records.md is missing"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
