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
git -C . push
git status
PASS

# The directory comes from git -C, resolved against the session's cwd.
check "git -C <dir> push follows the directory (relative)" '[ "$(decision "$tmp" "git -C repo push")" = ask ]'
check "git -C <dir> push follows the directory (absolute)" '[ "$(decision / "git -C $tmp/repo push")" = ask ]'
check "git -C <feature checkout> push leaves alone" '[ -z "$(decision "$tmp" "git -C feat push")" ]'

# A checkout whose path has a space: quoting keeps it one word.
cp -R "$tmp/repo" "$tmp/my repo"
cp -R "$tmp/my repo" "$tmp/my feat"
g -C "$tmp/my feat" checkout -q -b feat/x
sp="$tmp/my repo"
esc="${sp// /\\ }"
check "path with a space, single quotes: asks" '[ "$(decision / "git -C '"'"'$sp'"'"' push")" = ask ]'
check "path with a space, double quotes: asks" '[ "$(decision / "git -C \"$sp\" push")" = ask ]'
check "path with a space, backslash: asks" '[ "$(decision / "git -C $esc push")" = ask ]'
check "path with a space, relative and quoted: asks" '[ "$(decision "$tmp" "git -C \"my repo\" push origin main")" = ask ]'
sf="$tmp/my feat"
esf="${sf// /\\ }"
check "path with a space on a feature branch, single quotes: leaves alone" '[ -z "$(decision / "git -C '"'"'$sf'"'"' push")" ]'
check "path with a space on a feature branch, double quotes: leaves alone" '[ -z "$(decision / "git -C \"$sf\" push")" ]'
check "path with a space on a feature branch, backslash: leaves alone" '[ -z "$(decision / "git -C $esf push")" ]'
check "a quoted message with spaces stays one word" '[ -z "$(decision "$tmp/repo" "git commit -m \"push origin main now\"")" ]'
check "an unmatched quote does not crash" '[ "$(decision "$tmp/repo" "git push origin main \"oops")" = ask ]'

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

# A force push asks on any branch, and the reason names it.
while IFS= read -r cmd; do
  check "on a feature branch asks before a force push: $cmd" '[ "$(decision "$tmp/feat" "$cmd")" = ask ]'
done <<'ASK'
git push --force origin feat/x
git push -f origin feat/x
git push -uf origin feat/x
git push -fu origin feat/x
git push -vfu origin feat/x
git push --force-with-lease
git push --force-with-lease origin feat/x
git push --force-with-lease=feat/x origin feat/x
git push --force-with-lease=feat/x:abc123 origin feat/x
git push origin +feat/x
git push origin +HEAD:feat/x
git status && git push --force origin feat/x
git fetch; git push -f
git commit -m "x" || git push origin +feat/x
ASK
while IFS= read -r cmd; do
  check "on a feature branch leaves alone, not a force push: $cmd" '[ -z "$(decision "$tmp/feat" "$cmd")" ]'
done <<'PASS'
git push -u origin feat/x
git push origin feat/x:feat/y
git push --no-force-with-lease origin feat/x
git commit -m "push -f later"
git push --follow-tags origin feat/x
git push --force-if-includes origin feat/x
git push -uv origin feat/x
PASS
force_reason="Mentat: agents do not force push (--force, -f, --force-with-lease or a +refspec). Approve only if you want this push to replace commits on the remote branch."
check "a force push on a feature branch: the reason names a force push" \
  '[ "$(reason "$tmp/feat" "git push --force origin feat/x")" = "$force_reason" ]'
check "a force push to the default branch: the reason names both" \
  '[ "$(reason "$tmp/repo" "git push -f origin main")" = "$force_reason Mentat: agents do not push to the default branch (main). Approve only if you want this push to go to it." ]'
check "two force pushes in one command: the reason names it once" \
  '[ "$(reason "$tmp/feat" "git push -f origin feat/x && git push origin +feat/x")" = "$force_reason" ]'

