#!/usr/bin/env bash
# shellcheck disable=SC2016
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-merge, the PreToolUse hook. Prints PASS/FAIL per
# case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-merge"
failures=0
check() { if eval "$2"; then printf 'PASS: no-merge %s\n' "$1"; else printf 'FAIL: no-merge %s\n' "$1"; failures=$((failures + 1)); fi; }

# decision <tool> <command>: prints the hook's permission decision, or nothing
decision() {
  jq -n --arg t "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}}' |
    "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

while IFS= read -r cmd; do
  check "asks before: $cmd" '[ "$(decision Bash "$cmd")" = ask ]'
done <<'ASK'
gh pr merge 12 --squash
gh pr merge --auto --squash 12
cd repo && gh pr merge 12
gh  pr   merge
GH_TOKEN= gh pr merge 3
gh api -X PUT repos/o/r/pulls/7/merge
gh api repos/o/r/pulls/7/merge -X PUT -f merge_method=squash
ASK

while IFS= read -r cmd; do
  check "leaves alone: $cmd" '[ -z "$(decision Bash "$cmd")" ]'
done <<'PASS'
gh pr view 12
gh pr create --draft
git merge-base main HEAD
git merge origin/main
gh api repos/o/r/pulls/7
gh api repos/o/r/pulls/7/reviews
mygh pr merge 12
PASS

check "asks before the desktop auto-merge tool" '[ "$(decision mcp__ccd_pr__set_auto_merge "")" = ask ]'
check "leaves other tools alone" '[ -z "$(decision Edit "gh pr merge")" ]'
out=$(printf 'not json' | "$hook"); rc=$?
check "unreadable input stays out of the way" '[ "$rc" = 0 ] && [ -z "$out" ]'
check "hooks.json runs it on PreToolUse for Bash and the auto-merge tool" \
  'jq -e ".hooks.PreToolUse[0] | (.matcher == \"Bash|mcp__ccd_pr__set_auto_merge\") and (.hooks[0].command | endswith(\"/hooks/no-merge\"))" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
