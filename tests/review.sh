#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat review`, which marks a pull request ready and waits
# for the Codex GitHub app's result, using a stub gh. Prints PASS/FAIL per case;
# exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: review %s\n' "$1"; else printf 'FAIL: review %s\n' "$1"; failures=$((failures + 1)); fi; }

# State lives in $STUB: head, draft, timeline.json, reviews.json, reactions.json,
# comments.json, check_runs.json (check_runs_later.json from the second read on)
# and status.json. "gh pr ready" records the call and appends a ready event at
# READY_AT; a file named push_on_ready holds a head to switch to at that moment.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "repo view") echo owner/repo ;;
  "pr view")
    case "$*" in
      *headRefOid*)
        n=$(($(cat "$STUB/head_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/head_reads"
        [ "$n" = "$(cat "$STUB/head_fails_at" 2>/dev/null)" ] && exit 1
        cat "$STUB/head" ;;
      *isDraft*) cat "$STUB/draft" ;;
      *) exit 99 ;;
    esac ;;
  "pr ready")
    if [ "${4:-}" = --undo ]; then echo true >"$STUB/draft"; exit 0; fi
    [ -f "$STUB/ready_fails" ] && exit 1
    echo false >"$STUB/draft"
    [ -f "$STUB/no_ready_event" ] || jq --arg t "$(cat "$STUB/ready_at")" '. + [{event: "ready_for_review", created_at: $t}]' \
      "$STUB/timeline.json" >"$STUB/t.new" && mv "$STUB/t.new" "$STUB/timeline.json"
    [ -f "$STUB/push_on_ready" ] && cp "$STUB/push_on_ready" "$STUB/head"
    [ -f "$STUB/reactions_after_ready" ] && cp "$STUB/reactions_after_ready" "$STUB/reactions.json"
    [ -f "$STUB/summary_after_ready" ] && cp "$STUB/summary_after_ready" "$STUB/issue_comments.json"
    exit 0 ;;
  "api --paginate")
    case "$3" in
      */timeline) cat "$STUB/timeline.json" ;;
      */reviews) [ -f "$STUB/reviews_fail" ] && exit 1; cat "$STUB/reviews.json" ;;
      */reactions) cat "$STUB/reactions.json" ;;
      */issues/*/comments) cat "$STUB/issue_comments.json" ;;
      */comments) cat "$STUB/comments.json" ;;
      */check-runs)
        n=$(($(cat "$STUB/ci_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/ci_reads"
        [ -f "$STUB/push_on_ci" ] && cp "$STUB/push_on_ci" "$STUB/head"
        if [ "$n" -ge 2 ] && [ -f "$STUB/check_runs_later.json" ]; then cat "$STUB/check_runs_later.json"; else cat "$STUB/check_runs.json"; fi ;;
      */status) cat "$STUB/status.json" ;;
      *) exit 99 ;;
    esac ;;
  *) exit 99 ;;
esac
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_REVIEW_TIMEOUT_SECONDS=2 MENTAT_CI_TIMEOUT_SECONDS=2 MENTAT_CI_GRACE_SECONDS=1