# A push or a pull request from a directory with uncommitted changes asks, and the reason names them.
cp -R "$tmp/feat" "$tmp/untracked"
touch "$tmp/untracked/new.txt"
cp -R "$tmp/feat" "$tmp/edited"
printf 'a\n' >"$tmp/edited/file.txt"
g -C "$tmp/edited" add file.txt
g -C "$tmp/edited" commit -q -m file
printf 'b\n' >"$tmp/edited/file.txt"
cp -R "$tmp/feat" "$tmp/staged"
printf 'a\n' >"$tmp/staged/file.txt"
g -C "$tmp/staged" add file.txt
for d in untracked edited staged; do
  while IFS= read -r cmd; do
    check "with uncommitted changes ($d) asks before: $cmd" '[ "$(decision "$tmp/$d" "$cmd")" = ask ]'
  done <<'ASK'
git push
git push -u origin feat/x
git push origin --tags
gh pr create --fill
gh pr create --title "x" --body "y"
git fetch && git push origin feat/x
git status; gh pr create --fill
ASK
done
check "with uncommitted changes, git -C <dir> push asks (relative)" '[ "$(decision "$tmp" "git -C edited push")" = ask ]'
check "with uncommitted changes, git -C <dir> push asks (absolute)" '[ "$(decision / "git -C $tmp/edited push")" = ask ]'
check "git -C <clean dir> push from a directory with changes leaves alone" '[ -z "$(decision "$tmp/edited" "git -C ../feat push")" ]'
while IFS= read -r cmd; do
  check "with uncommitted changes leaves alone: $cmd" '[ -z "$(decision "$tmp/edited" "$cmd")" ]'
done <<'PASS'
git status
git commit -am "push it"
git diff
gh pr view
gh pr list
gh pr checks
ls
PASS
unclean_reason="Mentat: agents push and open pull requests from a clean working tree, and git status lists uncommitted changes. Approve only if you want to go ahead without committing them."
check "with uncommitted changes: the reason names uncommitted changes" \
  '[ "$(reason "$tmp/edited" "git push origin feat/x")" = "$unclean_reason" ]'
check "with uncommitted changes, gh pr create: the reason names uncommitted changes" \
  '[ "$(reason "$tmp/untracked" "gh pr create --fill")" = "$unclean_reason" ]'
check "with uncommitted changes, a chained push and pull request: the reason names them once" \
  '[ "$(reason "$tmp/edited" "git push -u origin feat/x && gh pr create --fill")" = "$unclean_reason" ]'

# A cd earlier in the command sets the directory for the pieces after it.
cp -R "$tmp/edited" "$tmp/my edited"
while IFS= read -r cmd; do
  check "from a clean checkout asks before: $cmd" '[ "$(decision "$tmp/feat" "$cmd")" = ask ]'
done <<ASK
cd ../edited && git push
cd ../edited && gh pr create --fill
cd $tmp/edited && git push -u origin feat/x
cd $tmp/edited && gh pr create --fill
cd "../my edited" && gh pr create --fill
cd '$tmp/my edited' && git push
cd ../my\\ edited && git push
cd .. && cd edited && git push
env A=1 cd ../edited && gh pr create --fill
cd ../repo && git push
cd $tmp/repo && git push
cd ../repo && git -C ../repo push
ASK
while IFS= read -r cmd; do
  check "from a checkout with changes leaves alone: $cmd" '[ -z "$(decision "$tmp/edited" "$cmd")" ]'
done <<PASS
cd ../feat && git push
cd ../feat && gh pr create --fill
cd $tmp/feat && git push -u origin feat/x
cd "$tmp/my feat" && gh pr create --fill
cd .. && git -C feat push
PASS
check "a cd that cannot be resolved keeps the directory: cd -" '[ "$(decision "$tmp/edited" "cd - && git push")" = ask ]'
check "a cd to a missing directory keeps the directory" '[ "$(decision "$tmp/repo" "cd nowhere; git push")" = ask ]'
check "a bare cd goes to HOME" '[ "$(HOME="$tmp/edited" decision "$tmp/feat" "cd && git push")" = ask ]'
check "a cd ~/ goes to HOME" '[ "$(HOME="$tmp" decision "$tmp/feat" "cd ~/edited && gh pr create --fill")" = ask ]'
check "a cd after a push does not apply to it" '[ -z "$(decision "$tmp/feat" "git push && cd ../edited")" ]'

