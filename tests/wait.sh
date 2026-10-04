#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat wait`, using a stub gh. Prints PASS/FAIL per case;
# exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: wait %s\n' "$1"; else printf 'FAIL: wait %s\n' "$1"; failures=$((failures + 1)); fi; }

# gh pr view serves later.json from the third call on when it exists, so a
# case can change what GitHub reports after the first poll.
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo '{"nameWithOwner":"maint/repo"}' ;;
  "api user") [ -f "$STUB/user_fail" ] && exit 1; echo agent ;;
  "api --paginate")
    # api_fail fails every read after the first (the wait's start check); api_fail_all fails them all.
    a=$(($(cat "$STUB/api_calls" 2>/dev/null || echo 0) + 1)); echo "$a" >"$STUB/api_calls"
    { [ -f "$STUB/api_fail_all" ] || { [ -f "$STUB/api_fail" ] && [ "$a" -ge 2 ]; }; } && exit 1
    cat "$STUB/inline.json" 2>/dev/null || echo '[]' ;;
  "pr view")
    n=$(($(cat "$STUB/calls" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/calls"
    if [ "$n" -ge 3 ] && [ -f "$STUB/later.json" ]; then cat "$STUB/later.json"; else cat "$STUB/pr.json"; fi ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH" MENTAT_WAIT_INTERVAL_SECONDS=1 MENTAT_WAIT_LIMIT_SECONDS=3

H=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
# pr_json <state> <head> <reviews> <comments>
pr_json() { printf '{"state":"%s","headRefOid":"%s","reviews":[%s],"comments":[%s]}\n' "$@"; }
review() { printf '{"author":{"login":"%s"},"state":"%s","commit":{"oid":"%s"},"submittedAt":"%s","body":"%s"}' "$1" "$2" "$3" "$4" "${5:-}"; }
comment() { printf '{"author":{"login":"%s"},"createdAt":"%s","body":"%s"}' "$1" "$2" "${3:-}"; }
# inline <id> <in_reply_to_id or null> <login> <created_at>
inline() { printf '{"id":%s,"in_reply_to_id":%s,"user":{"login":"%s"},"created_at":"%s"}' "$@"; }
LATE=2999-01-01T00:00:00Z
EARLY=2000-01-01T00:00:00Z
EARLY2=2001-01-01T00:00:00Z
case_with() { rm -f "$STUB"/*; pr_json OPEN "$H" "$1" "$2" >"$STUB/pr.json"; }
run() { "$mentat" wait 5 >/dev/null 2>&1; echo $?; }

case_with "$(review maint APPROVED "$H" "$EARLY")" ""; rc=$(run)
check "approval at the current head exits 0" '[ "$rc" = 0 ]'
case_with "$(review maint CHANGES_REQUESTED "$H" "$EARLY"),$(review maint APPROVED "$H" "$LATE")" ""; rc=$(run)
check "a later approval replaces requested changes" '[ "$rc" = 0 ]'
case_with "" ""; pr_json OPEN "$H" "$(review maint APPROVED "$H" "$LATE")" "" >"$STUB/later.json"; rc=$(run)
check "an approval arriving on a later poll exits 0" '[ "$rc" = 0 ]'
case_with "$(review maint APPROVED "$OLD" "$EARLY")" ""; rc=$(run)
check "an approval of an older commit does not count" '[ "$rc" = 2 ]'
case_with "$(review someone APPROVED "$H" "$LATE")" ""; rc=$(run)
check "an approval from someone else does not count" '[ "$rc" = 2 ]'
case_with "$(review maint APPROVED "$H" "$EARLY")" "$(comment maint "$LATE")"; rc=$(run)
check "an approval followed by a maintainer comment exits 1" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY"),$(review maint COMMENTED "$H" "$LATE")" ""; rc=$(run)
check "an approval followed by a maintainer comment review exits 1" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY")" ""
printf '[%s]\n' "$(inline 1 null maint "$LATE")" >"$STUB/inline.json"; rc=$(run)
check "an approval followed by a maintainer inline reply exits 1" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY2")" ""
printf '[%s,%s]\n' "$(inline 1 null maint "$EARLY")" "$(inline 2 1 agent "$EARLY2")" >"$STUB/inline.json"; rc=$(run)
check "an answered inline comment from before the start is ignored" '[ "$rc" = 0 ]'
case_with "$(review maint APPROVED "$H" "$EARLY2")" ""
printf '[%s]\n' "$(inline 1 null maint "$EARLY")" >"$STUB/inline.json"; rc=$(run)
check "an unanswered inline comment from before the start exits 1" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY2")" ""
printf '[%s,%s,%s]\n' "$(inline 1 null maint "$EARLY")" "$(inline 3 null maint "$EARLY")" "$(inline 2 3 agent "$EARLY2")" >"$STUB/inline.json"; rc=$(run)
check "an agent reply in another thread does not answer an inline comment" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY2")" ""
printf '[%s,%s]\n' "$(inline 1 null agent "$EARLY")" "$(inline 2 1 maint "$EARLY2")" >"$STUB/inline.json"; rc=$(run)
check "a maintainer reply after the agent's comment is unanswered" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY")" ""
big=$(head -c 40000 /dev/zero | tr '\0' x)
jq -n --arg b "$big" --arg t "$LATE" '[range(30) | {user: {login: "maint"}, created_at: $t, body: $b}]' >"$STUB/inline.json"; rc=$(run)
check "a large set of new inline comments still stops an approval" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY")" ""; touch "$STUB/api_fail"; rc=$(run)
check "an approval is not accepted when comments cannot be read" '[ "$rc" = 2 ]'
case_with "" ""; touch "$STUB/api_fail"; pr_json CLOSED "$H" "" "" >"$STUB/later.json"; rc=$(run)
check "a closed pull request is reported even when comments cannot be read" '[ "$rc" = 1 ]'
case_with "$(review maint APPROVED "$H" "$EARLY")" ""; touch "$STUB/api_fail_all"; rc=$(run)
check "comments that cannot be read at the start exit 1" '[ "$rc" = 1 ]'
case_with "$(review maint CHANGES_REQUESTED "$H" "$LATE")" ""; rc=$(run)
check "requested changes exit 1" '[ "$rc" = 1 ]'
case_with "" "$(comment maint "$LATE")"; rc=$(run)
check "a maintainer comment after the start exits 1" '[ "$rc" = 1 ]'
case_with "$(review maint COMMENTED "$H" "$LATE")" ""; rc=$(run)
check "a maintainer comment review after the start exits 1" '[ "$rc" = 1 ]'
case_with "" "$(comment maint "$EARLY"),$(comment agent "$EARLY2")"; rc=$(run)
check "an answered maintainer comment before the start is ignored" '[ "$rc" = 2 ]'
case_with "" "$(comment maint "$EARLY")"; rc=$(run)
check "an unanswered maintainer comment before the start exits 1" '[ "$rc" = 1 ]'
case_with "" "$(comment maint "$EARLY"),$(comment agent "$EARLY2" "## Local Codex review, posted by the agent")"; rc=$(run)
check "a posted review does not answer a maintainer comment" '[ "$rc" = 1 ]'
case_with "$(review maint COMMENTED "$H" "$EARLY" "Please rename this")" ""; rc=$(run)
check "an unanswered maintainer comment review before the start exits 1" '[ "$rc" = 1 ]'
case_with "$(review maint COMMENTED "$H" "$EARLY")" ""; rc=$(run)
check "an empty comment review before the start is ignored" '[ "$rc" = 2 ]'
case_with "" ""; touch "$STUB/user_fail"; rc=$(run)
check "the signed-in user cannot be read exits 1" '[ "$rc" = 1 ]'
case_with "" "$(comment someone "$LATE")"; rc=$(run)
check "a comment from someone else is ignored" '[ "$rc" = 2 ]'
case_with "" ""; pr_json OPEN "$OLD" "" "" >"$STUB/later.json"; rc=$(run)
check "a moved head exits 1" '[ "$rc" = 1 ]'
case_with "" ""; pr_json CLOSED "$H" "" "" >"$STUB/later.json"; rc=$(run)
check "a closed pull request exits 1" '[ "$rc" = 1 ]'
case_with "" ""; rc=$(run)
check "no response within the limit exits 2" '[ "$rc" = 2 ]'
rc=$("$mentat" wait abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