APP='chatgpt-codex-connector[bot]'
H=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
EARLIER=2026-01-01T00:05:00Z
READY=2026-01-01T00:10:00Z
reset() {
  rm -f "$STUB"/*
  echo "$H" >"$STUB/head"; echo true >"$STUB/draft"; echo "$READY" >"$STUB/ready_at"
  printf '[{"event":"ready_for_review","created_at":"%s"}]\n' "$EARLIER" >"$STUB/timeline.json"
  for f in reviews reactions comments issue_comments; do echo '[]' >"$STUB/$f.json"; done
  runs completed success >"$STUB/check_runs.json"; echo '{"statuses":[]}' >"$STUB/status.json"
}
runs() { if [ $# = 0 ]; then echo '{"check_runs":[]}'; else printf '{"check_runs":[{"name":"test","status":"%s","conclusion":"%s"}]}\n' "$1" "$2"; fi; }
reaction() { printf '{"user":{"login":"%s"},"content":"%s","created_at":"%s"}' "$1" "$2" "$3"; }
review() { printf '{"user":{"login":"%s"},"commit_id":"%s","html_url":"https://example.test/review"}' "$1" "$2"; }
# summary <short sha> [status] [time] [author]: the app's summary comment, as GitHub returns it
summary() {
  local body
  body=$(printf '<!-- codex-pull-request-review-summary -->\n\n## Codex Review Summary\n\n| Review | Status | Commit | Review trigger |\n| --- | --- | --- | --- |\n| 📝 **Code Review** | ✅ **%s** <relative-time datetime="%s">%s</relative-time> | `%s` | Draft marked ready |\n' "${2:-Completed}" "${3:-2026-01-01T00:11:00.123456Z}" "${3:-2026-01-01T00:11:00.123456Z}" "$1")
  jq -n --arg a "${4:-$APP}" --arg b "$body" '[{user: {login: $a}, body: $b}]'
}
done_on() { summary "$@" >"$STUB/summary_after_ready"; }
run() { "$mentat" review 7 >"$STUB/out" 2>&1; echo $?; }

reset; done_on 1111111; rc=$(run)
check "marks a draft ready and accepts the summary's completed Code Review on the head (exit 0)" '[ "$rc" = 0 ] && grep -qx "pr ready 7" "$STUB/calls" && grep -q "found nothing on $H" "$STUB/out"'
check "does not move a draft back to draft" '! grep -q -- "--undo" "$STUB/calls"'
reset; echo false >"$STUB/draft"; done_on 1111111; rc=$(run)
check "re-readies a ready pull request to start a new run" '[ "$rc" = 0 ] && grep -qx "pr ready 7 --undo" "$STUB/calls" && [ "$(grep -n "pr ready 7 --undo" "$STUB/calls" | cut -d: -f1)" -lt "$(grep -nx "pr ready 7" "$STUB/calls" | cut -d: -f1)" ]'
reset; summary 1111111 Completed 2026-01-01T00:06:00Z >"$STUB/issue_comments.json"; rc=$(run)
check "a completion from before this ready does not count" '[ "$rc" = 1 ] && grep -q "no result from the Codex app" "$STUB/out"'
reset; printf '[%s]\n' "$(reaction "$APP" +1 2026-01-01T00:11:00Z)" >"$STUB/reactions_after_ready"; rc=$(run)
check "a 👍 alone certifies nothing" '[ "$rc" = 1 ] && ! grep -q "found nothing" "$STUB/out"'
reset; done_on 1111111 Completed 2026-01-01T00:10:00.5Z; rc=$(run)
check "a completion in the same second as the ready event counts" '[ "$rc" = 0 ]'
reset; done_on 2222222; rc=$(run)
check "a completion on an older commit does not count" '[ "$rc" = 1 ] && ! grep -q "found nothing" "$STUB/out"'
reset; done_on 1111111 Failed; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=60 run)
check "a failed code review is not reviewed, without waiting out the timeout" '[ "$rc" = 1 ] && grep -q "code review of $H failed" "$STUB/out"'
reset; done_on 1111111 Running; rc=$(run)
check "an unrecognized status is not reviewed" '[ "$rc" = 1 ] && ! grep -q "found nothing" "$STUB/out"'
reset; jq -n --arg a "$APP" '[{user: {login: $a}, body: "<!-- codex-pull-request-review-summary -->\nsomething else"}]' >"$STUB/summary_after_ready"; rc=$(run)
check "a summary in another format is not reviewed" '[ "$rc" = 1 ]'
reset; done_on 1111111; touch "$STUB/reviews_fail"; rc=$(run)
check "a failed read of the reviews is not an empty result" '[ "$rc" = 1 ] && ! grep -q "found nothing" "$STUB/out"'
reset; summary 1111111 Completed 2026-01-01T00:11:00Z someone >"$STUB/summary_after_ready"; rc=$(run)
check "a summary from someone else does not count" '[ "$rc" = 1 ]'
reset; printf '[%s]\n' "$(reaction "$APP" eyes 2026-01-01T00:04:00Z)" >"$STUB/reactions.json"; rc=$(run)
check "refuses while the app is still reviewing" '[ "$rc" = 1 ] && grep -q "still reviewing" "$STUB/out" && ! grep -q "pr ready" "$STUB/calls"'
reset; done_on 1111111; printf '[%s]\n' "$(review "$APP" "$H")" >"$STUB/reviews.json"
printf '[{"user":{"login":"%s"},"commit_id":"%s","path":"README.md","line":12,"html_url":"https://example.test/c1"}]\n' "$APP" "$H" >"$STUB/comments.json"; rc=$(run)
check "a review of the head reports findings (exit 2)" '[ "$rc" = 2 ] && grep -q "posted findings on $H: https://example.test/review" "$STUB/out" && grep -q "README.md:12 https://example.test/c1" "$STUB/out"'
reset; done_on 1111111; printf '[%s]\n' "$(review "$APP" "$OLD")" >"$STUB/reviews.json"; rc=$(run)
check "a review of another commit is not a finding on the head" '[ "$rc" = 0 ]'
reset; printf '[%s]\n' "$(review "$APP" "$H")" >"$STUB/reviews.json"; rc=$(run)
check "findings before the code review completes do not end the round" '[ "$rc" = 1 ]'
reset; done_on 1111111; printf '[{"user":{"login":"%s"},"commit_id":"%s","html_url":"https://example.test/security","body":"### Codex Security Review"}]\n' "$APP" "$H" >"$STUB/reviews.json"; rc=$(run)
check "a security review on the head counts as findings once the code review completes" '[ "$rc" = 2 ] && grep -q "https://example.test/security" "$STUB/out"'
reset; echo "$OLD" >"$STUB/push_on_ready"; done_on 1111111; rc=$(run)
check "a push around the ready is caught, not certified (exit 3)" '[ "$rc" = 3 ] && ! grep -q "found nothing" "$STUB/out"'
reset; touch "$STUB/no_ready_event"; rc=$(MENTAT_READY_TRIES=1 run)
check "no new ready event on GitHub is not reviewed" '[ "$rc" = 1 ] && grep -q "new ready event" "$STUB/out"'
reset; touch "$STUB/ready_fails"; rc=$(run)
check "a failed ready is not reviewed" '[ "$rc" = 1 ] && grep -q "could not mark #7 ready" "$STUB/out"'
# One failed read of the head is a missed poll, not a moved head.
reset; echo 3 >"$STUB/head_fails_at"; done_on 1111111; rc=$(run)
check "a failed head read in the loop is not a moved head" '[ "$rc" = 0 ] && ! grep -q "head moved" "$STUB/out"'
reset; echo 4 >"$STUB/head_fails_at"; done_on 1111111; rc=$(run)
check "a result is accepted only after the head is read again" '[ "$rc" = 0 ] && [ "$(cat "$STUB/head_reads")" -ge 6 ]'
reset; rc=$(run)
check "no result in time is not reviewed (exit 1)" '[ "$rc" = 1 ] && grep -q "no result from the Codex app on $H" "$STUB/out"'
# CI on the head is waited for before the review starts.
reset; done_on 1111111; runs in_progress null >"$STUB/check_runs.json"; runs completed success >"$STUB/check_runs_later.json"; rc=$(run)
check "waits for running CI, then reviews" '[ "$rc" = 0 ] && [ "$(cat "$STUB/ci_reads")" -ge 2 ] && grep -qx "pr ready 7" "$STUB/calls"'
check "reads CI by the head commit" 'grep -q "repos/owner/repo/commits/$H/check-runs" "$STUB/calls" && grep -q "repos/owner/repo/commits/$H/status" "$STUB/calls"'
reset; done_on 1111111; runs completed failure >"$STUB/check_runs.json"; rc=$(run)
check "failed CI is not reviewed (exit 4) and names the check" '[ "$rc" = 4 ] && grep -q "CI did not pass on $H" "$STUB/out" && grep -qx -- "- test" "$STUB/out" && ! grep -q "pr ready" "$STUB/calls"'
reset; done_on 1111111; echo '{"statuses":[{"context":"ci/legacy","state":"failure"}]}' >"$STUB/status.json"; rc=$(run)
check "a failed commit status counts as failed CI" '[ "$rc" = 4 ] && grep -qx -- "- ci/legacy" "$STUB/out"'
reset; done_on 1111111; runs queued null >"$STUB/check_runs.json"; rc=$(run)
check "CI still running at the timeout is not reviewed (exit 4)" '[ "$rc" = 4 ] && grep -q "CI did not finish on $H" "$STUB/out" && ! grep -q "pr ready" "$STUB/calls"'
reset; done_on 1111111; runs >"$STUB/check_runs.json"; rc=$(run)
check "no CI at all reviews after the grace period" '[ "$rc" = 0 ] && [ "$(cat "$STUB/ci_reads")" -ge 2 ]'
reset; done_on 1111111; echo "$OLD" >"$STUB/push_on_ci"; rc=$(run)
check "a push during the CI wait is caught before the pull request is marked ready (exit 3)" '[ "$rc" = 3 ] && ! grep -q "pr ready" "$STUB/calls"'
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
reset; done_on 1111111; printf '{"check_runs":[{"name":"fast","status":"completed","conclusion":"success","completed_at":"%s"}]}\n' "$now" >"$STUB/check_runs.json"
printf '{"check_runs":[{"name":"fast","status":"completed","conclusion":"success","completed_at":"%s"},{"name":"slow","status":"in_progress","conclusion":null}]}\n' "$now" >"$STUB/check_runs_later.json"
# A grace period far longer than the test, so a clock tick before the first poll cannot end it.
rc=$(MENTAT_CI_GRACE_SECONDS=30 run)
check "a check that just passed waits for checks that register later" '[ "$rc" = 4 ] && grep -q "CI did not finish" "$STUB/out" && grep -qx -- "- slow" "$STUB/out" && ! grep -q "pr ready" "$STUB/calls"'
reset; done_on 1111111; runs completed skipped >"$STUB/check_runs.json"; rc=$(run)
check "a skipped check does not block the review" '[ "$rc" = 0 ]'
rc=$("$mentat" review 7 --local >/dev/null 2>&1; echo $?)
check "an argument after the number is a usage error, not the app path (exit 64)" '[ "$rc" = 64 ]'
rc=$("$mentat" review abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
