#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat ci`, which waits for CI on a pull request's head and
# reviews nothing, and for the review command's usage errors, using a stub gh.
# The wait for CI is the same one every review runs first. Prints PASS/FAIL per
# case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: review %s\n' "$1"; else printf 'FAIL: review %s\n' "$1"; failures=$((failures + 1)); fi; }

# State lives in $STUB: head, and check_runs.json (check_runs_later.json from the
# second read on). A file named push_on_ci holds a head to switch to when CI is read.
# Any other call is recorded and fails.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "repo view") echo owner/repo ;;
  "pr view")
    case "$*" in
      *headRefOid*) cat "$STUB/head" ;;
      *) exit 99 ;;
    esac ;;
  "api --paginate")
    case "$3" in
      */check-runs)
        n=$(($(cat "$STUB/ci_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/ci_reads"
        [ -f "$STUB/push_on_ci" ] && cp "$STUB/push_on_ci" "$STUB/head"
        if [ "$n" -ge 2 ] && [ -f "$STUB/check_runs_later.json" ]; then cat "$STUB/check_runs_later.json"; else cat "$STUB/check_runs.json"; fi ;;
      *) exit 99 ;;
    esac ;;
  *) exit 99 ;;
esac
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_CI_TIMEOUT_SECONDS=2 MENTAT_CI_GRACE_SECONDS=1

H=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
reset() {
  rm -f "$STUB"/*
  echo "$H" >"$STUB/head"
  runs completed success >"$STUB/check_runs.json"
}
runs() { if [ $# = 0 ]; then echo '{"check_runs":[]}'; else printf '{"check_runs":[{"name":"test","status":"%s","conclusion":"%s"}]}\n' "$1" "$2"; fi; }
runci() { "$mentat" ci 7 >"$STUB/out" 2>&1; echo $?; }

reset; runs in_progress null >"$STUB/check_runs.json"; runs completed success >"$STUB/check_runs_later.json"; rc=$(runci)
check "ci waits for running CI, then passes (exit 0)" '[ "$rc" = 0 ] && [ "$(cat "$STUB/ci_reads")" -ge 2 ] && grep -q "CI passed on $H" "$STUB/out"'
check "ci reads CI by the head commit" 'grep -q "repos/owner/repo/commits/$H/check-runs" "$STUB/calls"'
check "ci posts nothing" '! grep -q -- "-X POST\|pr comment" "$STUB/calls"'
reset; runs completed failure >"$STUB/check_runs.json"; rc=$(runci)
check "ci reports failed CI (exit 4) and names the check" '[ "$rc" = 4 ] && grep -q "CI did not pass on $H" "$STUB/out" && grep -qx -- "- test" "$STUB/out"'
reset; runs queued null >"$STUB/check_runs.json"; rc=$(runci)
check "ci reports CI still running at the timeout (exit 4)" '[ "$rc" = 4 ] && grep -q "CI did not finish on $H" "$STUB/out"'
reset; runs >"$STUB/check_runs.json"; rc=$(runci)
check "ci with no CI at all passes after the grace period (exit 0)" '[ "$rc" = 0 ] && [ "$(cat "$STUB/ci_reads")" -ge 2 ] && grep -q "CI passed on $H" "$STUB/out"'
reset; echo "$OLD" >"$STUB/push_on_ci"; rc=$(runci)
check "ci catches a push during the wait (exit 3)" '[ "$rc" = 3 ] && ! grep -q "CI passed" "$STUB/out"'
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
reset; printf '{"check_runs":[{"name":"fast","status":"completed","conclusion":"success","completed_at":"%s"}]}\n' "$now" >"$STUB/check_runs.json"
printf '{"check_runs":[{"name":"fast","status":"completed","conclusion":"success","completed_at":"%s"},{"name":"slow","status":"in_progress","conclusion":null}]}\n' "$now" >"$STUB/check_runs_later.json"
# A grace period far longer than the test, so a clock tick before the first poll cannot end it.
rc=$(MENTAT_CI_GRACE_SECONDS=30 runci)
check "ci waits for checks that register after one passed (exit 4)" '[ "$rc" = 4 ] && grep -q "CI did not finish" "$STUB/out" && grep -qx -- "- slow" "$STUB/out"'
reset; runs completed skipped >"$STUB/check_runs.json"; rc=$(runci)
check "ci does not let a skipped check block (exit 0)" '[ "$rc" = 0 ] && grep -q "CI passed on $H" "$STUB/out"'
rc=$("$mentat" ci abc >/dev/null 2>&1; echo $?)
check "ci with a bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$("$mentat" review 7 --local >"$STUB/out" 2>&1; echo $?)
check "an argument after the number is a usage error, not ignored (exit 64)" '[ "$rc" = 64 ] && grep -qF "usage: mentat review [--local | --grok] [--request <file>] <pull request number>" "$STUB/out"'
rc=$("$mentat" review abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
