#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat review`, which waits for the Codex GitHub app's
# result, using a stub gh. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: review %s\n' "$1"; else printf 'FAIL: review %s\n' "$1"; failures=$((failures + 1)); fi; }

# gh pr view serves pr.json; from the second call on, later.json when it exists.
# gh api serves timeline.json, reviews.json, reactions.json and comments.json.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "repo view") echo owner/repo ;;
  "pr view")
    n=$(($(cat "$STUB/pr_calls" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/pr_calls"
    f="$STUB/pr.json"; [ "$n" -ge 2 ] && [ -f "$STUB/later.json" ] && f="$STUB/later.json"
    for a in "$@"; do [ "$a" = .headRefOid ] && { jq -r .headRefOid "$f"; exit 0; }; done
    cat "$f" ;;
  "api --paginate")
    case "$3" in
      */timeline) cat "$STUB/timeline.json" 2>/dev/null || echo '[]' ;;
      */reviews) cat "$STUB/reviews.json" 2>/dev/null || echo '[]' ;;
      */reactions) cat "$STUB/reactions.json" 2>/dev/null || echo '[]' ;;
      */comments) cat "$STUB/comments.json" 2>/dev/null || echo '[]' ;;
      *) exit 99 ;;
    esac ;;
  *) exit 99 ;;
esac
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_REVIEW_TIMEOUT_SECONDS=2

APP='chatgpt-codex-connector[bot]'
H=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
READY=2026-01-01T00:10:00Z
reset() {
  rm -f "$STUB"/*
  printf '{"headRefOid":"%s","isDraft":false,"createdAt":"2026-01-01T00:00:00Z"}\n' "$H" >"$STUB/pr.json"
  printf '[{"event":"ready_for_review","created_at":"2026-01-01T00:05:00Z"},{"event":"ready_for_review","created_at":"%s"}]\n' "$READY" >"$STUB/timeline.json"
}
review() { printf '{"user":{"login":"%s"},"commit_id":"%s","html_url":"https://example.test/review"}' "$1" "$2"; }
thumbs() { printf '{"user":{"login":"%s"},"content":"+1","created_at":"%s"}' "$1" "$2"; }
run() { "$mentat" review 7 >"$STUB/out" 2>&1; echo $?; }

reset; printf '[%s]\n' "$(thumbs "$APP" 2026-01-01T00:11:00Z)" >"$STUB/reactions.json"; rc=$(run)
check "a 👍 after the latest ready is clean (exit 0)" '[ "$rc" = 0 ] && grep -q "found nothing on $H" "$STUB/out"'
reset; printf '[%s]\n' "$(thumbs "$APP" 2026-01-01T00:06:00Z)" >"$STUB/reactions.json"; rc=$(run)
check "a 👍 from before the latest ready does not count" '[ "$rc" = 1 ] && grep -q "no result from the Codex app" "$STUB/out"'
reset; printf '[%s]\n' "$(thumbs someone 2026-01-01T00:11:00Z)" >"$STUB/reactions.json"; rc=$(run)
check "a 👍 from someone else does not count" '[ "$rc" = 1 ]'
reset; printf '[%s]\n' "$(review "$APP" "$H")" >"$STUB/reviews.json"
printf '[{"user":{"login":"%s"},"commit_id":"%s","path":"README.md","line":12,"html_url":"https://example.test/c1"}]\n' "$APP" "$H" >"$STUB/comments.json"; rc=$(run)
check "a review of the head reports findings (exit 2)" '[ "$rc" = 2 ] && grep -q "posted findings on $H: https://example.test/review" "$STUB/out" && grep -q "README.md:12 https://example.test/c1" "$STUB/out"'
reset; printf '[%s]\n' "$(review "$APP" "$OLD")" >"$STUB/reviews.json"; rc=$(run)
check "a review of an older commit does not count" '[ "$rc" = 1 ]'
reset; printf '[%s]\n' "$(review "$APP" "$H")" >"$STUB/reviews.json"; printf '[%s]\n' "$(thumbs "$APP" 2026-01-01T00:11:00Z)" >"$STUB/reactions.json"; rc=$(run)
check "findings on the head win over a 👍" '[ "$rc" = 2 ]'
reset; rc=$(run)
check "no result in time is not reviewed (exit 1)" '[ "$rc" = 1 ] && grep -q "no result from the Codex app on $H" "$STUB/out"'
reset; printf '{"headRefOid":"%s","isDraft":true,"createdAt":"2026-01-01T00:00:00Z"}\n' "$H" >"$STUB/pr.json"; rc=$(run)
check "a draft is not reviewed" '[ "$rc" = 1 ] && grep -q "is a draft" "$STUB/out" && ! grep -q reactions "$STUB/calls"'
reset; printf '{"headRefOid":"%s","isDraft":false}\n' "$OLD" >"$STUB/later.json"; rc=$(run)
check "a moved head exits 3" '[ "$rc" = 3 ]'
reset; echo '[]' >"$STUB/timeline.json"; printf '[%s]\n' "$(thumbs "$APP" 2026-01-01T00:01:00Z)" >"$STUB/reactions.json"; rc=$(run)
check "without a ready event, a 👍 after creation counts" '[ "$rc" = 0 ]'
check "makes no writes" '! grep -q -- "-X\|--method\|-f \|pr ready\|pr comment" "$STUB/calls"'
rc=$("$mentat" review abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
