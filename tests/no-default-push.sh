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
git push --repo origin
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
git push --repo origin main
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
git push --repo origin feat/x
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
git push --repo origin +HEAD:feat/x
git push --repo=origin +feat/x
(git push --force origin feat/x)
{ git push -f; }
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
# A cd joined by && away from a checkout with changes checks only the directory it goes to.
while IFS= read -r cmd; do
  check "from a checkout with changes, a cd joined by && to a clean one leaves alone: $cmd" '[ -z "$(decision "$tmp/edited" "$cmd")" ]'
done <<PASS
cd ../feat && git push
cd ../feat && gh pr create --fill
cd $tmp/feat && git push -u origin feat/x
cd "$tmp/my feat" && gh pr create --fill
PASS
# Any other join still checks the session directory too.
while IFS= read -r cmd; do
  check "from a checkout with changes asks before: $cmd" '[ "$(reason "$tmp/edited" "$cmd")" = "$unclean_reason" ]'
done <<ASK
cd ../feat; git push
cd ../feat; gh pr create --fill
cd $tmp/feat || git push -u origin feat/x
cd "$tmp/my feat" & gh pr create --fill
ASK
newline_pr=$'cd ../feat\ngh pr create --fill'
check "from a checkout with changes, a cd on the line before still asks" '[ "$(reason "$tmp/edited" "$newline_pr")" = "$unclean_reason" ]'
check "from a checkout with changes leaves alone: cd .. && git -C feat push" '[ -z "$(decision "$tmp/edited" "cd .. && git -C feat push")" ]'
check "a cd - with no previous directory goes back to the session cwd" '[ "$(decision "$tmp/edited" "cd - && git push")" = ask ]'
check "a cd - goes back to the previous directory" '[ "$(decision "$tmp/feat" "cd ../edited && cd ../feat && tests/run && cd - && git push")" = ask ]'
check "a cd - swaps with the previous directory" '[ "$(decision "$tmp/feat" "cd ../edited && cd ../feat && cd - && git push")" = ask ]'
check "a cd -- <dir> goes to the directory" '[ "$(decision "$tmp/feat" "cd -- ../edited && git push")" = ask ]'
check "a cd in a subshell applies inside it" '[ "$(decision "$tmp/feat" "(cd ../edited && git push)")" = ask ]'
check "a cd joined by && in a subshell from a checkout with changes checks only its directory" '[ -z "$(decision "$tmp/edited" "(cd ../feat && git push)")" ]'
check "a cd in a subshell ends with it" '[ "$(decision "$tmp/edited" "(cd ../feat) && git push")" = ask ]'
mkdir "$tmp/repo/tests"
check "from a checkout on main, a cd after a nested subshell still asks" \
  '[ "$(decision "$tmp/repo" "(cd tests && (./run) && cd .. && git push)")" = ask ]'
check "from a checkout on main, a cd after a spaced nested subshell still asks" \
  '[ "$(decision "$tmp/repo" "(cd tests && ( ./run ) && cd .. && git push)")" = ask ]'
# A cd the hook misreads still checks the session directory.
check "a cd the hook misreads still checks the session directory: changes" \
  '[ "$(reason "$tmp/edited" "(cd ../feat && true) >log && git push")" = "$unclean_reason" ]'
check "a cd the hook misreads still checks the session directory: main" \
  '[ "$(decision "$tmp/repo" "(cd ../feat && true) >log && git push")" = ask ]'
check "a cd the hook misreads still checks the session directory: pull request" \
  '[ "$(reason "$tmp/edited" "(cd ../feat && true) >log && gh pr create --fill")" = "$unclean_reason" ]'
check "a cd to a missing directory keeps the directory" '[ "$(decision "$tmp/repo" "cd nowhere; git push")" = ask ]'
check "a bare cd goes to HOME" '[ "$(HOME="$tmp/edited" decision "$tmp/feat" "cd && git push")" = ask ]'
check "a cd ~/ goes to HOME" '[ "$(HOME="$tmp" decision "$tmp/feat" "cd ~/edited && gh pr create --fill")" = ask ]'
check "a cd after a push does not apply to it" '[ -z "$(decision "$tmp/feat" "git push && cd ../edited")" ]'

