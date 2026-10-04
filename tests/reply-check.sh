#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/reply-check, the Stop hook. Prints PASS/FAIL per
# case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/reply-check"
failures=0
check() { if eval "$2"; then printf 'PASS: reply-check %s\n' "$1"; else printf 'FAIL: reply-check %s\n' "$1"; failures=$((failures + 1)); fi; }

words() { # $1 count: prints that many words
  local i=0 out=""
  while [ "$i" -lt "$1" ]; do out="$out word"; i=$((i + 1)); done
  printf '%s' "${out# }"
}
# ask <reply> [stop_hook_active]: prints what the hook asks Claude Code to do
ask() {
  jq -n --arg m "$1" --argjson a "${2:-false}" \
    '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' |
    "$hook" | jq -r '.hookSpecificOutput.additionalContext // empty'
}
dash=$(printf '\342\200\224')
fence='```'

out=$(ask "$(words 100)")
check "a reply at the limit passes" '[ -z "$out" ]'
out=$(ask "$(words 101)")
check "a reply over the limit is asked for a rewrite" 'printf "%s" "$out" | grep -q "101 words"'
out=$(ask "$(printf 'Done.\n\n%s\n%s\n%s\n' "$fence" "$(words 300)" "$fence")")
check "words inside a fenced code block are not counted" '[ -z "$out" ]'
out=$(ask "$(printf -- '- %s\n- %s\n\n| a | b |\n|---|---|\n' "$(words 49)" "$(words 49)")")
check "list markers and table borders are not counted" '[ -z "$out" ]'
out=$(ask "Merged $dash see the log.")
check "an em dash is asked for a rewrite" 'printf "%s" "$out" | grep -q "em dash"'
out=$(ask "$(printf 'Done.\n\n%s\nquoted %s text\n> redirected\n%s\n' "$fence" "$dash" "$fence")")
check "an em dash or > inside a fenced code block passes" '[ -z "$out" ]'
out=$(ask "$(printf 'The log says:\n\n> not found\n')")
check "a blockquote is asked for a rewrite" 'printf "%s" "$out" | grep -q "blockquote"'
out=$(ask "$(words 101)$dash")
check "every problem is named in one request" 'printf "%s" "$out" | grep -q "101 words" && printf "%s" "$out" | grep -q "em dash"'
out=$(ask "$(words 300)" true)
check "a rewrite is asked for only once per turn" '[ -z "$out" ]'
out=$(printf 'not json' | "$hook"); rc=$?
check "unreadable input lets the turn end" '[ "$rc" = 0 ] && [ -z "$out" ]'
out=$(jq -n '{hook_event_name: "Stop", stop_hook_active: false}' | "$hook"); rc=$?
check "an input with no reply lets the turn end" '[ "$rc" = 0 ] && [ -z "$out" ]'

check "hooks.json runs it on Stop" 'jq -e ".hooks.Stop[0].hooks[0].command | endswith(\"/hooks/reply-check\")" "$root/hooks/hooks.json" >/dev/null'
limit=$(sed -n 's/^limit=//p' "$hook")
check "the output style states the same limit" '[ -n "$limit" ] && grep -q "$limit words" "$root/output-styles/mentat.md"'

[ "$failures" -eq 0 ]
