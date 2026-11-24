#!/usr/bin/env bash
# Checks files against a glossary's Avoid lines.
# Usage: tests/glossary-check.sh <glossary> <covered-list> <not-yet-rewritten-list>
# Each list file holds one path a line. Every covered file not on the not-yet-rewritten list is
# checked; a listed file that is not a covered file or is not on disk fails, so the list stays
# true.
#
# The glossary's format: each entry starts at a "## <word>" heading, the word to use. In an entry,
# "Avoid: a, b" names words or phrases not to use, matched case-insensitively on word boundaries
# with plural, -ed and -ing forms of the last word, hyphens and spaces alike; "Avoid (whole
# phrase): a, b" matches only the exact phrase, in any case, its words separated by whitespace and
# no letter, digit or hyphen on either side; "Avoid: none" names nothing; and an
# "Ambiguous:" line flags the entry's word, which is counted, never failed. Every entry has an
# Avoid line. Other lines, the meaning included, are never read as words to avoid.
#
# In a checked file, code spans, fenced blocks, link targets, URLs, paths, file names and
# frontmatter other than description are skipped; as in CommonMark, a code span ends only at a run
# of as many backticks as opened it, and a fenced block only at a fence of its opening character
# at least as long. A path is a word holding a / that starts with /, ./, ../ or ~, ends with /,
# holds a glob * beside a /, or ends in a file extension; other words joined by a slash are prose.
# A phrase may run across a line break inside a
# paragraph (consecutive prose lines; a blank line, heading, list item, table row or fence ends
# one) and is named at the line it starts on. A sentence over 20 words (code
# spans, list markers and fenced blocks skipped) is counted in the file's PASS line.
# tests/glossary-check.awk does the matching. Prints PASS/FAIL lines; exits 1 on any FAIL.
set -uo pipefail

failures=0
fail() { printf 'FAIL: glossary %s\n' "$1"; failures=$((failures + 1)); }

if [ "$#" -ne 3 ]; then
  fail "usage: tests/glossary-check.sh <glossary> <covered-list> <not-yet-rewritten-list>"
  exit 1
fi
glossary=$1 covered=$2 listed=$3

if [ ! -s "$glossary" ]; then
  fail "$glossary is missing or empty"
  exit 1
fi
for list in "$covered" "$listed"; do
  if [ ! -f "$list" ]; then
    fail "list $list is missing"
    exit 1
  fi
done

nlisted=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  nlisted=$((nlisted + 1))
  if ! grep -qxF -- "$f" "$covered"; then
    fail "$f is listed as not yet rewritten but is not a covered file"
  elif [ ! -f "$f" ]; then
    fail "$f is listed as not yet rewritten but does not exist"
  fi
done <"$listed"

checked=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qxF -- "$f" "$listed" && continue
  if [ -f "$f" ]; then
    checked+=("$f")
  else
    fail "$f is a covered file but does not exist"
  fi
done <"$covered"

if ! awk -v G="$glossary" -f "$(dirname "$0")/glossary-check.awk" "$glossary" ${checked[@]+"${checked[@]}"}; then
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then exit 1; fi
printf 'PASS: glossary: %d file(s) checked, %d listed as not yet rewritten\n' "${#checked[@]}" "$nlisted"