# A draft pull request asks, and the reason names it.
while IFS= read -r cmd; do
  check "on a feature branch asks before a draft pull request: $cmd" '[ "$(decision "$tmp/feat" "$cmd")" = ask ]'
done <<'ASK'
gh pr create --draft
gh pr create -d --fill
gh pr create --title "x" --draft --body "y"
gh pr create --draft=true --fill
gh pr new --draft
/usr/local/bin/gh pr create -d
GH_REPO=o/r gh pr create --draft
git push -u origin feat/x && gh pr create --draft --fill
git status; gh pr create -d
ASK
while IFS= read -r cmd; do
  check "on a feature branch leaves alone, not a draft pull request: $cmd" '[ -z "$(decision "$tmp/feat" "$cmd")" ]'
done <<'PASS'
gh pr create --fill
gh pr create --title "a --draft idea" --body "use -d"
gh pr create --draft=false --fill
gh pr ready
gh pr view --json isDraft
gh issue create --title x
git push -u origin feat/x && gh pr create --fill
PASS
draft_reason="Mentat: agents open pull requests as normal ones, not drafts (--draft or -d). Approve only if you want a draft pull request."
check "a draft pull request: the reason names a draft pull request" \
  '[ "$(reason "$tmp/feat" "gh pr create --draft --fill")" = "$draft_reason" ]'
check "a draft pull request with uncommitted changes: the reason names both" \
  '[ "$(reason "$tmp/untracked" "gh pr create --draft")" = "$draft_reason $unclean_reason" ]'

# A separator or newline inside quotes does not split the command.
while IFS= read -r cmd; do
  check "a quoted separator asks before a draft pull request: $cmd" '[ "$(decision "$tmp/feat" "$cmd")" = ask ]'
done <<'ASK'
gh pr create --title "A & B" --draft
gh pr create --body "| a | b |" --draft
gh pr create --title 'a; b' -d
ASK
check "a quoted separator leaves alone: gh pr create --title \"a; b\" --fill" \
  '[ -z "$(decision "$tmp/feat" "gh pr create --title \"a; b\" --fill")" ]'
multiline=$'gh pr create --title x --body "line one\n\nline | two" --draft'
check "a multi-line quoted body asks before a draft pull request" '[ "$(decision "$tmp/feat" "$multiline")" = ask ]'
heredoc=$'cat >notes.txt <<EOF\nit\'s done\nEOF\ngit push origin main'
check "an unmatched quote in a heredoc body still asks before main" '[ "$(decision "$tmp/feat" "$heredoc")" = ask ]'
check "a draft pull request after a quoted separator asks" \
  '[ "$(reason "$tmp/feat" "git commit -m \"a & b\" && gh pr create --draft")" = "$draft_reason" ]'
# A long inline body stays fast: the hook reads each command before it runs.
row="| \`hooks/no-default-push\` | it's a table row; with a & b, \$x and a \\\\ backslash | yes |"
body=""
for ((k = 0; k < 250; k++)); do body+="$row"$'\n'; done
long="gh pr create --title \"feat: x\" --body \"$body\" --draft"
start=$SECONDS
long_decision=$(decision "$tmp/feat" "$long")
elapsed=$((SECONDS - start))
check "a ${#long}-character pull request body asks before a draft pull request, in ${elapsed}s (under 3s)" \
  '[ "$long_decision" = ask ] && [ "$elapsed" -lt 3 ]'

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
# Without jq the hook exits before reading stdin, so a piped writer could be killed and pipefail would report its status.
out=$(PATH=/nonexistent /bin/bash "$hook" <<<'{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'); rc=$?
check "no jq: silent, exit 0" 'silent "$out" "$rc"'

check "hooks.json runs it on PreToolUse for Bash, beside the merge hook" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | endswith(\"/hooks/no-default-push\")] | any" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