# A cd joined to the push or pull request only by && at the same level: only its folder is checked.
while IFS= read -r cmd; do
  check "from a checkout on main, a cd joined by && leaves alone: $cmd" '[ -z "$(decision "$tmp/repo" "$cmd")" ]'
done <<PASS
cd ../feat && git push -q
cd ../feat && git push -q origin HEAD
cd $tmp/feat && tests/run && git push
cd ../feat && make 2>&1 && git push
cd ../feat && make >log 2>&1 && git push -q
cd ../feat && git add -A && git commit -qm "fix: a; b | c & d" && git push -q origin HEAD
cd ../feat && git commit -m "fix: x (WRK-1)" && git push
cd ../feat && git push origin &>/dev/null
cd ../feat && gh pr create --fill
command cd ../feat && git push
A=1 cd ../feat && git push
{ cd ../feat && git push; }
(cd ../feat && git push)
true; cd ../feat && git push
git status && cd ../feat && git push
PASS
while IFS= read -r cmd; do
  check "from a checkout on main, a quoted separator in the push arguments leaves alone: $cmd" '[ -z "$(decision "$tmp/repo" "$cmd")" ]'
done <<'PASS'
cd ../feat && git push -o "merge_request.title=fix: x & y" origin HEAD
cd ../feat && git push -o "title=a; b" origin HEAD
cd ../feat && git push -o 'title=a | b' -q
cd ../feat && git push -o "a && b || c" -q
PASS
check "from a checkout with changes, a quoted separator in a pull request title leaves alone" \
  '[ -z "$(decision "$tmp/edited" "cd ../feat && gh pr create --title \"a; b & c | d\" --fill")" ]'
multi_pr=$'cd ../feat && gh pr create --title t --body "line one\nline two"'
multi_push=$'cd ../feat && git push -o "line one\nline two" origin HEAD'
check "from a checkout with changes, a quoted newline in a pull request body leaves alone" '[ -z "$(decision "$tmp/edited" "$multi_pr")" ]'
check "from a checkout on main, a quoted newline in the push arguments leaves alone" '[ -z "$(decision "$tmp/repo" "$multi_push")" ]'
check "from a checkout on main, a push inside a quoted command before another push still asks" \
  '[ "$(decision "$tmp/repo" "sh -c \"a; git push; b\"; git push origin feat/x")" = ask ]'
check "from a checkout on main, a push inside a quoted command with the same text as a later push still asks" \
  '[ "$(decision "$tmp/repo" "sh -c \"git fetch; git push; true\"; cd ../feat && git push")" = ask ]'
check "from a checkout on main, a push inside a quoted command after a cd still asks" \
  '[ "$(decision "$tmp/repo" "cd ../feat && sh -c \"git fetch; git push origin main\"")" = ask ]'
cont_cd=$'cd ../feat && \\\n  git push -q'
check "from a checkout on main, a cd joined by && across a continued line leaves alone" '[ -z "$(decision "$tmp/repo" "$cont_cd")" ]'
while IFS= read -r cmd; do
  check "from a checkout on main, a cd not joined by && alone still asks: $cmd" '[ "$(decision "$tmp/repo" "$cmd")" = ask ]'
done <<'ASK'
cd ../feat; git push -q
cd ../feat || git push -q
cd ../feat | git push -q
cd ../feat & git push -q
cd ../feat && true; git push -q
cd ../feat && true || git push -q
cd ../feat && true | git push -q
cd ../feat && make |& cat && git push -q
cd ../feat && (true) && git push -q
cd ../feat && { true; } && git push -q
cd ../feat && (git push -q)
cd ../feat && { git push -q; }
(cd ../feat) && git push -q
(cd ../feat && true) && git push -q
(cd ../feat && true) 2>&1 && git push -q
(cd ../feat && true) >log && git push -q
false || cd ../feat && git push -q
true | cd ../feat && git push -q
env cd ../feat && git push -q
sudo cd ../feat && git push -q
nohup cd ../feat && git push -q
time cd ../feat && git push -q
cd nowhere && git push -q
cd ~nobody-here && git push -q
cd "$WT" && git push -q
cd ../feat && cd "$WT" && git push -q
cd ../feat && cd nowhere && git push -q
git push origin &>/dev/null
ASK
newline_cd=$'cd ../feat\ngit push -q'
check "from a checkout on main, a cd on the line before still asks" '[ "$(decision "$tmp/repo" "$newline_cd")" = ask ]'
while IFS= read -r cmd; do
  check "a cd joined by && to a feature checkout still asks before: $cmd" '[ "$(decision "$tmp/repo" "$cmd")" = ask ]'
