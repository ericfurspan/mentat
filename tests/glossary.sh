#!/usr/bin/env bash
# The glossary check (tests/glossary-check.sh) behaves as specified, on invented fixtures in
# tests/fixtures/glossary/: each input class below gets the outcome the glossary's spec gives it.
# Prints PASS/FAIL per check; exits 1 on any FAIL.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
pass() { printf 'PASS: glossary fixtures %s\n' "$1"; }
fail() { printf 'FAIL: glossary fixtures %s\n' "$1"; failures=$((failures + 1)); }

fx=tests/fixtures/glossary
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# run_check <glossary> <covered files> <files listed as not yet rewritten>, each list one path a line.
run_check() {
  printf '%s\n' "$2" >"$tmp/covered"
  printf '%s\n' "$3" >"$tmp/listed"
  out=$(tests/glossary-check.sh "$1" "$tmp/covered" "$tmp/listed" 2>&1)
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

g=$fx/glossary.md

# 3. A file holding an Avoid word fails, naming file, line and entry; one without passes.
run_check "$g" "$fx/avoid.md" ""
expect "an Avoid word fails" 1 "FAIL: glossary $fx/avoid.md:3: \"runner\" is avoided by entry \"courier\""
run_check "$g" "$fx/clean.md" ""
expect "a file with no Avoid word passes" 0 "PASS: glossary $fx/clean.md: no avoided words"

# a. Plural, -ed, -ing, hyphenated and capitalized forms match.
run_check "$g" "$fx/forms.md" ""
expect "a capitalized plural matches" 1 "$fx/forms.md:3: \"runner\""
expect "an -ed form matches" 1 "$fx/forms.md:4: \"signal\""
expect "an -ing form with a doubled consonant matches" 1 "$fx/forms.md:5: \"signal\""
expect "a hyphenated plural phrase matches" 1 "$fx/forms.md:6: \"parcel carrier\""
expect "a possessive matches" 1 "$fx/forms.md:7: \"signal\""

# b. Code spans, fenced blocks, link targets, paths, URLs, file names and frontmatter other than
# the description are skipped.
run_check "$g" "$fx/skipped.md" ""
expect "code spans, fences, link targets and paths are skipped" 0 "PASS: glossary $fx/skipped.md: no avoided words"

# c. A whole-phrase Avoid line matches only the exact phrase, in any case.
run_check "$g" "$fx/whole-forms.md" ""
expect "a whole-phrase Avoid word's other forms pass" 0 "PASS: glossary $fx/whole-forms.md: no avoided words"
run_check "$g" "$fx/whole-exact.md" ""
expect "a whole-phrase Avoid phrase itself fails" 1 "$fx/whole-exact.md:3: \"low water\" is avoided by entry \"tide\""

# d. A missing glossary, one whose Avoid lines name nothing, and an entry with no Avoid line fail.
run_check "$fx/absent.md" "$fx/clean.md" ""
expect "a missing glossary fails" 1 "FAIL: glossary $fx/absent.md is missing or empty"
run_check "$fx/no-words.md" "$fx/clean.md" ""
expect "Avoid lines that name nothing fail" 1 "FAIL: glossary $fx/no-words.md: its Avoid lines name no words"
run_check "$fx/no-avoid-line.md" "$fx/clean.md" ""
expect "an entry with no Avoid line fails" 1 "FAIL: glossary $fx/no-avoid-line.md: entry \"tide\" has no Avoid line"

# e. A file listed as not yet rewritten that is not a covered file, or that is still covered
# (tracked) but no longer on disk, fails.
run_check "$g" "$fx/clean.md" "$fx/gone.md"
expect "a listed file that no longer exists fails" 1 "FAIL: glossary $fx/gone.md is listed as not yet rewritten but is not a covered file"
run_check "$g" "$fx/clean.md
$fx/gone.md" "$fx/gone.md"
expect "a listed file deleted but still tracked fails" 1 "FAIL: glossary $fx/gone.md is listed as not yet rewritten but does not exist"

# f. One entry's word that is another entry's Avoid word, sits inside its Avoid phrase, or holds
# its Avoid word fails.
run_check "$fx/chosen-avoided.md" "$fx/clean.md" ""
expect "a chosen word that another entry avoids fails" 1 "FAIL: glossary $fx/chosen-avoided.md: entry \"runner\" is avoided by entry \"courier\" (\"runner\")"
run_check "$fx/chosen-inside.md" "$fx/clean.md" ""
expect "a chosen word inside another entry's Avoid phrase fails" 1 "FAIL: glossary $fx/chosen-inside.md: entry \"parcel\" is avoided by entry \"courier\" (\"parcel carrier\")"
run_check "$fx/chosen-holds.md" "$fx/clean.md" ""
expect "a chosen word holding another entry's Avoid word fails" 1 "FAIL: glossary $fx/chosen-holds.md: entry \"lamp runner\" holds \"runner\", avoided by entry \"courier\""

# g. A flagged word is counted in the PASS line, never a failure.
run_check "$g" "$fx/flagged.md" ""
expect "a flagged word is listed in the PASS line" 0 "PASS: glossary $fx/flagged.md: no avoided words; 0 sentence(s) over 20 words; flagged: harbor 3"

# h. The glossary's own meaning and Avoid lines name avoided words, are not checked and add no
# Avoid words of their own.
run_check "$g" "$fx/clean.md" ""
expect "the glossary's own lines are not checked" 0 "PASS: glossary $g: 3 entries, 5 avoided terms"

# i. Sentences over 20 words are counted, skipping code spans, list markers and fenced blocks.
run_check "$g" "$fx/long.md" ""
expect "long sentences are counted in the PASS line" 0 "PASS: glossary $fx/long.md: no avoided words; 1 sentence(s) over 20 words; flagged: none"

# j. A file still listed as not yet rewritten is not checked, whatever it holds.
run_check "$g" "$fx/avoid.md
$fx/clean.md" "$fx/avoid.md"
expect "a listed file is not checked" 0 "PASS: glossary: 1 file(s) checked, 1 listed as not yet rewritten"

if [ "$failures" -gt 0 ]; then exit 1; fi
