#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-merge, the PreToolUse hook. Prints PASS/FAIL per
# case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-merge"
failures=0
check() { if eval "$2"; then printf 'PASS: no-merge %s\n' "$1"; else printf 'FAIL: no-merge %s\n' "$1"; failures=$((failures + 1)); fi; }

# The hook decides from its input alone: a gh that records every call and fails
# proves it never reads GitHub.
root_tmp=$(mktemp -d)
trap 'rm -rf "$root_tmp"' EXIT
export STUB="$root_tmp/stub"
mkdir -p "$STUB" "$root_tmp/bin"
cat >"$root_tmp/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
exit 99
STUBEOF
chmod +x "$root_tmp/bin/gh"
export PATH="$root_tmp/bin:$PATH"

# decision <tool> <command>: prints the hook's permission decision, or nothing
decision() {
  jq -n --arg t "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}}' |
    "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

while IFS= read -r cmd; do
  check "asks before: $cmd" '[ "$(decision Bash "$cmd")" = ask ]'
done <<'ASK'
gh pr merge 12 --squash
gh -R o/r pr merge 7
gh pr merge 7 --auto --squash
pr=7; gh api -X PUT "repos/o/r/pulls/$pr/merge"
gh api -X PUT repos/o/r/pulls/7/merge -f sha=abc1234 -f merge_method=squash
gh api -X PUT repos/{owner}/{repo}/pulls/7/merge -f sha=abc1234
gh api -X PUT repos/o/r/pulls/7/merge; gh api -X PUT repos/o/r/pulls/8/merge
ASK
while IFS= read -r cmd; do
  check "leaves alone: $cmd" '[ -z "$(decision Bash "$cmd")" ]'
done <<'PASS'
gh pr view 12
gh pr create --title "fix merge logic"
gh pr ready 7
PASS
check "asks before the desktop auto-merge tool" '[ "$(decision mcp__ccd_pr__set_auto_merge "")" = ask ]'
check "reads nothing from GitHub" '[ ! -f "$STUB/calls" ]'
check "hooks.json runs it on PreToolUse for Bash and the auto-merge tool" \
  'jq -e ".hooks.PreToolUse[0] | (.matcher == \"Bash|mcp__ccd_pr__set_auto_merge\") and (.hooks[0].command | endswith(\"/hooks/no-merge\"))" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
