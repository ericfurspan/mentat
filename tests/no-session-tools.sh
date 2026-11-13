#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-session-tools, the PreToolUse hook. Prints PASS/FAIL
# per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-session-tools"
failures=0
check() { if eval "$2"; then printf 'PASS: no-session-tools %s\n' "$1"; else printf 'FAIL: no-session-tools %s\n' "$1"; failures=$((failures + 1)); fi; }

# output <tool> <tool_input JSON>: prints what the hook prints.
output() { jq -n --arg t "$1" --argjson i "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i}' | "$hook"; }
decision() { output "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }

check "denies archiving a session" '[ "$(decision mcp__ccd_session_mgmt__archive_session "{\"session_id\": \"s1\"}")" = deny ]'
check "denies moving a session to the cloud" '[ "$(decision mcp__ccd_session__move_to_cloud "{}")" = deny ]'
while IFS= read -r target; do
  input=$(jq -n --arg t "$target" '{target: $t, prompt: "p"}')
  check "denies starting a session with target $target" '[ "$(decision mcp__ccd_session__start_session "$input")" = deny ]'
done <<'CLOUD'
cloud
Cloud
CLOUD
while IFS= read -r input; do
  check "passes a start with {}: $input" '[ "$(output mcp__ccd_session__start_session "$input")" = "{}" ]'
done <<'LOCAL'
{"target": "local", "prompt": "p"}
{"prompt": "p"}
{"target": "worktree"}
LOCAL
check "passes another tool with {}" '[ "$(output Bash "{\"command\": \"ls\"}")" = "{}" ]'
check "the archive reason names the maintainer's step" \
  '[ "$(output mcp__ccd_session_mgmt__archive_session "{}" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "Mentat: agents never archive a session; archiving is the maintainer'"'"'s step." ]'
check "hooks.json runs it on PreToolUse for the three session tools" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"mcp__ccd_session_mgmt__archive_session|mcp__ccd_session__move_to_cloud|mcp__ccd_session__start_session\") | .hooks[].command | select(endswith(\"/hooks/no-session-tools\"))] | length == 1" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
