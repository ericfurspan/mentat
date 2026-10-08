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
# The hook checks replies only when the Mentat style is chosen in settings, so
# the tests run with a project and a home of their own.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/project/.claude" "$tmp/home/.claude"
export CLAUDE_PROJECT_DIR="$tmp/project" HOME="$tmp/home"
style() { printf '{"outputStyle": "%s"}\n' "$2" >"$1"; }
style "$tmp/home/.claude/settings.json" mentat:Mentat
# ask <reply> [stop_hook_active]: prints what the hook asks Claude Code to do
ask() {
  jq -n --arg m "$1" --argjson a "${2:-false}" \
    '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' |
    "$hook" | jq -r '.hookSpecificOutput.additionalContext // empty'
}
dash=$(printf '\342\200\224')
fence='```'

out=$(ask "$(words 250)")
check "a reply at the hook limit passes" '[ -z "$out" ]'
out=$(ask "$(words 251)")
check "a reply over the limit is asked for a rewrite" 'printf "%s" "$out" | grep -q "251 words"'
out=$(ask "$(printf 'Done.\n\n%s\n%s\n%s\n' "$fence" "$(words 300)" "$fence")")
check "words inside a fenced code block are not counted" '[ -z "$out" ]'
out=$(ask "Merged $dash see the log.")
check "an em dash is asked for a rewrite" 'printf "%s" "$out" | grep -q "em dash"'
out=$(ask "$(printf 'The log says:\n\n> not found\n')")
check "a blockquote is asked for a rewrite" 'printf "%s" "$out" | grep -q "blockquote"'
out=$(ask "$(words 300)" true)
check "a rewrite is asked for only once per turn" '[ -z "$out" ]'
out=$(printf 'not json' | "$hook"); rc=$?
check "unreadable input lets the turn end" '[ "$rc" = 0 ] && [ -z "$out" ]'

# Style selection: the hook stays quiet unless the Mentat style is chosen, and
# local settings win over project, which win over user.
long=$(words 300)
style "$tmp/project/.claude/settings.json" Explanatory; out=$(ask "$long")
check "another style chosen for the project is left alone" '[ -z "$out" ]'
style "$tmp/project/.claude/settings.local.json" Mentat; out=$(ask "$long")
check "local settings win over project settings" 'printf "%s" "$out" | grep -q "300 words"'
rm "$tmp/project/.claude/settings.local.json" "$tmp/project/.claude/settings.json" "$tmp/home/.claude/settings.json"; out=$(ask "$long")
check "no style chosen anywhere is left alone" '[ -z "$out" ]'

check "hooks.json runs it on Stop" 'jq -e ".hooks.Stop[0].hooks[0].command | endswith(\"/hooks/reply-check\")" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
