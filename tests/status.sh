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
unset MENTAT_REVIEW_ROUNDS

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
  "api repos/owner/repo --jq .owner.type") [ -f "$STUB/no_owner" ] && exit 1; cat "$STUB/owner_type" ;;
  "pr view 7 --json author,reviews") [ -f "$STUB/no_reviews" ] && exit 1; jq '{author, reviews}' "$STUB/pr" ;;
  "pr view 7 --json reviewRequests") [ -f "$STUB/no_requests" ] && exit 1; jq '{reviewRequests}' "$STUB/pr" ;;
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

# The pull request the owner reads use, as gh prints its fields: opened by mentat-bot in a
# repository the user "owner" owns, with no reviews and no review requested.
reset() {
  rm -f "$STUB"/*; printf '%s\n' "$H" >"$STUB/head"; echo '[]' >"$STUB/comments"; echo '{"check_runs": []}' >"$STUB/checks"
  echo User >"$STUB/owner_type"; echo '{"author": {"login": "mentat-bot"}, "reviews": [], "reviewRequests": []}' >"$STUB/pr"
}
pr_set() { jq "$@" "$STUB/pr" >"$STUB/p.tmp" && mv "$STUB/p.tmp" "$STUB/pr"; }
# review <login> <state> <commit>: adds a submitted review, each later than the one before.
review() { pr_set --arg u "$1" --arg s "$2" --arg c "$3" '.reviews += [{author: {login: $u}, state: $s, submittedAt: "2026-01-01T00:\(.reviews | length + 10):00Z", commit: {oid: $c}}]'; }
# request <login>: adds a requested reviewer; request_team <slug> a requested team.
request() { pr_set --arg u "$1" '.reviewRequests += [{__typename: "User", login: $u}]'; }
request_team() { pr_set --arg t "$1" '.reviewRequests += [{__typename: "Team", name: $t, slug: $t}]'; }
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
# The headings exactly as lib/review.sh and plugins/mentat-reviewers/lib/grok.sh write them.
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
check "with no reviews prints one line: no rounds, no review yet, no Grok, no Codex, no CI" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none, owner review: not requested"'
check "reads only: posts, edits and pushes nothing" 'read_only && ! grep -qv -e "^repo view " -e "^api user " -e "^pr view 7 " -e "^api --paginate repos/owner/repo/" -e "^api repos/owner/repo --jq " "$STUB/calls"'

reset; claude_local "$H" findings; codex "$H" findings; comment mentat-bot "Grok review started on $H"; grok "$H" "no findings"; checks completed success; rc=$(run 7)
check "a reviewed head: one local round, head reviewed, Grok done, Codex done on it, CI passed" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: done, grok stop: none, codex: done on 2222222 (findings, spec fingerprint none), ci: passed, owner review: not requested"'

# The head moved after the last reviews: the reviews posted stay the old head's record.
reset; claude_local "$OLD" findings; codex "$OLD" "no findings"; codex "$H" findings; comment mentat-bot "Grok review started on $OLD"; checks completed success in_progress -; rc=$(run 7)
check "the head moved after the last review: names the last reviewed commit, Codex is still reported on it; Grok running, CI running" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: no (last reviewed 1111111), grok: running, grok stop: none, codex: done on 1111111 (no findings, spec fingerprint none), ci: running, owner review: not requested"'

reset; claude_local "$OLD" findings; claude_local "$H" incomplete; codex "$H" "no findings"; comment mentat-bot "Grok review started on $OLD"
comment mentat-bot "Grok review did not finish on $OLD: Grok exited with status 1"; checks completed success completed failure; rc=$(run 7)
check "an incomplete Local Claude review is not a round and not a reviewed head, and a Codex review there is not reported; Grok did not finish; CI failed" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: no (last reviewed 1111111), grok: did not finish, grok stop: none, codex: none, ci: failed, owner review: not requested"'

reset; claude_local "$H" findings; comment mentat-bot "Grok review started on $H"; grok "$H" incomplete; rc=$(run 7)
check "a Grok review posted as incomplete did not finish" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: did not finish, grok stop: none, codex: none, ci: none, owner review: not requested"'

reset; claude_local "$OLD" findings; claude_local "$H" "no findings"; codex "$H" findings; comment someone-else "## Local Codex review of $H: no findings, spec fingerprint none"
comment someone-else "## Local Claude review of $OLD: findings, spec fingerprint none"
comment someone-else "Grok review started on $H"; rc=$(run 7)
check "counts only comments by the account gh is signed in as" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2 of 5, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint none), ci: none, owner review: not requested"'

# Local Claude reviews are the local rounds, with the last one's head and fingerprint.
reset; claude_local "$OLD" findings; claude_local "$H" "no findings" "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Local Claude reviews count as rounds, with the last one's head and spec fingerprint" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2 of 5, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: matches, owner review: not requested"'
reset; claude_local "$OLD" findings; codex "$H" findings "$REQ_FP"; claude_local "$H" incomplete; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "a Local Codex review is not a round and does not mark its head reviewed or set the spec, and an incomplete Local Claude review is not a round" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: no (last reviewed 1111111), grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review none, file $REQ_FP), owner review: not requested"'
reset; claude_local "$OLD" findings; claude_local "$H" findings none someone-else; rc=$(run 7)
check "a Local Claude review by another account does not count" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: no (last reviewed 1111111), grok: none, grok stop: none, codex: none, ci: none, owner review: not requested"'
reset; comment mentat-bot "Grok review started on $H"; grok "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Grok's plain review is not a round" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: done, grok stop: none, codex: none, ci: none, spec: no review yet, owner review: not requested"'

# The codex field: Codex's state on the last head Claude reviewed, from the latest Codex
# comment there, whichever review posted first.
OTHER_FP=000000000000
reset; codex "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "a Codex review alone is no round, marks nothing reviewed, and with no Claude review the codex field is none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none, spec: no review yet, owner review: not requested"'
reset; claude_local "$H" findings; codex "$H" incomplete; rc=$(run 7)
check "an incomplete Codex review posted on Claude's head did not finish on it" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: did not finish on 2222222, ci: none, owner review: not requested"'
reset; claude_local "$H" findings; codex "$H" incomplete; codex "$H" "no findings"; rc=$(run 7)
check "a Codex review done after an incomplete one on the same head is done" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (no findings, spec fingerprint none), ci: none, owner review: not requested"'
reset; claude_local "$H" findings; codex "$H" "no findings"; codex "$H" incomplete; rc=$(run 7)
check "an incomplete Codex review after a done one on the same head did not finish" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: did not finish on 2222222, ci: none, owner review: not requested"'
BOTH="head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint $REQ_FP, spec matches), ci: none, spec: matches, owner review: not requested"
reset; codex "$H" findings "$REQ_FP"; claude_local "$H" "no findings" "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Codex's comment before Claude's on the same head: Codex done, spec matches" '[ "$rc" = 0 ] && line "$BOTH"'
reset; claude_local "$H" "no findings" "$REQ_FP"; codex "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "Codex's comment after Claude's on the same head: the same line" '[ "$rc" = 0 ] && line "$BOTH"'
reset; claude_local "$H" findings "$OTHER_FP"; codex "$H" findings "$OTHER_FP"; claude_local "$H" "no findings" "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "the spec changed on one head: Claude's last review matches it, Codex's review of the old spec differs" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2 of 5, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint $OTHER_FP, spec differs), ci: none, spec: matches, owner review: not requested"'

# The Grok stop review has its own field; the grok field reads only the plain review.
stop_review() { comment "${4:-mentat-bot}" "## Local Grok stop review of $1: $2, spec fingerprint ${3:-none}

REVIEW RESULT: X"; }
reset; comment mentat-bot "Grok stop review started on $H"; rc=$(run 7)
check "a stop review's start comment alone: stop running on its head, grok none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: running on 2222222, codex: none, ci: none, owner review: not requested"'
reset; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" "no findings" "$REQ_FP"; rc=$(run 7)
check "a posted stop review: done, with its head, result and spec fingerprint; grok none" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: done on 2222222 (no findings, spec fingerprint $REQ_FP), codex: none, ci: none, owner review: not requested"'
reset; comment mentat-bot "Grok stop review started on $OLD"; comment mentat-bot "Grok stop review did not finish on $OLD: Grok exited with status 1"; rc=$(run 7)
check "a stop review that did not finish names its head" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: did not finish on 1111111, codex: none, ci: none, owner review: not requested"'
reset; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" incomplete; rc=$(run 7)
check "a stop review posted as incomplete did not finish" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: did not finish on 2222222, codex: none, ci: none, owner review: not requested"'
reset; claude_local "$H" findings; comment mentat-bot "Grok review started on $OLD"; grok "$OLD" findings; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" findings "$REQ_FP"; rc=$(run 7)
check "a plain review and a stop review: each in its own field" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: done, grok stop: done on 2222222 (findings, spec fingerprint $REQ_FP), codex: none, ci: none, owner review: not requested"'
reset; comment mentat-bot "Grok review started on $OLD"; comment mentat-bot "Grok stop review started on $H"; stop_review "$H" findings; rc=$(run 7)
check "a stop review does not change a plain run still running" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: running, grok stop: done on 2222222 (findings, spec fingerprint none), codex: none, ci: none, owner review: not requested"'
reset; comment someone-else "Grok stop review started on $H"; stop_review "$H" findings none someone-else; comment someone-else "Grok stop review did not finish on $H: x"; rc=$(run 7)
check "a stop review by another account does not count" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none, owner review: not requested"'

reset; claude_local "$H" findings "$REQ_FP"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request: the fingerprint matches as mentat review --request computes it (a path with spaces works)" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: matches, owner review: not requested"'
other=$(printf '%s' "$(cat "$root/work dir/other request.md")" | shasum -a 256 | cut -c1-12)
rc=$(run 7 --request "$root/work dir/other request.md")
check "--request: a different spec is told apart, with both fingerprints" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review $REQ_FP, file $other), owner review: not requested"'
reset; claude_local "$H" findings; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request: a review without a fingerprint differs" '[ "$rc" = 0 ] && line "head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, spec: differs (last review none, file $REQ_FP), owner review: not requested"'
reset; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "--request with no review yet says so" '[ "$rc" = 0 ] && line "head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none, spec: no review yet, owner review: not requested"'
# The owner review field, last on the line: the review of the repository's owner ("owner"),
# the first that holds. A read it needs that fails makes it unknown, and only it.
NONE="head 2222222, local rounds 0 of 5, head reviewed: no (no review yet), grok: none, grok stop: none, codex: none, ci: none"
reset; echo Organization >"$STUB/owner_type"; touch "$STUB/no_reviews" "$STUB/no_requests"; rc=$(run 7)
check "owner review: an organization's repository has no single owner, read before the reviews" '[ "$rc" = 0 ] && line "$NONE, owner review: no single owner"'
reset; pr_set '.author.login = "owner"'; touch "$STUB/no_requests"; rc=$(run 7)
check "owner review: the owner opened the pull request, read before the requested reviewers" '[ "$rc" = 0 ] && line "$NONE, owner review: author"'
reset; review owner COMMENTED "$OLD"; review owner APPROVED "$H"; review someone-else CHANGES_REQUESTED "$H"; request owner; rc=$(run 7)
check "owner review: the owner's latest review approves the head, though another account's came later and the owner is still requested" '[ "$rc" = 0 ] && line "$NONE, owner review: approved on head"'
reset; review owner APPROVED "$OLD"; review someone-else APPROVED "$H"; request_team reviewers; request owner; rc=$(run 7)
check "owner review: requested, when the owner approved only an older head and another account approved this one" '[ "$rc" = 0 ] && line "$NONE, owner review: requested"'
reset; review owner APPROVED "$H"; review owner COMMENTED "$H"; request someone-else; request_team owner; rc=$(run 7)
check "owner review: not requested, when a comment-only review on the head follows the owner's approval and only another account and a team are requested" '[ "$rc" = 0 ] && line "$NONE, owner review: not requested"'
FULL="head 2222222, local rounds 1 of 5, head reviewed: yes, grok: none, grok stop: none, codex: done on 2222222 (findings, spec fingerprint $REQ_FP, spec matches), ci: passed, spec: matches"
reset; claude_local "$H" findings "$REQ_FP"; codex "$H" findings "$REQ_FP"; checks completed success; touch "$STUB/no_reviews"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "owner review: reviews that cannot be read are unknown, and the rest of the line is as it was (exit 0)" '[ "$rc" = 0 ] && line "$FULL, owner review: unknown (could not read the reviews)"'
reset; claude_local "$H" findings "$REQ_FP"; codex "$H" findings "$REQ_FP"; checks completed success; review owner COMMENTED "$H"; touch "$STUB/no_requests"; rc=$(run 7 --request "$root/work dir/agreed request.md")
check "owner review: requested reviewers that cannot be read are unknown, and the rest of the line is as it was (exit 0)" '[ "$rc" = 0 ] && line "$FULL, owner review: unknown (could not read the requested reviewers)"'
reset; touch "$STUB/no_owner"; rc=$(run 7)
check "owner review: a repository owner that cannot be read is unknown, and the rest of the line is as it was (exit 0)" '[ "$rc" = 0 ] && line "$NONE, owner review: unknown (could not read the repository owner)"'

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

# The round limit in force, MENTAT_REVIEW_ROUNDS (5 when unset or empty), follows the local rounds.
reset; claude_local "$OLD" findings; claude_local "$H" findings; rc=$(MENTAT_REVIEW_ROUNDS=7 run 7)
check "MENTAT_REVIEW_ROUNDS=7: the local rounds are printed against 7" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2 of 7, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, owner review: not requested"'
rc=$(MENTAT_REVIEW_ROUNDS=10 run 7)
check "MENTAT_REVIEW_ROUNDS=10: the local rounds are printed against 10" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2 of 10, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, owner review: not requested"'
rc=$(MENTAT_REVIEW_ROUNDS='' run 7)
check "MENTAT_REVIEW_ROUNDS empty: the local rounds are printed against 5" '[ "$rc" = 0 ] && line "head 2222222, local rounds 2 of 5, head reviewed: yes, grok: none, grok stop: none, codex: none, ci: none, owner review: not requested"'
for bad in 0 abc 08 -1 1.5; do
  reset; rc=$(MENTAT_REVIEW_ROUNDS=$bad run 7)
  check "MENTAT_REVIEW_ROUNDS=$bad is a usage error (exit 64) that reads nothing from GitHub" '[ "$rc" = 64 ] && grep -qxF "mentat: MENTAT_REVIEW_ROUNDS must be a whole number of 1 or more, not $bad" "$STUB/err" && [ ! -s "$STUB/out" ] && [ ! -f "$STUB/calls" ]'
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi
