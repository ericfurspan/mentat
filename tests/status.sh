#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat status`, using a stub gh and a stub git. Prints PASS/FAIL
# per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/work dir"
failures=0
check() { if eval "$2"; then printf 'PASS: status %s\n' "$1"; else printf 'FAIL: status %s\n' "$1"; failures=$((failures + 1)); fi; }

# gh answers the reads mentat status makes from files in $STUB; any other call is
# recorded in $STUB/writes and fails. git is never needed: any call is a write.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$*" in
  "repo view --json nameWithOwner --jq .nameWithOwner") echo owner/repo ;;
  "api user --jq .login") echo mentat-bot ;;
  "pr view 7 --json headRefOid --jq .headRefOid") cat "$STUB/head" ;;
  "api --paginate repos/owner/repo/issues/7/comments") [ -f "$STUB/no_comments" ] && exit 1; cat "$STUB/comments" ;;
  "api --paginate repos/owner/repo/commits/$(cat "$STUB/head")/check-runs") cat "$STUB/checks" ;;
  *) echo "$*" >>"$STUB/writes"; exit 99 ;;
esac
STUBEOF
cat >"$root/bin/git" <<'STUBEOF'
#!/usr/bin/env bash
echo "git $*" >>"$STUB/writes"; exit 99
STUBEOF
chmod +x "$root/bin/gh" "$root/bin/git"
export PATH="$root/bin:$PATH"

OLD=1111111111111111111111111111111111111111
H=2222222222222222222222222222222222222222
# The request text and fingerprint tests/review-local.sh checks `mentat review --request` posts.
REQ_TEXT=$'Make the README say change.\nLeave every other file alone.\nChecked by reading README.'
REQ_FP=71fca9a263e9
printf '%s\n' "$REQ_TEXT" >"$root/work dir/agreed request.md"
printf 'Something else.\n' >"$root/work dir/other request.md"

