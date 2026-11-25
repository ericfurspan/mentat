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
mcp__github__set_v2_auto_merge yes deny
mcp__srv__Enable_auto_merge yes deny
BashOutput no pass
mcp__github__pull_request_read no pass
mcp__linear__merge_diff no pass
TOOLS
check "the reason says the maintainer merges and how to pass text that only mentions a merge" \
  '[ "$(output Bash "gh pr merge 7" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "Mentat: the maintainer merges; agents never merge a pull request or turn on auto-merge. If this command only mentions a merge in its text, such as a commit message or pull request body, pass that text through a file (-F or --body-file)." ]'
check "reads nothing from GitHub" '[ ! -f "$STUB/calls" ]'

# The repository's own merge policy (lib/agent-merge.sh): with MENTAT_AGENT_MERGE on in the
# settings committed on origin's default branch, the hook passes exactly one merge command.
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
real_git=$(command -v git)
# mkrepo <settings text or ->: a clone of a bare origin with one commit on main and origin/HEAD set.
n=0
mkrepo() {
  n=$((n + 1))
  repo="$root_tmp/work$n"
  git init -q --bare "$root_tmp/origin$n.git"
  git -C "$root_tmp/origin$n.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$root_tmp/origin$n.git" "$repo" 2>/dev/null
  git -C "$repo" checkout -q -b main
  mkdir -p "$repo/docs" "$repo/hooks"
  printf 'a\n' >"$repo/docs/a.md"
  printf 'a\n' >"$repo/hooks/a"
  if [ "$1" != - ]; then mkdir -p "$repo/.claude"; printf '%s\n' "$1" >"$repo/.claude/settings.json"; fi
  git -C "$repo" add -A
  git -C "$repo" commit -q -m first
  git -C "$repo" push -q origin main 2>/dev/null
  git -C "$repo" remote set-head origin main
}
# branch <repo> <name> <path>: a commit adding <path> on a branch cut from origin/main; prints it.
branch() {
  git -C "$1" checkout -q -B "$2" origin/main
  mkdir -p "$1/$(dirname "$3")"
  printf 'x\n' >"$1/$3"
  git -C "$1" add -- "$3"
  git -C "$1" commit -q -m change
  git -C "$1" rev-parse HEAD
}
on='{"env": {"MENTAT_AGENT_MERGE": "on", "MENTAT_MERGE_WAIT_PATHS": "hooks/ CHANGELOG.md"}}'
mkrepo "$on"
onrepo=$repo
ok=$(branch "$onrepo" okbranch docs/new.md)
prot=$(branch "$onrepo" protbranch hooks/new)
ghp=$(branch "$onrepo" ghbranch .github/workflows/x.yml)
unknown=0000000000000000000000000000000000000000
# hin <cwd> <command>: what the hook prints for a Bash command run in <cwd> (none: no cwd).
hin() {
  if [ "$1" = none ]; then
    jq -n --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}' | "$hook"
  else
    jq -n --arg d "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$hook"
  fi
}
in_decision() { hin "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
in_reason() { hin "$@" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
today="Mentat: the maintainer merges; agents never merge a pull request or turn on auto-merge. If this command only mentions a merge in its text, such as a commit message or pull request body, pass that text through a file (-F or --body-file)."
form="gh pr merge <number> --merge --match-head-commit <40-hex commit>"

# 6a: with the setting off or unreadable, every merge form is denied with today's reason.
mkrepo '{"env": {"MENTAT_AGENT_MERGE": "off"}}'; r_off=$repo
mkrepo '{"env": {"MENTAT_AGENT_MERGE": "yes"}}'; r_yes=$repo
mkrepo '{"env": {"MENTAT_AGENT_MERGE": ""}}'; r_empty=$repo
mkrepo '{"env": {}}'; r_none=$repo
mkrepo 'not json'; r_bad=$repo
mkrepo -; r_nofile=$repo
mkrepo "$on"; git -C "$repo" remote set-head origin -d >/dev/null; r_nohead=$repo
mkrepo '{"env": {"MENTAT_AGENT_MERGE": "off"}}'
printf '%s\n' "$on" >"$repo/.claude/settings.json"; r_tree=$repo
mkdir -p "$root_tmp/plain"
git init -q "$root_tmp/notorigin"
for state in "$r_off" "$r_yes" "$r_empty" "$r_none" "$r_bad" "$r_nofile" "$r_nohead" "$r_tree" none "$root_tmp/plain" "$root_tmp/notorigin" "$root_tmp/no such folder"; do
  label=${state#"$root_tmp"/}
  for cmd in "gh pr merge 7 --merge --match-head-commit $ok" 'gh pr merge 7 --squash' "PATH=/opt/example/bin:\$PATH gh pr merge 7 --merge --match-head-commit $ok"; do
    check "setting off or unreadable ($label): denies with today's reason: ${cmd:0:40}" '[ "$(in_decision "$state" "$cmd")" = deny ] && [ "$(in_reason "$state" "$cmd")" = "$today" ]'
  done
done
check "the process environment never turns it on" '[ "$(MENTAT_AGENT_MERGE=on in_decision "$r_off" "gh pr merge 7 --merge --match-head-commit $ok")" = deny ]'
check "settings in the working tree never turn it on" '[ "$(in_decision "$r_tree" "gh pr merge 7 --merge --match-head-commit $ok")" = deny ]'

# 6b: on, the allowed form passes with {} (so permission prompts still apply).
while IFS= read -r cmd; do
  cmd=${cmd//SHA/$ok}
  check "on: passes with {}: $cmd" '[ "$(hin "$onrepo" "$cmd")" = "{}" ]'
done <<'ALLOWED'
gh pr merge 7 --merge --match-head-commit SHA
gh pr merge 123 --merge --match-head-commit SHA
PATH=/opt/example/bin:$PATH gh pr merge 7 --merge --match-head-commit SHA
PATH="/opt/example/bin:$PATH" gh pr merge 7 --merge --match-head-commit SHA
PATH=/opt/example/bin:/usr/bin gh  pr merge 7 --merge --match-head-commit SHA
ALLOWED
check "on: a subfolder of the repository as cwd reads the same setting" '[ "$(hin "$onrepo/docs" "gh pr merge 7 --merge --match-head-commit $ok")" = "{}" ]'

# 6c: on, any other leading assignment is denied.
while IFS= read -r cmd; do
  cmd=${cmd//SHA/$ok}
  check "on: denies another assignment: ${cmd%% gh*}" '[ "$(in_decision "$onrepo" "$cmd")" = deny ]'
done <<'ASSIGN'
GH_REPO=o/r gh pr merge 7 --merge --match-head-commit SHA
GH_HOST=example.com gh pr merge 7 --merge --match-head-commit SHA
GH_TOKEN=abc gh pr merge 7 --merge --match-head-commit SHA
GIT_DIR=/opt/example/other gh pr merge 7 --merge --match-head-commit SHA
FOO=1 gh pr merge 7 --merge --match-head-commit SHA
PATH=/opt/example/bin GH_REPO=o/r gh pr merge 7 --merge --match-head-commit SHA
PATH=/opt/a PATH=/opt/b gh pr merge 7 --merge --match-head-commit SHA
export PATH=/opt/example/bin gh pr merge 7 --merge --match-head-commit SHA
ASSIGN

# 6d: on, a command with ; & | ` $( < > or a newline is denied.
base="gh pr merge 7 --merge --match-head-commit $ok"
nl=$'\n'
for extra in "; echo hi" " && echo hi" " & echo hi" " | cat" ' `id`' ' $(id)' " < /opt/example/in" " > /opt/example/out" "${nl}echo hi"; do
  check "on: denies a merge with ${extra:0:12}" '[ "$(in_decision "$onrepo" "$base$extra")" = deny ]'
done
check "on: denies a command that starts with a newline and then the allowed form" '[ "$(in_decision "$onrepo" "echo hi${nl}$base")" = deny ]'
check "on: denies the allowed form after a semicolon" '[ "$(in_decision "$onrepo" "echo hi; $base")" = deny ]'
for val in '"/opt/a;b"' '"/opt/a&b"' '"/opt/a|b"' '"/opt/a<b"' '"/opt/a>b"'; do
  check "on: denies a quoted PATH value holding a shell character: $val" '[ "$(in_decision "$onrepo" "PATH=$val $base")" = deny ]'
done
check "on: denies a PATH value with a command substitution" '[ "$(in_decision "$onrepo" "PATH=\$(id) $base")" = deny ]'

# 6e: on, any other gh pr merge command is denied, naming the one allowed form.
short=${ok:0:39}
while IFS= read -r cmd; do
  cmd=${cmd//SHA/$ok}
  cmd=${cmd//SHORT/$short}
  check "on: denies, naming the allowed form: $cmd" '[ "$(in_decision "$onrepo" "$cmd")" = deny ] && in_reason "$onrepo" "$cmd" | grep -qF "$form"'
done <<'OTHERS'
gh pr merge 7 --squash
gh pr merge 7
gh pr merge 7 --merge
gh pr merge 7 --merge --auto --match-head-commit SHA
gh pr merge 7 --merge --match-head-commit SHA --delete-branch
gh pr merge 7 --merge --admin --match-head-commit SHA
gh pr merge 7 --squash --match-head-commit SHA
gh pr merge 7 --rebase --match-head-commit SHA
gh pr merge 7 --match-head-commit SHA --merge
gh pr merge 7 --match-head-commit SHA
gh pr merge 7 --merge --match-head-commit SHORT
gh pr merge 7 --merge --match-head-commit SHAa
gh pr merge 7 --merge --match-head-commit ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD
gh pr merge 7 --merge --match-head-commit gggggggggggggggggggggggggggggggggggggggg
gh pr merge 7 --merge --match-head-commit main
gh pr merge feature-branch --merge --match-head-commit SHA
gh pr merge https://example.com/o/r/pull/7 --merge --match-head-commit SHA
gh pr merge --merge --match-head-commit SHA
gh pr merge 7 --merge --match-head-commit=SHA
gh -R o/r pr merge 7 --merge --match-head-commit SHA
gh --repo o/r pr merge 7 --merge --match-head-commit SHA
gh pr merge 7 --merge --match-head-commit SHA extra
echo gh pr merge 7 --merge --match-head-commit SHA
OTHERS
check "on: the denial still tells how to pass text that only mentions a merge" 'in_reason "$onrepo" "gh pr merge 7 --squash" | grep -qF "(-F or --body-file)"'

# 6f: on, the merge API, auto-merge and the desktop tool are denied as today.
for cmd in "gh api -X PUT repos/o/r/pulls/7/merge -f sha=$ok" "pr=7; gh api -X PUT \"repos/o/r/pulls/\$pr/merge\"" "gh pr merge 7 --auto --merge --match-head-commit $ok"; do
  check "on: denies: ${cmd:0:50}" '[ "$(in_decision "$onrepo" "$cmd")" = deny ]'
done
check "on: the merge API is denied with today's reason" '[ "$(in_reason "$onrepo" "gh api -X PUT repos/o/r/pulls/7/merge -f sha=$ok")" = "$today" ]'
tool_out() { jq -n --arg d "$onrepo" '{tool_name: "mcp__ccd_pr__set_auto_merge", cwd: $d, tool_input: {}}' | "$hook"; }
check "on: denies the desktop auto-merge tool with today's reason" '[ "$(tool_out | jq -r .hookSpecificOutput.permissionDecisionReason)" = "$today" ]'

# 6g: on, the allowed form for a commit that touches a protected path, is unknown, or
# cannot be read is denied, saying the pull request waits for the maintainer.
for sha in "$prot" "$ghp" "$unknown"; do
  cmd="gh pr merge 7 --merge --match-head-commit $sha"
  check "on: denies, the pull request waits for the maintainer ($sha)" '[ "$(in_decision "$onrepo" "$cmd")" = deny ] && in_reason "$onrepo" "$cmd" | grep -q "waits for the maintainer"'
done
check "on: a protected change is named in the reason" 'in_reason "$onrepo" "gh pr merge 7 --merge --match-head-commit $prot" | grep -qF "hooks/new"'
mkrepo '{"env": {"MENTAT_AGENT_MERGE": "on", "MENTAT_MERGE_WAIT_PATHS": ["hooks/"]}}'
c=$(branch "$repo" b docs/new.md)
check "on: denies when the wait list cannot be read" '[ "$(in_decision "$repo" "gh pr merge 7 --merge --match-head-commit $c")" = deny ] && in_reason "$repo" "gh pr merge 7 --merge --match-head-commit $c" | grep -q "waits for the maintainer"'
# A git whose diff fails, and a git that records every call and fails.
mkdir -p "$root_tmp/gitdiff" "$root_tmp/gitrec"
cat >"$root_tmp/gitdiff/git" <<STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = diff ] && exit 1; done
exec "$real_git" "\$@"
STUBEOF
cat >"$root_tmp/gitrec/git" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/git-calls"
exit 99
STUBEOF
chmod +x "$root_tmp/gitdiff/git" "$root_tmp/gitrec/git"
cmd="gh pr merge 7 --merge --match-head-commit $ok"
check "on: denies when the diff fails" '[ "$(PATH="$root_tmp/gitdiff:$PATH" hin "$onrepo" "$cmd" | jq -r .hookSpecificOutput.permissionDecision)" = deny ] && PATH="$root_tmp/gitdiff:$PATH" hin "$onrepo" "$cmd" | grep -q "waits for the maintainer"'

# 6h: a command that matches no merge pattern passes as today without reading the setting.
for cmd in "gh pr view 12" "ls -la" "gh pr create --title \"fix merge logic\"" "git status" "gh pr ready 7"; do
  check "a git that fails is never run for: $cmd" '[ "$(PATH="$root_tmp/gitrec:$PATH" hin "$onrepo" "$cmd")" = "{}" ]'
done
check "no command that matches no merge pattern ran git" '[ ! -f "$STUB/git-calls" ]'
check "a merge command with the setting off reads the setting once, with git" '
  PATH="$root_tmp/gitrec:$PATH" hin "$onrepo" "gh pr merge 7 --squash" >/dev/null; [ -f "$STUB/git-calls" ]'
rm -f "$STUB/git-calls"
# The hook behaves as today when lib/agent-merge.sh is missing.
mkdir -p "$root_tmp/nolib/hooks/lib"
cp "$hook" "$root_tmp/nolib/hooks/no-merge"
cp "$root/hooks/lib/verdict.sh" "$root_tmp/nolib/hooks/lib/verdict.sh"
nolib() { jq -n --arg d "$onrepo" --arg c "$1" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$root_tmp/nolib/hooks/no-merge"; }
check "without lib/agent-merge.sh the allowed form is denied as today" '[ "$(nolib "gh pr merge 7 --merge --match-head-commit $ok" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "$today" ]'
check "without lib/agent-merge.sh other commands pass" '[ "$(nolib "gh pr view 7")" = "{}" ]'
check "with the setting on, still reads nothing from GitHub" '[ ! -f "$STUB/calls" ]'

# 6i: on, what the hook denies on the merge hook's wider matching stays denied: the allowed
# form split by a backslash-newline, with a quoted number, flag or commit, followed by a
# second command on the next line, and an MCP merge tool.
bs='\'
while IFS= read -r cmd; do
  cmd=${cmd//SHA/$ok}
  cmd=${cmd//BS/$bs}
  cmd=${cmd//NL/$nl}
  check "on: still denies a continued or quoted form: ${cmd//$nl/<nl>}" '[ "$(in_decision "$onrepo" "$cmd")" = deny ]'
done <<'WIDER'
gh pr merge 7 --merge BSNL--match-head-commit SHA
gh pr merge 7 BSNL--merge --match-head-commit SHA
gh pr merge 7 --merge --match-head-commit BSNLSHA
gh pr merge BSNL7 --merge --match-head-commit SHA
gh BSNLpr merge 7 --merge --match-head-commit SHA
gh pr merge 7 --merge --match-head-commit SHA BSNL
gh pr merge "7" --merge --match-head-commit SHA
gh pr merge '7' --merge --match-head-commit SHA
gh pr merge 7 "--merge" --match-head-commit SHA
gh pr merge 7 '--merge' --match-head-commit SHA
gh pr merge 7 --merge "--match-head-commit" SHA
gh pr merge 7 --merge --match-head-commit "SHA"
gh pr merge 7 --merge --match-head-commit 'SHA'
gh pr merge 7 --merge --match-head-commit=SHA
gh pr merge 7 "--merge" --match-head-commit="SHA"
gh pr merge 7 --merge --match-head-commit SHANLecho hi
gh pr merge 7 --merge --match-head-commit SHANLgh pr merge 8 --squash
echo hiNLgh pr merge 7 --merge --match-head-commit SHA
WIDER
mcp_out() { jq -n --arg t "$1" --arg d "$onrepo" '{tool_name: $t, cwd: $d, tool_input: {}}' | "$hook"; }
for mcp in mcp__github__merge_pull_request mcp__ccd_pr__set_auto_merge mcp__example__enable_pr_auto_merge; do
  check "on: still denies the MCP tool $mcp with today's reason" '[ "$(mcp_out "$mcp" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "$today" ]'
done

[ "$failures" -eq 0 ]