done <<ASK
cd ../feat && git push origin main
cd ../feat && git push origin HEAD:main
cd ../feat && git push origin main &>/dev/null
cd ../feat && git push --all
cd ../feat && git push --mirror
cd ../feat && git push --force
cd ../feat && git push -f origin feat/x
cd ../feat && git push origin +feat/x
cd ../feat && git push origin 'refs/heads/*:refs/heads/*'
cd ../feat && git -C ../repo push
cd ../feat && git -C $tmp/repo push
cd ../edited && git push -q
cd ../edited && gh pr create --fill
ASK
check "a cd joined by && to a checkout on main still asks" '[ "$(decision "$tmp/feat" "cd ../repo && git push -q")" = ask ]'

# ~, $HOME and ${HOME} in git -C and cd go to HOME.
mkdir "$tmp/home"
cp -R "$tmp/edited" "$tmp/home/repo"
cp -R "$tmp/feat" "$tmp/home/clean"
cp -R "$tmp/repo" "$tmp/home/main-checkout"
while IFS= read -r cmd; do
  check "with HOME holding a checkout with changes asks before: $cmd" '[ "$(HOME="$tmp/home" decision "$tmp/feat" "$cmd")" = ask ]'
  clean_cmd=${cmd//repo/clean}
  check "with HOME holding a clean checkout leaves alone: $clean_cmd" '[ -z "$(HOME="$tmp/home" decision "$tmp/feat" "$clean_cmd")" ]'
done <<'ASK'
git -C ~/repo push
git -C "$HOME/repo" push
git -C "${HOME}/repo" push
cd "$HOME/repo" && git push
cd ${HOME}/repo && git push
cd $HOME && git -C repo push
cd ${HOME} && git -C repo push
ASK
check "a cd joined by && before git -C still checks the -C directory from the session's" \
  '[ "$(decision "$tmp/home" "cd ../feat && git -C main-checkout push")" = ask ]'
check "git -C ~/<checkout on main> push names the default branch" \
  '[ "$(HOME="$tmp/home" reason "$tmp/feat" "git -C ~/main-checkout push")" = "Mentat: agents do not push to the default branch (main). Approve only if you want this push to go to it." ]'

# A draft pull request is a normal choice: from a clean checkout nothing asks.
while IFS= read -r cmd; do
  check "on a feature branch leaves alone, a draft pull request: $cmd" '[ -z "$(decision "$tmp/feat" "$cmd")" ]'
done <<'PASS'
gh pr create --draft
gh pr create -d --fill
gh pr create --title "x" --draft --body "y"
gh pr create --draft=true --fill
gh pr new --draft
/usr/local/bin/gh pr create -d
GH_REPO=o/r gh pr create --draft
git push -u origin feat/x && gh pr create --draft --fill
git status; gh pr create -d
gh pr create -df
gh pr create -fd
gh pr create -wd
(gh pr create --draft)
gh -R o/r pr create --draft
gh --repo o/r pr create -d
gh pr -R o/r create --draft
gh pr --repo o/r create -d
gh pr create --fill
gh pr create --title "a --draft idea" --body "use -d"
gh pr create --draft=false --fill
gh pr create -f
gh pr create --fill --draft=false
gh pr ready
gh pr view --json isDraft
gh issue create --title x
git push -u origin feat/x && gh pr create --fill
PASS
# A draft still gets the other checks.
check "a draft pull request with uncommitted changes: the reason names only those" \
  '[ "$(reason "$tmp/untracked" "gh pr create --draft")" = "$unclean_reason" ]'
check "a chained force push before a draft pull request: the reason names only the force push" \
  '[ "$(reason "$tmp/feat" "git push -f origin feat/x && gh pr create --draft")" = "$force_reason" ]'

# A separator or newline inside quotes does not split the command.
while IFS= read -r cmd; do
  check "a quoted separator asks before a force push: $cmd" '[ "$(reason "$tmp/feat" "$cmd")" = "$force_reason" ]'
done <<'ASK'
git push -o "A & B" --force origin feat/x
git push -o "| a | b |" origin +feat/x
git push -o 'a; b' -f origin feat/x
ASK
while IFS= read -r cmd; do
  check "a quoted separator with uncommitted changes asks before: $cmd" '[ "$(reason "$tmp/edited" "$cmd")" = "$unclean_reason" ]'
done <<'ASK'
gh --repo "o & r" pr create --fill
gh pr -R 'a; b' create --fill
ASK
check "a quoted separator leaves alone: gh pr create --title \"a; b\" --fill" \
  '[ -z "$(decision "$tmp/feat" "gh pr create --title \"a; b\" --fill")" ]'
multiline=$'git push -o "line one\n\nline | two" --force origin feat/x'
check "a multi-line quoted value asks before a force push" '[ "$(reason "$tmp/feat" "$multiline")" = "$force_reason" ]'
heredoc=$'cat >notes.txt <<EOF\nit\'s done\nEOF\ngit push origin main'
check "an unmatched quote in a heredoc body still asks before main" '[ "$(decision "$tmp/feat" "$heredoc")" = ask ]'
check "a push after a separator inside a quoted command asks before main" \
  '[ "$(decision "$tmp/feat" "sh -c \"git fetch; git push origin main\"")" = ask ]'
check "a force push after a quoted separator asks" \
  '[ "$(reason "$tmp/feat" "git commit -m \"a & b\" && git push --force origin feat/x")" = "$force_reason" ]'

# A backslash-newline outside single quotes continues the line.
cont_force=$'git push \\\n  --force origin feat/x'
cont_plus=$'git push origin \\\n  +feat/x'
cont_twice=$'git push \\\n  --repo origin \\\n  --force feat/x'
cont_fill=$'gh pr create \\\n  --fill'
cont_dq=$'git -C "'"$tmp"$'/ed\\\nited" push'
single_body=$'git push --push-option \'a \\\n--force\' origin feat/x'
single_then_force=$'git push --push-option \'a \\\n--fill\' \\\n  --force origin feat/x'
check "a continued line asks before a force push" '[ "$(reason "$tmp/feat" "$cont_force")" = "$force_reason" ]'
check "a continued line asks before a +refspec" '[ "$(reason "$tmp/feat" "$cont_plus")" = "$force_reason" ]'
check "two continued lines ask before a force push" '[ "$(reason "$tmp/feat" "$cont_twice")" = "$force_reason" ]'
check "a continued line leaves alone: gh pr create --fill" '[ -z "$(decision "$tmp/feat" "$cont_fill")" ]'
check "a continued line with uncommitted changes asks before: gh pr create --fill" '[ "$(reason "$tmp/edited" "$cont_fill")" = "$unclean_reason" ]'
check "a continued line inside double quotes joins the path" '[ "$(reason / "$cont_dq")" = "$unclean_reason" ]'
check "a backslash-newline inside single quotes stays in the value" '[ -z "$(decision "$tmp/feat" "$single_body")" ]'
check "a continued line after a single-quoted value asks before a force push" \
  '[ "$(reason "$tmp/feat" "$single_then_force")" = "$force_reason" ]'
# An apostrophe that leaves the quoted split inside a quote: the plain split joins the continued lines.
comment_cont=$'# It\'s ready\ngit push \\\n  --force origin feat/x\ngit push origin \\\n  main'
heredoc_cont=$'cat >notes <<EOF\nit\'s done\nEOF\ngit push \\\n  --force origin feat/x'
cont_plain=$'git push \\\n  origin feat/x'
check "continued lines after an apostrophe in a comment ask before a force push and a push to main" \
  '[ "$(reason "$tmp/feat" "$comment_cont")" = "$force_reason Mentat: agents do not push to the default branch (main). Approve only if you want this push to go to it." ]'
check "a continued line after an apostrophe in a heredoc asks before a force push" \
  '[ "$(reason "$tmp/feat" "$heredoc_cont")" = "$force_reason" ]'
check "a continued line leaves alone: git push origin feat/x" '[ -z "$(decision "$tmp/feat" "$cont_plain")" ]'
# A long inline body stays fast: the hook reads each command before it runs.
row="| \`hooks/no-default-push\` | it's a table row; with a & b, \$x and a \\\\ backslash | yes |"
body=""
for ((k = 0; k < 250; k++)); do body+="$row"$'\n'; done
long="gh pr create --title \"feat: x\" --body \"$body\" --fill"
start=$SECONDS
long_decision=$(decision "$tmp/edited" "$long")
elapsed=$((SECONDS - start))
check "a ${#long}-character pull request body with uncommitted changes asks, in ${elapsed}s (under 5s)" \
  '[ "$long_decision" = ask ] && [ "$elapsed" -lt 5 ]'
long_push="git push -o \"$body\" --force origin feat/x"
start=$SECONDS
long_decision=$(decision "$tmp/feat" "$long_push")
elapsed=$((SECONDS - start))
check "a force push after a ${#long_push}-character quoted value asks, in ${elapsed}s (under 5s)" \
  '[ "$long_decision" = ask ] && [ "$elapsed" -lt 5 ]'

# gh flags before or after pr, such as -R or --repo with its value, are skipped.
while IFS= read -r cmd; do
  check "with uncommitted changes asks before: $cmd" '[ "$(decision "$tmp/edited" "$cmd")" = ask ]'
done <<'ASK'
gh -R o/r pr create --fill
gh --repo o/r pr create --fill
gh pr -R o/r create --fill
gh pr --repo o/r create --fill
ASK
check "with uncommitted changes asks before: gh --repo=o/r pr create --fill" '[ "$(decision "$tmp/edited" "gh --repo=o/r pr create --fill")" = ask ]'
check "with uncommitted changes leaves alone: gh -R o/r pr view" '[ -z "$(decision "$tmp/edited" "gh -R o/r pr view")" ]'
check "with uncommitted changes leaves alone: gh pr -R o/r view" '[ -z "$(decision "$tmp/edited" "gh pr -R o/r view")" ]'

# A pull request whose branch changes agent instruction files asks, from the merge base with origin/<default>.
g init -q "$tmp/ibase"
mkdir -p "$tmp/ibase/skills/x" "$tmp/ibase/prompts" "$tmp/ibase/docs/prompts"
for f in AGENTS.md rules.md prompts/builder.md skills/x/SKILL.md docs/rules.md docs/prompts/x.md README.md; do
  printf 'a\n' >"$tmp/ibase/$f"
done
g -C "$tmp/ibase" add -A
g -C "$tmp/ibase" commit -q -m base
g -C "$tmp/ibase" update-ref refs/remotes/origin/main HEAD
g -C "$tmp/ibase" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
g -C "$tmp/ibase" checkout -q -b feat/i
# branch <name> <change>: a copy of ibase with <change> run in it and committed.
branch() {
  cp -R "$tmp/ibase" "$tmp/$1"
  (cd "$tmp/$1" && eval "$2") >/dev/null
  g -C "$tmp/$1" add -A
  g -C "$tmp/$1" commit -q -m change
}
branch i-agents 'printf "b\n" >>AGENTS.md'
branch i-new 'mkdir -p a/b && printf "x\n" >a/b/AGENTS.override.md'
branch i-claude 'printf "x\n" >docs/CLAUDE.md'
branch i-skill 'printf "b\n" >>skills/x/SKILL.md'
branch i-rules 'printf "b\n" >>rules.md'
branch i-prompts 'printf "b\n" >>prompts/builder.md'
branch i-rename 'g mv AGENTS.md notes.md'
branch i-delete 'g rm -q rules.md'
branch i-other 'printf "b\n" >>README.md; printf "b\n" >>docs/rules.md; printf "b\n" >>docs/prompts/x.md; printf "x\n" >AGENTS.txt'
instr_reason="Mentat: this pull request changes agent instructions, and a change to what agents are told gets mentat second-opinion before the maintainer agrees to it. Approve if it got one, if Codex and Grok are off for this session, or if it changes no meaning."
for d in i-agents i-new i-claude i-skill i-rules i-prompts i-rename i-delete; do
  while IFS= read -r cmd; do
    check "a branch changing instructions ($d) asks with that reason before: $cmd" '[ "$(reason "$tmp/$d" "$cmd")" = "$instr_reason" ]'
  done <<'ASK'
gh pr create --fill
gh pr new --draft
git push -u origin feat/i && gh pr create --fill
ASK
done
while IFS= read -r cmd; do
  check "a branch changing only other files leaves alone: $cmd" '[ -z "$(decision "$tmp/i-other" "$cmd")" ]'
done <<'PASS'
gh pr create --fill
gh pr new --draft
PASS
while IFS= read -r cmd; do
  check "a branch changing instructions leaves alone: $cmd" '[ -z "$(decision "$tmp/i-agents" "$cmd")" ]'
done <<'PASS'
git push
git push -u origin feat/i
gh pr view
PASS
# Without origin/HEAD, origin/main or origin/master is the default.
cp -R "$tmp/i-agents" "$tmp/i-nohead"
g -C "$tmp/i-nohead" symbolic-ref --delete refs/remotes/origin/HEAD
check "a branch changing instructions, no origin/HEAD but origin/main: asks with that reason" \
  '[ "$(reason "$tmp/i-nohead" "gh pr create --fill")" = "$instr_reason" ]'
# No default-branch ref, or no merge base with it: nothing to compare, no prompt.
cp -R "$tmp/i-nohead" "$tmp/i-noref"
g -C "$tmp/i-noref" update-ref -d refs/remotes/origin/main
check "a branch changing instructions, no default-branch ref: leaves alone" '[ -z "$(decision "$tmp/i-noref" "gh pr create --fill")" ]'
cp -R "$tmp/i-agents" "$tmp/i-unrelated"
g -C "$tmp/i-unrelated" update-ref refs/remotes/origin/main "$(g -C "$tmp/i-unrelated" commit-tree -m other "$(g -C "$tmp/i-unrelated" mktree </dev/null)")"
check "a branch changing instructions, no merge base with the default branch: leaves alone" \
  '[ -z "$(decision "$tmp/i-unrelated" "gh pr create --fill")" ]'
# With uncommitted changes too, one prompt gives both reasons.
cp -R "$tmp/i-agents" "$tmp/i-dirty"
touch "$tmp/i-dirty/new.txt"
check "a branch changing instructions with uncommitted changes: one prompt names both" \
  '[ "$(reason "$tmp/i-dirty" "gh pr create --fill")" = "$unclean_reason $instr_reason" ]'
# A cd is followed as for the clean-tree check.
check "a cd to a branch changing instructions asks before gh pr create" \
  '[ "$(reason "$tmp/feat" "cd ../i-agents && gh pr create --fill")" = "$instr_reason" ]'
check "a cd joined by && away from a branch changing instructions checks only its directory" \
  '[ -z "$(decision "$tmp/i-agents" "cd ../feat && gh pr create --fill")" ]'
check "a cd joined by || away from a branch changing instructions still asks before gh pr create" \
  '[ "$(reason "$tmp/i-agents" "cd ../feat || gh pr create --fill")" = "$instr_reason" ]'
check "a cd to a branch changing only other files leaves alone" '[ -z "$(decision "$tmp/feat" "cd ../i-other && gh pr create --fill")" ]'
check "a cd joined by && away from a branch changing instructions leaves alone" '[ -z "$(decision "$tmp/i-agents" "cd ../i-other && gh pr create --fill")" ]'
check "a cd joined by ; away from a branch changing instructions still asks" \
  '[ "$(reason "$tmp/i-agents" "cd ../i-other; gh pr create --fill")" = "$instr_reason" ]'
check "a cd joined by && to a branch changing instructions asks" \
  '[ "$(reason "$tmp/i-other" "cd ../i-agents && gh pr create --fill")" = "$instr_reason" ]'
# Paths are read from the repository root, even from a subdirectory with diff.relative set.
cp -R "$tmp/i-rules" "$tmp/i-relative"
g -C "$tmp/i-relative" config diff.relative true
check "a branch changing the root rules.md, from a subdirectory with diff.relative: asks with that reason" \
  '[ "$(reason "$tmp/i-relative/docs" "gh pr create --fill")" = "$instr_reason" ]'

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
