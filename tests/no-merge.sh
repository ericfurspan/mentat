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

# A stub gh serves each repository's AGENTS.md from $STUB/<owner>_<repo>.md; a
# missing file is a failed read.
root_tmp=$(mktemp -d)
trap 'rm -rf "$root_tmp"' EXIT
export STUB="$root_tmp/stub"
mkdir -p "$STUB" "$root_tmp/bin"
cat >"$root_tmp/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
for a in "$@"; do
  case "$a" in repos/*/contents/AGENTS.md) r=${a#repos/}; r=${r%/contents/AGENTS.md}; f="$STUB/${r/\//_}.md"; [ -f "$f" ] && cat "$f" && exit 0; exit 1 ;; esac
done
exit 99
STUBEOF
chmod +x "$root_tmp/bin/gh"
export PATH="$root_tmp/bin:$PATH"
optin() { printf '# Rules\n\n- Agents may merge their own pull requests.\n' >"$STUB/$1.md"; }

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
pr=7; gh api -X PUT "repos/o/r/pulls/$pr/merge"
ASK
while IFS= read -r cmd; do
  check "leaves alone: $cmd" '[ -z "$(decision Bash "$cmd")" ]'
done <<'PASS'
gh pr view 12
gh pr create --title "fix merge logic"
PASS
# The opt-in: the merge API call to a repository whose AGENTS.md has the line.
optin o_r
check "opted in: the merge API call gets no prompt" '[ -z "$(decision Bash "gh api -X PUT repos/o/r/pulls/7/merge -f sha=abc1234 -f merge_method=squash")" ]'
check "opted in: reads the target repository's AGENTS.md from GitHub" 'grep -q "repos/o/r/contents/AGENTS.md" "$STUB/calls"'
check "opted in: a merge API call without sha= still asks" '[ "$(decision Bash "gh api -X PUT repos/o/r/pulls/7/merge -f merge_method=squash")" = ask ]'
check "opted in: gh pr merge still asks" '[ "$(decision Bash "gh pr merge 7 --squash")" = ask ]'
check "opted in: gh pr merge --auto still asks" '[ "$(decision Bash "gh pr merge 7 --auto --squash")" = ask ]'
check "opted in: the desktop auto-merge tool still asks" '[ "$(decision mcp__ccd_pr__set_auto_merge "")" = ask ]'
check "another repository without the line asks" '[ "$(decision Bash "gh api -X PUT repos/other/repo/pulls/7/merge -f sha=abc1234")" = ask ]'
check "a placeholder repository asks" '[ "$(decision Bash "gh api -X PUT repos/{owner}/{repo}/pulls/7/merge -f sha=abc1234")" = ask ]'
check "two merge calls in one command ask" '[ "$(decision Bash "gh api -X PUT repos/o/r/pulls/7/merge; gh api -X PUT repos/o/r/pulls/8/merge")" = ask ]'
printf '# Rules\n\nThe maintainer merges.\n' >"$STUB/o_r.md"
check "a removed opt-in asks" '[ "$(decision Bash "gh api -X PUT repos/o/r/pulls/7/merge -f sha=abc1234")" = ask ]'
rm -f "$STUB/o_r.md"
check "a failed read asks" '[ "$(decision Bash "gh api -X PUT repos/o/r/pulls/7/merge -f sha=abc1234")" = ask ]'
check "asks before the desktop auto-merge tool" '[ "$(decision mcp__ccd_pr__set_auto_merge "")" = ask ]'
check "hooks.json runs it on PreToolUse for Bash and the auto-merge tool" \
  'jq -e ".hooks.PreToolUse[0] | (.matcher == \"Bash|mcp__ccd_pr__set_auto_merge\") and (.hooks[0].command | endswith(\"/hooks/no-merge\"))" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
