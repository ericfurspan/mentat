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

# output <tool> <command>: prints what the hook prints.
output() {
  jq -n --arg t "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}}' | "$hook"
}
# decision <tool> <command>: prints the hook's permission decision, or nothing
decision() { output "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }

while IFS= read -r cmd; do
  check "denies: $cmd" '[ "$(decision Bash "$cmd")" = deny ]'
done <<'DENY'
gh pr merge 12 --squash
gh -R o/r pr merge 7
gh pr merge 7 --auto --squash
pr=7; gh api -X PUT "repos/o/r/pulls/$pr/merge"
gh api -X PUT repos/o/r/pulls/7/merge -f sha=abc1234 -f merge_method=squash
gh api -X PUT repos/{owner}/{repo}/pulls/7/merge -f sha=abc1234
gh api -X PUT repos/o/r/pulls/7/merge; gh api -X PUT repos/o/r/pulls/8/merge
gh -R "o/r" pr merge 5 --merge
gh -R 'o/r' pr merge 5
gh --repo="o/r" pr merge 5
gh --repo=o/r pr merge 5
gh --repo "o r" pr merge 5
gh --repo='o r' pr merge 5
gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:"X"}){clientMutationId}}'
gh api graphql -f query='mutation{enablePullRequestAutoMerge(input:{pullRequestId:"X"}){clientMutationId}}'
gh api graphql -f query='mutation{mergeBranch(input:{repositoryId:"X",base:"main",head:"feat"}){clientMutationId}}'
gh api graphql -f query='mutation{enqueuePullRequest(input:{pullRequestId:"X"}){clientMutationId}}'
gh api -X POST repos/o/r/merges -f base=main -f head=feat
gh api --method POST /repos/o/r/merges
gh api repos/{owner}/{repo}/merges
gh api "repos/$REPO/merges"
gh api "repos/$O/$R/merges" -f base=main
gh api https://api.github.com/repos/o/r/merges
gh pr view 5; gh api repos/o/r/merges -f base=main -f head=feat
DENY
# Split across lines: a backslash-newline continuation, or a query over several lines.
cmd=$(printf 'gh -R o/r \\\npr merge 5')
check "denies gh pr merge split by a backslash-newline" '[ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf 'gh \\\n  --repo "o/r" \\\n  pr \\\n  merge 5')
check "denies gh pr merge split over several continuation lines" '[ "$(decision Bash "$cmd")" = deny ]'
# Bash removes a backslash-newline outright, so one inside a word still runs the merge.
cmd=$(printf 'gh -R "o/r" pr mer\\\nge 5')
check "denies gh pr merge with a continuation inside merge" '[ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf 'gh -R o/r p\\\nr merge 5')
check "denies gh pr merge with a continuation inside pr" '[ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf "gh api graphql -f query='\nmutation {\n  mergePullRequest(input: {pullRequestId: \"X\"}) {\n    clientMutationId\n  }\n}'")
check "denies a GraphQL merge written over several lines" '[ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf 'gh \\\napi -X POST repos/o/r/merges -f base=main -f head=feat')
check "denies a /merges call split by a backslash-newline" '[ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf 'gh api -X PUT \\\n  repos/o/r/pulls/7/merge')
check "denies the merge API split by a backslash-newline" '[ "$(decision Bash "$cmd")" = deny ]'
# A merge followed by more than a pipe buffer of text (over 100 KB) is still denied.
long=$(i=0; while [ "$i" -lt 8000 ]; do printf 'echo line %d\n' "$i"; i=$((i + 1)); done)
cmd=$(printf "gh pr merge 7 --squash --body-file - <<'EOF'\n%s\nEOF" "$long")
check "denies gh pr merge with a body over 100 KB" '[ "${#cmd}" -gt 100000 ] && [ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf 'gh api -X PUT repos/o/r/pulls/7/merge\n%s' "$long")
check "denies the merge API followed by a script over 100 KB" '[ "${#cmd}" -gt 100000 ] && [ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"X\"}){clientMutationId}}'\n%s" "$long")
check "denies a GraphQL merge followed by a script over 100 KB" '[ "${#cmd}" -gt 100000 ] && [ "$(decision Bash "$cmd")" = deny ]'
cmd=$(printf '%s\ngh api -X POST repos/o/r/merges -f base=main -f head=feat' "$long")
check "denies a /merges call after a script over 100 KB" '[ "${#cmd}" -gt 100000 ] && [ "$(decision Bash "$cmd")" = deny ]'
cont=$(i=0; while [ "$i" -lt 8000 ]; do printf -- '-f k%d=v \\\n' "$i"; i=$((i + 1)); done)
cmd=$(printf 'gh -R o/r \\\n%s\npr merge 5' "$cont")
check "denies gh pr merge after over 100 KB of continuation lines" '[ "${#cmd}" -gt 100000 ] && [ "$(decision Bash "$cmd")" = deny ]'
while IFS= read -r cmd; do
  check "passes with {}: $cmd" '[ "$(output Bash "$cmd")" = "{}" ]'
done <<'PASS'
gh pr view 12
gh pr create --title "fix merge logic"
gh pr ready 7
gh -R "o/r" pr view 5
gh --repo="o r" pr view 5
gh pr view 5 --json mergeStateStatus,mergeable
gh api graphql -f query='query{repository(owner:"o",name:"r"){pullRequest(number:5){mergeable autoMergeRequest{enabledAt}}}}'
gh api graphql -f query='mutation{disablePullRequestAutoMerge(input:{pullRequestId:"X"}){clientMutationId}}'
git commit -m "deny mergePullRequest"
gh pr create --title "repos/o/r/merges"
gh api repos/o/r/pulls/5/commits
gh api repos/o/r/contents/x/merges
PASS
# Only a backslash-newline joins lines: a merge word on the next line is another command.
cmd=$(printf 'gh pr\nmerge 5')
check "passes gh pr and merge on separate lines" '[ "$(output Bash "$cmd")" = "{}" ]'
cmd=$(printf "echo mergePullRequest\ngh api repos/o/r/pulls/5")
check "passes a mutation name before gh api" '[ "$(output Bash "$cmd")" = "{}" ]'
check "denies the desktop auto-merge tool" '[ "$(decision mcp__ccd_pr__set_auto_merge "")" = deny ]'
# The matcher in hooks.json and the hook agree on which tools merge: hooks.json runs
# the hook for each listed tool that should be checked, and the hook decides.
matches() { jq -e --arg t "$1" '[.hooks.PreToolUse[] | select(.hooks | map(.command | endswith("/hooks/no-merge")) | any) | .matcher as $m | $t | test($m)] | any' "$root/hooks/hooks.json" >/dev/null; }
while read -r t runs decides; do
  check "hooks.json runs it for $t: $runs; the hook decides: $decides" \
    'if matches "$t"; then m=yes; else m=no; fi; d=$(decision "$t" ""); [ "$m" = "$runs" ] && [ "${d:-pass}" = "$decides" ]'
done <<'TOOLS'
Bash yes pass
mcp__ccd_pr__set_auto_merge yes deny
mcp__github__merge_pull_request yes deny
mcp__plugin_github_github__merge_pull_request yes deny
mcp__github__enable_auto_merge yes deny
BashOutput no pass
mcp__github__pull_request_read no pass
mcp__linear__merge_diff no pass
TOOLS
check "the reason says the maintainer merges and how to pass text that only mentions a merge" \
  '[ "$(output Bash "gh pr merge 7" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "Mentat: the maintainer merges; agents never merge a pull request or turn on auto-merge. If this command only mentions a merge in its text, such as a commit message or pull request body, pass that text through a file (-F or --body-file)." ]'
check "reads nothing from GitHub" '[ ! -f "$STUB/calls" ]'

[ "$failures" -eq 0 ]
