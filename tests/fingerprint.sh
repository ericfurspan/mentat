#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat fingerprint`, run through bin/mentat on invented files.
# Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'chmod -R u+rwx "$root" 2>/dev/null; rm -rf "$root"' EXIT
D="$root/a dir"
mkdir -p "$D"
failures=0
check() { if eval "$2"; then printf 'PASS: fingerprint %s\n' "$1"; else printf 'FAIL: fingerprint %s\n' "$1"; failures=$((failures + 1)); fi; }

# The request text and fingerprint tests/status.sh and tests/review-local.sh use, so the
# value is the one mentat review --request records and mentat status compares.
REQ_TEXT=$'Make the README say change.\nLeave every other file alone.\nChecked by reading README.'
REQ_FP=71fca9a263e9
printf '%s\n' "$REQ_TEXT" >"$D/agreed request.md"
printf '%s\n\n\n' "$REQ_TEXT" >"$D/trailing newlines.md"
printf 'Something else.\n' >"$D/other.md"
printf ' \n\t\n\n' >"$D/blank.md"
: >"$D/empty.md"
printf '%s\n' "$REQ_TEXT" >"$D/unreadable.md"
chmod 000 "$D/unreadable.md"

run() { "$mentat" fingerprint "$@" >"$root/out" 2>"$root/err"; echo $?; }
out() { cat "$root/out"; }

rc=$(run "$D/agreed request.md")
check "prints the request's fingerprint, the value mentat review records (exit 0)" '[ "$rc" = 0 ] && [ "$(out)" = "$REQ_FP" ] && [ ! -s "$root/err" ]'
rc=$(run "$D/trailing newlines.md")
check "trailing newlines do not change it, as read_request reads the file (exit 0)" '[ "$rc" = 0 ] && [ "$(out)" = "$REQ_FP" ]'
rc=$(run "$D/agreed request.md" "$REQ_FP")
check "matching the expected value: exit 0, both printed" '[ "$rc" = 0 ] && [ "$(out)" = "fingerprint $REQ_FP, expected $REQ_FP: match" ]'
rc=$(run "$D/other.md" "$REQ_FP")
check "differing from the expected value: exit 1, both printed" '[ "$rc" = 1 ] && [ "$(out)" = "fingerprint $(printf "Something else." | shasum -a 256 | cut -c1-12), expected $REQ_FP: differs" ]'
for f in missing.md blank.md empty.md unreadable.md; do
  for exp in "" "$REQ_FP"; do
    if [ -n "$exp" ]; then rc=$(run "$D/$f" "$exp"); else rc=$(run "$D/$f"); fi
    check "$f${exp:+ with an expected value}: exit 2, no fingerprint printed, the reason named" '[ "$rc" = 2 ] && [ ! -s "$root/out" ] && grep -qF "$D/$f" "$root/err"'
  done
done

for args in "" "a b c"; do
  # shellcheck disable=SC2086 # the words are the arguments
  rc=$(run $args)
  check "usage error (exit 64) for: mentat fingerprint $args" '[ "$rc" = 64 ] && grep -qF "usage: mentat fingerprint <file> [<expected>]" "$root/err" && [ ! -s "$root/out" ]'
done
rc=$("$mentat" nonsense >/dev/null 2>"$root/err"; echo $?)
check "mentat's usage names mentat fingerprint" '[ "$rc" = 64 ] && grep -qF "| mentat fingerprint <file> [<expected>]" "$root/err"'

[ "$failures" -eq 0 ]
