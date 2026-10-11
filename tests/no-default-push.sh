#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-default-push, the PreToolUse hook. Prints
# PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-default-push"
failures=0
check() { if eval "$2"; then printf 'PASS: no-default-push %s\n' "$1"; else printf 'FAIL: no-default-push %s\n' "$1"; failures=$((failures + 1)); fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# A repository with a real origin whose HEAD is main, checked out on main.
g init -q --bare "$tmp/origin.git"
g init -q "$tmp/repo"
g -C "$tmp/repo" remote add origin "$tmp/origin.git"
g -C "$tmp/repo" commit -q --allow-empty -m first
g -C "$tmp/repo" push -q origin main
g -C "$tmp/repo" remote set-head origin main >/dev/null
# The same repository on a feature branch, and one whose default is trunk.
cp -R "$tmp/repo" "$tmp/feat"
g -C "$tmp/feat" checkout -q -b feat/x
g init -q "$tmp/trunk"
g -C "$tmp/trunk" checkout -q -b trunk
g -C "$tmp/trunk" commit -q --allow-empty -m first
g -C "$tmp/trunk" update-ref refs/remotes/origin/trunk HEAD
g -C "$tmp/trunk" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
# No origin/HEAD at all: main and master both count.
g init -q "$tmp/bare"
g -C "$tmp/bare" checkout -q -b develop
g -C "$tmp/bare" commit -q --allow-empty -m first

# decision <cwd> <command>: prints the hook's permission decision, or nothing
decision() {
  jq -n --arg d "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' |
    "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

# On main (origin/HEAD is main).
while IFS= read -r cmd; do
  check "on main asks before: $cmd" '[ "$(decision "$tmp/repo" "$cmd")" = ask ]'
done <<'ASK'
git push origin main
git push -u origin main
git push origin HEAD:main
git push origin +main
git push origin refs/heads/main
git push origin feat/x:main
git push origin :main
git push --delete origin main
git push -d origin main
git push --all
git push --mirror origin
git push
git push origin
git push origin HEAD
git push --force-with-lease
git -C . push origin main
git -c push.default=current push
git status && git push origin main
git fetch; git push origin main
git commit -m "x" || git push origin HEAD:main
git add . | git push origin main
git push origin feat/x main
git push origin 'refs/heads/*:refs/heads/*'
ASK
while IFS= read -r cmd; do
  check "on main leaves alone: $cmd" '[ -z "$(decision "$tmp/repo" "$cmd")" ]'
done <<'PASS'
git push -u origin feat/x
git push origin feat/main-thing
git push origin feat/x:feat/y
git push origin HEAD:feat/x
git push origin --tags
git push --tags
git push origin v1.0
git status
git pull origin main
git fetch origin main
git commit -m "fix: ask before a push"
git log main..feat/x
ls
PASS

# On a feature branch.
while IFS= read -r cmd; do
  check "on a feature branch asks before: $cmd" '[ "$(decision "$tmp/feat" "$cmd")" = ask ]'
done <<'ASK'
git push origin main
git push origin HEAD:main
git push --all
ASK
while IFS= read -r cmd; do
  check "on a feature branch leaves alone: $cmd" '[ -z "$(decision "$tmp/feat" "$cmd")" ]'
done <<'PASS'
git push
git push origin
git push origin HEAD
git push -u origin feat/x
git push --force-with-lease origin feat/x
git -C . push
git status
PASS

# The directory comes from git -C, resolved against the session's cwd.
check "git -C <dir> push follows the directory (relative)" '[ "$(decision "$tmp" "git -C repo push")" = ask ]'
check "git -C <dir> push follows the directory (absolute)" '[ "$(decision / "git -C $tmp/repo push")" = ask ]'
check "git -C <feature checkout> push leaves alone" '[ -z "$(decision "$tmp" "git -C feat push")" ]'

# The default branch is whatever origin/HEAD says.
check "default trunk: asks before pushing trunk" '[ "$(decision "$tmp/trunk" "git push origin trunk")" = ask ]'
check "default trunk: asks before a bare push on trunk" '[ "$(decision "$tmp/trunk" "git push")" = ask ]'
check "default trunk: main is just a branch" '[ -z "$(decision "$tmp/trunk" "git push origin main")" ]'

# Without origin/HEAD, main and master both count.
check "no origin/HEAD: asks before main" '[ "$(decision "$tmp/bare" "git push origin main")" = ask ]'
check "no origin/HEAD: asks before master" '[ "$(decision "$tmp/bare" "git push origin master")" = ask ]'
check "no origin/HEAD: leaves develop alone" '[ -z "$(decision "$tmp/bare" "git push origin develop")" ]'
check "no origin/HEAD: leaves a bare push on develop alone" '[ -z "$(decision "$tmp/bare" "git push")" ]'
check "outside a repository: asks before main" '[ "$(decision "$tmp" "git push origin main")" = ask ]'

# The reason names the branch.
reason() { decision_json "$1" "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
decision_json() {
  jq -n --arg d "$1" --arg c "$2" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$hook"
}
check "the reason names the default branch" \
  '[ "$(reason "$tmp/repo" "git push origin main")" = "Mentat: agents do not push to the default branch (main). Approve only if you want this push to go to it." ]'

# Without a cwd in the input, the process directory is used.
nocwd() { (cd "$tmp/repo" && jq -n '{tool_name: "Bash", tool_input: {command: "git push"}}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty'); }
check "no cwd in the input: uses the process directory" '[ "$(nocwd)" = ask ]'

# Other tools and input it cannot read: no output, exit 0.
silent() { [ -z "$1" ] && [ "$2" -eq 0 ]; }
out=$(printf '' | "$hook"); rc=$?
check "empty input: silent, exit 0" 'silent "$out" "$rc"'
out=$(printf 'not json' | "$hook"); rc=$?
check "bad JSON: silent, exit 0" 'silent "$out" "$rc"'
out=$(printf '{"tool_name":"Bash","tool_input":{}}' | "$hook"); rc=$?
check "no command: silent, exit 0" 'silent "$out" "$rc"'
out=$(jq -n --arg d "$tmp/repo" '{tool_name: "Write", cwd: $d, tool_input: {command: "git push origin main"}}' | "$hook"); rc=$?
check "another tool: silent, exit 0" 'silent "$out" "$rc"'
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | PATH=/nonexistent /bin/bash "$hook"); rc=$?
check "no jq: silent, exit 0" 'silent "$out" "$rc"'

check "hooks.json runs it on PreToolUse for Bash, beside the merge hook" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | endswith(\"/hooks/no-default-push\")] | any" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