reset() { rm -f "$STUB"/*; printf '%s\n' "$H" >"$STUB/head"; echo '[]' >"$STUB/comments"; echo '{"check_runs": []}' >"$STUB/checks"; }
# comment <login> <body>: adds a comment, oldest first.
comment() { jq --arg u "$1" --arg b "$2" '. + [{user: {login: $u}, body: $b}]' "$STUB/comments" >"$STUB/c.tmp" && mv "$STUB/c.tmp" "$STUB/comments"; }
# checks <status> <conclusion> ...: the head's check runs, one pair each.
checks() {
  local runs="[]"
  while [ $# -ge 2 ]; do
    runs=$(jq --arg s "$1" --arg c "$2" '. + [{name: "tests", status: $s, conclusion: (if $c == "-" then null else $c end), completed_at: "2026-01-01T00:00:00Z"}]' <<<"$runs")
    shift 2
  done
  jq -n --argjson r "$runs" '{check_runs: $r}' >"$STUB/checks"
}
# The headings exactly as lib/review.sh, plugins/mentat-reviewers/lib/grok.sh and skills/claude-review write them.
local_review() { comment "${4:-mentat-bot}" "## Local $5 review of $1: $2, spec fingerprint ${3:-none}

<details><summary>Full review</summary>

- Agreed request fingerprint: ${3:-none}
</details>

REVIEW RESULT: X"; }
codex() { local_review "$1" "$2" "${3:-none}" mentat-bot Codex; }
claude_local() { local_review "$1" "$2" "${3:-none}" "${4:-mentat-bot}" Claude; }
grok() { comment mentat-bot "## Local Grok review of $1: $2, spec fingerprint ${3:-none}

REVIEW RESULT: X"; }
run() { (cd "$root/work dir" && "$mentat" status "$@" >"$STUB/out" 2>"$STUB/err"); echo $?; }
line() { [ "$(cat "$STUB/out")" = "$1" ]; }
read_only() { [ ! -f "$STUB/writes" ] && [ -z "$(find "$root/work dir" -newer "$STUB/head" -print -quit)" ]; }

reset; rc=$(run 7)
check "with no reviews prints one line: no rounds, no review yet, no Grok, no Codex, no CI" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none"'
check "reads only: posts, edits and pushes nothing" 'read_only && ! grep -qv -e "^repo view " -e "^api user " -e "^pr view 7 " -e "^api --paginate repos/owner/repo/" "$STUB/calls"'

reset; claude_local "$H" findings; codex "$H" findings; comment mentat-bot "Grok review started on $H"; grok "$H" "no findings"; checks completed success; rc=$(run 7)
check "a reviewed head: one Claude round, head reviewed, Grok done, Codex done on it, CI passed" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: done, grok stop: none, codex: done on 2222222 (findings, spec fingerprint none), ci: passed"'

# The head moved after the last reviews: the reviews posted stay the old head's record.
reset; claude_local "$OLD" findings; codex "$OLD" "no findings"; codex "$H" findings; comment mentat-bot "Grok review started on $OLD"; checks completed success in_progress -; rc=$(run 7)
check "the head moved after the last review: names the last reviewed commit, Codex is still reported on it; Grok running, CI running" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: no (last reviewed 1111111), grok: running, grok stop: none, codex: done on 1111111 (no findings, spec fingerprint none), ci: running"'

reset; claude_local "$OLD" findings; claude_local "$H" incomplete; codex "$H" "no findings"; comment mentat-bot "Grok review started on $OLD"
comment mentat-bot "Grok review did not finish on $OLD: Grok exited with status 1"; checks completed success completed failure; rc=$(run 7)
check "an incomplete Local Claude review is not a round and not a reviewed head, and a Codex review there is not reported; Grok did not finish; CI failed" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: no (last reviewed 1111111), grok: did not finish, grok stop: none, codex: none, ci: failed"'

reset; claude_local "$H" findings; comment mentat-bot "Grok review started on $H"; grok "$H" incomplete; rc=$(run 7)
check "a Grok review posted as incomplete did not finish" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: did not finish, grok stop: none, codex: none, ci: none"'

reset; claude_local "$OLD" findings; claude_local "$H" "no findings"; codex "$H" findings; comment someone-else "## Local Codex review of $H: no findings, spec fingerprint none"
comment someone-else "## Local Claude review of $OLD: findings, spec fingerprint none"
comment someone-else "Grok review started on $H"; comment someone-else "Claude review round 3 on $OLD"; rc=$(run 7)
check "counts only comments by the account gh is signed in as" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint none), ci: none"'

# Local Claude reviews are the local rounds, with the last one's head and fingerprint.
reset; claude_local "$OLD" findings; claude_local "$H" "no findings" "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Local Claude reviews count as rounds, with the last one's head and spec fingerprint" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: matches"'
reset; claude_local "$OLD" findings; codex "$H" findings "$REQ_FP"; claude_local "$H" incomplete; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "a Local Codex review is not a round and does not mark its head reviewed or set the spec, and an incomplete Local Claude review is not a round" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: no (last reviewed 1111111), grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review none, file $REQ_FP)"'
reset; claude_local "$OLD" findings; claude_local "$H" findings none someone-else; rc=$(run 7)
check "a Local Claude review by another account does not count" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: no (last reviewed 1111111), grok: none, grok stop: none, codex: none, ci: none"'
reset; comment mentat-bot "Grok review started on $H"; grok "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Grok's plain review is not a round" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: done, grok stop: none, codex: none, ci: none, spec: no review yet"'

# The codex field: Codex's state on the last head Claude reviewed, from the latest Codex
# comment there, whichever review posted first.
OTHER_FP=000000000000
reset; codex "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "a Codex review alone is no round, marks nothing reviewed, and with no Claude review the codex field is none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none, spec: no review yet"'
reset; claude_local "$H" findings; codex "$H" incomplete; rc=$(run 7)
check "an incomplete Codex review posted on Claude's head did not finish on it" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: did not finish on 2222222, ci: none"'
reset; claude_local "$H" findings; codex "$H" incomplete; codex "$H" "no findings"; rc=$(run 7)
check "a Codex review done after an incomplete one on the same head is done" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (no findings, spec fingerprint none), ci: none"'
reset; claude_local "$H" findings; codex "$H" "no findings"; codex "$H" incomplete; rc=$(run 7)
check "an incomplete Codex review after a done one on the same head did not finish" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: did not finish on 2222222, ci: none"'
BOTH="head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint $REQ_FP, spec matches), ci: none, spec: matches"
reset; codex "$H" findings "$REQ_FP"; claude_local "$H" "no findings" "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Codex's comment before Claude's on the same head: Codex done, spec matches" '[ "$rc" = 0 ] && line "$BOTH"'
reset; claude_local "$H" "no findings" "$REQ_FP"; codex "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Codex's comment after Claude's on the same head: the same line" '[ "$rc" = 0 ] && line "$BOTH"'
reset; claude_local "$H" findings "$OTHER_FP"; codex "$H" findings "$OTHER_FP"; claude_local "$H" "no findings" "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "the spec changed on one head: Claude's last review matches it, Codex's review of the old spec differs" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint $OTHER_FP, spec differs), ci: none, spec: matches"'
reset; codex "$H" "no findings" "$REQ_FP"; comment mentat-bot "Claude review round 1 on ${H:0:7}

Agreed request fingerprint: $REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "a Claude review round on a short head: Codex on that head is reported, the head is reviewed, the spec matches" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, claude rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (no findings, spec fingerprint $REQ_FP, spec matches), ci: none, spec: matches"'

# The Grok stop review has its own field; the grok field reads only the plain review.
stop_review() { comment "${4:-mentat-bot}" "## Local Grok stop review of $1: $2, spec fingerprint ${3:-none}

REVIEW RESULT: X"; }
reset; comment mentat-bot "Grok stop review started on $H"; rc=$(run 7)
check "a stop review's start comment alone: stop running on its head, grok none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: running on 2222222, codex: none, ci: none"'
reset; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" "no findings" "$REQ_FP"; rc=$(run 7)
check "a posted stop review: done, with its head, result and spec fingerprint; grok none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: done on 2222222 (no findings, spec fingerprint $REQ_FP), codex: none, ci: none"'
reset; comment mentat-bot "Grok stop review started on $OLD"; comment mentat-bot "Grok stop review did not finish on $OLD: Grok exited with status 1"; rc=$(run 7)
check "a stop review that did not finish names its head" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: did not finish on 1111111, codex: none, ci: none"'
reset; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" incomplete; rc=$(run 7)
check "a stop review posted as incomplete did not finish" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: did not finish on 2222222, codex: none, ci: none"'
reset; claude_local "$H" findings; comment mentat-bot "Grok review started on $OLD"; grok "$OLD" findings; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" findings "$REQ_FP"; rc=$(run 7)
check "a plain review and a stop review: each in its own field" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: done, grok stop: done on 2222222 (findings, spec fingerprint $REQ_FP), codex: none, ci: none"'
reset; comment mentat-bot "Grok review started on $OLD"; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" findings; rc=$(run 7)
check "a stop review does not change a plain run still running" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: running, grok stop: done on 2222222 (findings, spec fingerprint none), codex: none, ci: none"'
reset; comment someone-else "Grok stop review started on $H"; stop_review "$H" findings none someone-else; comment someone-else "Grok stop review did not finish on $H: x"; rc=$(run 7)
check "a stop review by another account does not count" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none"'

reset; comment mentat-bot "Claude review round 1 on ${OLD:0:7}

Agreed request fingerprint: 000000000000"; comment mentat-bot "Claude review round 2 on ${H:0:7}

No findings.
Agreed request fingerprint: $REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Claude review rounds are counted when present, a short head matches, and the spec fingerprint matches" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, claude rounds 2, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: matches"'

reset; claude_local "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request: the fingerprint matches as mentat review --request computes it (a path with spaces works)" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: matches"'
other=$(printf '%s' "$(cat "$root/work dir/other request.md")" | shasum -a 256 | cut -c1-12)
rc=$(run 7 --request "$root/work dir/other request.md")
check "--request: a different spec is told apart, with both fingerprints" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review $REQ_FP, file $other)"'
reset; claude_local "$H" findings; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request: a review without a fingerprint differs" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review none, file $REQ_FP)"'
reset; claude_local "$OLD" findings; comment mentat-bot "Claude review round 1 on ${H:0:7}

No findings."; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request: a Claude round without a fingerprint line reads as none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1, claude rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review none, file $REQ_FP)"'
reset; comment mentat-bot "Claude review round 1 on ${H:0:7}

The Codex comment says Agreed request fingerprint: 000000000000 for an older request.
> - Agreed request fingerprint: 000000000000

Agreed request fingerprint: $REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request: a Claude round's fingerprint is its own record line, not one quoted in its findings" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, claude rounds 1, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: matches"'
reset; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request with no review yet says so" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none, spec: no review yet"'
reset; rc=$(run 7 --request "$root/no such file.md")
check "--request with a missing file cannot read (exit 1) and reads nothing from GitHub" '[ "$rc" = 1 ] && grep -q "could not read the agreed request file" "$STUB/err" && [ ! -f "$STUB/calls" ]'

reset; touch "$STUB/no_comments"; rc=$(run 7)
check "comments that cannot be read are an error (exit 1), not a status" '[ "$rc" = 1 ] && [ ! -s "$STUB/out" ] && grep -q "could not read the comments on #7" "$STUB/err"'

for args in "" "x" "7 8" "7 --request" "--request $root/x 7" "7 --other f"; do
  reset
  # shellcheck disable=SC2086 # split on purpose
  rc=$(run $args)
  check "usage error (exit 64) for: mentat status $args" '[ "$rc" = 64 ] && grep -q "usage: mentat status <pull request number> \[--request <file>\]" "$STUB/err" && [ ! -f "$STUB/calls" ]'
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi
