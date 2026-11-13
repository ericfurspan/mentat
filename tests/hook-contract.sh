#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for the contract every enforcing PreToolUse hook keeps through
# hooks/lib/verdict.sh: it fails closed on input it cannot read and on a check that
# gives no verdict, prints exactly one JSON object and exits 0, and is wired with
# onFailure block and a timeout. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
check() { if eval "$2"; then printf 'PASS: hook-contract %s\n' "$1"; else printf 'FAIL: hook-contract %s\n' "$1"; failures=$((failures + 1)); fi; }

hooks="no-merge no-repo-admin no-session-tools no-guard-edits no-private-text"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME" "$tmp/bin" "$tmp/nojq" "$tmp/fixtures" "$tmp/bare/hooks"
# A gh that records nothing and fails, so no case reads GitHub.
printf '#!/usr/bin/env bash\nexit 99\n' >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
ln -s "$tmp/bin/gh" "$tmp/nojq/gh"
export PATH="$tmp/bin:$PATH"

# one_object <output>: the output is exactly one JSON object.
one_object() { jq -se 'length == 1 and (.[0] | type) == "object"' <<<"$1" >/dev/null 2>&1; }
# denied <output> <reason>: one object holding a deny with exactly that reason.
denied() {
  one_object "$1" &&
    [ "$(jq -r '.hookSpecificOutput | .hookEventName + "|" + .permissionDecision + "|" + .permissionDecisionReason' <<<"$1")" = "PreToolUse|deny|$2" ]
}

for h in $hooks; do
  hook=$root/hooks/$h
  unread="Mentat: $h could not read its input (one JSON object with a tool_name), so it blocks this call."
  out=$(printf '' | "$hook"); rc=$?
  check "$h denies empty input and exits 0" '[ "$rc" = 0 ] && denied "$out" "$unread"'
  out=$(printf 'not json {' | "$hook"); rc=$?
  check "$h denies input that is not JSON and exits 0" '[ "$rc" = 0 ] && denied "$out" "$unread"'
  out=$(printf '{"tool_input": {"command": "ls"}}' | "$hook")
  check "$h denies input with no tool_name" 'denied "$out" "$unread"'
  out=$(printf '{"tool_name": ""}' | "$hook")
  check "$h denies an empty tool_name" 'denied "$out" "$unread"'
  out=$(printf '{"tool_name": 7}' | "$hook")
  check "$h denies a tool_name that is no string" 'denied "$out" "$unread"'
  out=$(printf '{"tool_name": "Bash"}{"tool_name": "Bash"}' | "$hook")
  check "$h denies more than one JSON value" 'denied "$out" "$unread"'
  out=$(printf '[{"tool_name": "Bash"}]' | "$hook")
  check "$h denies a JSON array" 'denied "$out" "$unread"'
  out=$(printf '{"tool_name": "Bash", "tool_input": {"command": "ls"}}' | PATH="$tmp/nojq:/bin" "$hook" 2>/dev/null); rc=$?
  check "$h denies without jq on PATH, naming the hook, and exits 0" \
    '[ "$rc" = 0 ] && denied "$out" "Mentat: $h needs jq, which is missing, so it blocks this call."'
  out=$(printf '{"tool_name": "Bash", "tool_input": {"command": "ls"}}' | "$hook")
  check "$h passes a harmless command with exactly {}" '[ "$out" = "{}" ]'
  # A copy without hooks/lib cannot load the shared helper, and denies.
  cp "$hook" "$tmp/bare/hooks/$h"
  out=$(printf '{"tool_name": "Bash", "tool_input": {"command": "ls"}}' | "$tmp/bare/hooks/$h" 2>/dev/null); rc=$?
  check "$h denies when it cannot load its helper" \
    '[ "$rc" = 0 ] && one_object "$out" && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out")" = deny ]'
done

# fixture <name> <check body>: a hook on the shared helper whose check runs the body.
fixture() {
  {
    printf '#!/usr/bin/env bash\nset -uo pipefail\n. "%s/hooks/lib/verdict.sh"\n' "$root"
    printf 'check() {\n%s\n}\nrun_hook check\n' "$2"
  } >"$tmp/fixtures/$1"
  chmod +x "$tmp/fixtures/$1"
}
run_fixture() { printf '{"tool_name": "Bash", "tool_input": {"command": "ls"}}' | "$tmp/fixtures/$1"; }

fixture silent ':'
fixture exits 'exit 0'
fixture crashes 'exit 3'
fixture plain 'echo looks fine'
fixture unknown 'verdict maybe'
fixture allow 'verdict allow'
fixture defer 'verdict defer'
fixture bare-ask 'verdict ask'
fixture two-lines 'printf "pass\\npass\\n"; exit 0'
fixture stray 'echo progress; verdict pass'
fixture passes 'verdict pass'
fixture denies 'verdict deny "not this one."'
fixture bare-deny 'verdict deny'
fixture asks 'verdict ask "Mentat: check this."'
fixture newline-reason 'verdict deny "a
b"'

none_reason() { printf 'Mentat: %s gave no verdict, so it blocks this call.' "$1"; }
out=$(run_fixture silent); rc=$?
check "a check that prints nothing denies, naming the hook, and exits 0" '[ "$rc" = 0 ] && denied "$out" "$(none_reason silent)"'
check "a check that exits 0 with nothing denies" 'denied "$(run_fixture exits)" "$(none_reason exits)"'
check "a check that crashes denies, naming the hook" 'denied "$(run_fixture crashes)" "Mentat: crashes failed (exit 3), so it blocks this call."'
check "a check that prints plain text denies" 'denied "$(run_fixture plain)" "$(none_reason plain)"'
check "an unknown verdict word denies" 'denied "$(run_fixture unknown)" "$(none_reason unknown)"'
check "allow is no verdict and denies" 'denied "$(run_fixture allow)" "$(none_reason allow)"'
check "defer is no verdict and denies" 'denied "$(run_fixture defer)" "$(none_reason defer)"'
check "ask with no reason denies" 'denied "$(run_fixture bare-ask)" "$(none_reason bare-ask)"'
check "two results deny" 'denied "$(run_fixture two-lines)" "Mentat: two-lines gave more than one result, so it blocks this call."'
check "stray output before the verdict denies" 'denied "$(run_fixture stray)" "Mentat: stray gave more than one result, so it blocks this call."'
check "a reason over two lines denies with the helper's reason" 'denied "$(run_fixture newline-reason)" "Mentat: newline-reason gave more than one result, so it blocks this call."'
check "pass prints exactly {}" '[ "$(run_fixture passes)" = "{}" ]'
check "deny prints its reason after Mentat:" 'denied "$(run_fixture denies)" "Mentat: not this one."'
check "deny with no reason names the hook" 'denied "$(run_fixture bare-deny)" "Mentat: bare-deny blocks this call."'
out=$(run_fixture asks)
check "ask prints one object with its reason, Mentat: once" \
  'one_object "$out" && [ "$(jq -r ".hookSpecificOutput | .permissionDecision + \"|\" + .permissionDecisionReason" <<<"$out")" = "ask|Mentat: check this." ]'

# Wiring: each enforcing hook runs once, synchronously, blocking on failure, with a
# 30-second timeout.
for h in $hooks; do
  check "hooks.json runs $h once with onFailure block, timeout 30 and no async" \
    'jq -e --arg h "/hooks/$h" "[.hooks.PreToolUse[].hooks[] | select(.command | endswith(\$h))] | length == 1 and (.[0] | .onFailure == \"block\" and .timeout == 30 and (has(\"async\") | not))" "$root/hooks/hooks.json" >/dev/null'
done

[ "$failures" -eq 0 ]
