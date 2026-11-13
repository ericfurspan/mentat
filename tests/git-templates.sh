#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for git-templates/ (the pre-commit and pre-push templates, the scanner
# and own-hook.sh) and the session-start check of the installed copy. An agent's git
# names the templates' folder in core.hooksPath through GIT_CONFIG_* entries; the
# maintainer's git has no such entries. A stub gitleaks and local bare repositories
# stand in for the real ones. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
check() { if eval "$2"; then printf 'PASS: git-templates %s\n' "$1"; else printf 'FAIL: git-templates %s\n' "$1"; failures=$((failures + 1)); fi; }

base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
tmp="$base/with space"
export STUB="$tmp/stub"
export HOME="$tmp/home"
unset XDG_CONFIG_HOME GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS MENTAT_OWN_HOOK MENTAT_GIT_TEMPLATES_DIR
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/gitconfig"
mkdir -p "$STUB" "$tmp/bin" "$HOME" "$tmp/tmpdir"
export TMPDIR="$tmp/tmpdir"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"

# gitleaks: records its arguments and stdin, prints text that must never reach the
# output, and writes a JSON report to --report-path. Each stdin line holding
# stubmatchedtext is a finding of stub-rule. Exits with --exit-code on a finding, else
# 0. $STUB/error: fails with no report.
cat >"$tmp/bin/gitleaks" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
cat >"$STUB/stdin"
echo "stubgitleaksoutput stubmatchedtext"
echo "stubgitleaksoutput stubmatchedtext" >&2
report="" code=1
while [ $# -gt 0 ]; do
  case "$1" in
    --report-path) report=$2; shift ;;
    --exit-code) code=$2; shift ;;
  esac
  shift
done
[ ! -f "$STUB/error" ] || exit 1
lines=$(grep -n stubmatchedtext "$STUB/stdin" | cut -d: -f1)
if [ -z "$lines" ]; then echo '[]' >"$report"; exit 0; fi
printf '%s\n' "$lines" | jq -R 'tonumber | {RuleID: "stub-rule", StartLine: ., File: "", Secret: "stubmatchedtext", Match: "token = stubmatchedtext"}' | jq -s . >"$report"
exit "$code"
STUBEOF
chmod +x "$tmp/bin/gitleaks"
export PATH="$tmp/bin:$PATH"
tpl="$root/git-templates/hooks"

# A bare origin whose HEAD is main, and a clone on a feature branch.
git init -q --bare "$tmp/origin.git"
# The remote itself would let its HEAD branch be deleted, so only the hook refuses it.
git --git-dir="$tmp/origin.git" config receive.denyDeleteCurrent ignore
git init -q "$tmp/seed"
printf 'one\ntoken = stubmatchedtext\n' >"$tmp/seed/kept.txt"
git -C "$tmp/seed" add -A
git -C "$tmp/seed" commit -q -m first
git -C "$tmp/seed" push -q "$tmp/origin.git" main
git clone -q "$tmp/origin.git" "$tmp/repo"
repo="$tmp/repo"
git -C "$repo" checkout -q -b feat/x

# A <args>: git in an agent's shell, from $repo (or $in), with the templates' folder as
# core.hooksPath. M <args>: the maintainer's git, with no such entry.
in=$repo
A() { (cd "$in" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$tpl" git "$@") >"$STUB/out" 2>&1; }
M() { (cd "$in" && git "$@") >"$STUB/out" 2>&1; }
remote_head() { git --git-dir="$tmp/origin.git" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
head_of() { git -C "$in" rev-parse HEAD; }
no_leak() { ! grep -q -e stubmatchedtext -e stubgitleaksoutput "$STUB/out"; }
reset() { rm -rf "${STUB:?}"/*; git -C "$repo" reset -q --hard; git -C "$repo" clean -q -fdx; }
stage_hit() { printf 'a\ntoken = stubmatchedtext\n' >"$in/file two.txt"; git -C "$in" add -A; }
stage_clean() { printf '%s\n' "$1" >"$in/$1.txt"; git -C "$in" add -A; }

# Commits.
reset; stage_hit; h=$(head_of)
A commit -q -m "add file"; rc=$?
check "a staged invented secret is refused by the pre-commit template" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ]'
check "the refusal names the rule and the file" 'grep -qF "stub-rule in file two.txt" "$STUB/out" && grep -q "commit refused" "$STUB/out"'
check "the refusal never shows the match or gitleaks output" 'no_leak'
check "gitleaks runs on stdin with redaction and a JSON report" 'grep -q "^stdin --no-banner --redact --log-level fatal --exit-code 3 --report-format json --report-path " "$STUB/calls"'
check "leaves no temporary files" '[ -z "$(ls -A "$TMPDIR")" ]'
reset; stage_clean clean; h=$(head_of)
A commit -q -m "add clean"; rc=$?
check "a clean commit goes through" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -s "$STUB/calls" ]'
reset; printf 'more\ntoken = stubmatchedtext\n' >>"$repo/clean.txt"; h=$(head_of)
A commit -q -a -m "edit"; rc=$?
check "git commit -a with nothing staged before is scanned for what it commits" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in clean.txt" "$STUB/out"'
reset; git -C "$repo" rm -q kept.txt; h=$(head_of)
A commit -q -m "remove kept"; rc=$?
check "a removed line with a finding passes" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -s "$STUB/calls" ]'
reset; stage_hit; touch "$STUB/error"; h=$(head_of)
A commit -q -m "add file"; rc=$?
check "a gitleaks error refuses as a failed scan" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -q "could not run" "$STUB/out" && ! grep -q stub-rule "$STUB/out" && no_leak'
reset; stage_hit; h=$(head_of)
M commit -q -m "maintainer commit"; rc=$?
check "the maintainer's git runs no template: a commit with the invented secret goes through unscanned" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ ! -e "$STUB/calls" ]'
git -C "$repo" reset -q --hard "$h"

# A missing scanner refuses.
mkdir "$tmp/nogitleaks"
ln -s "$(command -v git)" "$tmp/nogitleaks/git"
ln -s "$(command -v jq)" "$tmp/nogitleaks/jq"
reset; stage_clean plain; h=$(head_of)
PATH="$tmp/nogitleaks:/usr/bin:/bin" A commit -q -m "add plain"; rc=$?
check "a missing scanner refuses a commit" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -q "could not run" "$STUB/out"'
reset
PATH="$tmp/nogitleaks:/usr/bin:/bin" A push -q origin feat/x; rc=$?
check "a missing scanner refuses a push" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/x)" ]'

# Pushes.
reset; A push -q origin feat/x; rc=$?
check "a clean push of a feature branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/x)" = "$(head_of)" ]'
main=$(remote_head main)
for spec in feat/x:main HEAD:main refs/heads/feat/x:refs/heads/main +feat/x:main; do
  reset; A push -q origin "$spec"; rc=$?
  check "a push to the default branch is refused: $spec" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "default branch (main)" "$STUB/out"'
done
reset; A push -q --force origin feat/x:main; rc=$?
check "a force push to the default branch is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "default branch (main)" "$STUB/out"'
rewrite=$(git -C "$repo" commit-tree "$(git -C "$repo" hash-object -t tree /dev/null)" -m rewrite)
reset; A push -q --force origin "$rewrite:refs/heads/main"; rc=$?
check "a force push that rewrites the default branch's history is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "default branch (main)" "$STUB/out"'
reset; A push -q origin --delete main; rc=$?
check "a deletion of the default branch is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "never delete the default branch" "$STUB/out"'
reset; A push -q origin :main; rc=$?
check "a deletion of the default branch by refspec is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "never delete the default branch" "$STUB/out"'
# Git sends existing remote branches first, in name order, then new ones.
reset; A push -q origin feat/x:feat/first feat/x:main; rc=$?
check "the default branch first among several destinations refuses the whole push" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && [ -z "$(remote_head feat/first)" ] && grep -q "default branch (main)" "$STUB/out"'
reset; A commit -q --allow-empty -m "for several"; pushed=$(remote_head feat/x)
A push -q origin feat/x feat/x:main; rc=$?
check "the default branch after another destination refuses the whole push" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && [ "$(remote_head feat/x)" = "$pushed" ] && grep -q "default branch (main)" "$STUB/out"'
reset; git -C "$repo" branch -q -f main feat/x; A push -q --all origin; rc=$?
check "push --all with a changed local main is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ]'
git -C "$repo" branch -q -f main "$main"
reset; A push -q "$tmp/origin.git" feat/x:main; rc=$?
check "a push to the default branch by URL is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "default branch (main)" "$STUB/out"'
reset; A push -q -n origin feat/x:main; rc=$?
check "push -n stays a dry run and is still refused for the default branch" '[ "$rc" != 0 ] && grep -q "default branch (main)" "$STUB/out"'
reset; A commit -q --amend -m "first, amended"; A push -q -f origin feat/x; rc=$?
check "a force push to another branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/x)" = "$(head_of)" ]'
reset; A push -q origin feat/x:feat/rw; A push -q -f origin "$rewrite:refs/heads/feat/rw"; rc=$?
check "a force push that rewrites another branch's history goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/rw)" = "$rewrite" ]'
reset; A push -q origin +feat/x:feat/y; rc=$?
check "a +refspec to another branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/y)" = "$(head_of)" ]'
reset; A push -q origin --delete feat/y; rc=$?
check "a deletion of another branch goes through" '[ "$rc" = 0 ] && [ -z "$(remote_head feat/y)" ]'
reset; git -C "$repo" tag v1; A push -q origin --tags; rc=$?
check "--tags alone is not a branch change and goes through" '[ "$rc" = 0 ] && git --git-dir="$tmp/origin.git" rev-parse -q --verify refs/tags/v1 >/dev/null'
reset; touch "$repo/untracked.txt"; printf 'x\n' >>"$repo/clean.txt"; A push -q origin feat/x:feat/dirty; rc=$?
check "a push from a dirty tree goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/dirty)" = "$(head_of)" ]'
# Outgoing commits made without the templates are scanned on push, added lines only.
reset; git -C "$repo" checkout -q -b feat/leak
printf 'token = stubmatchedtext\n' >"$repo/leak.txt"
git -C "$repo" add -A; git -C "$repo" commit -q -m leak
printf 'clean\n' >"$repo/leak.txt"; git -C "$repo" commit -q -am "clean it"
A push -q origin feat/leak; rc=$?
check "an outgoing commit that adds a secret is refused, naming the file, even if a later commit removes it" \
  '[ "$rc" != 0 ] && [ -z "$(remote_head feat/leak)" ] && grep -qF "stub-rule in leak.txt" "$STUB/out" && no_leak'
reset; git -C "$repo" checkout -q feat/x
A push -q origin feat/x:feat/clean; rc=$?
check "outgoing commits already on the remote are not scanned again" '[ "$rc" = 0 ] && { [ ! -e "$STUB/stdin" ] || ! grep -q "token = stubmatchedtext" "$STUB/stdin"; }'
# The remote's own HEAD names the default branch: here trunk, not main.
git init -q --bare "$tmp/trunk.git"
git -C "$repo" push -q "$tmp/trunk.git" feat/x:trunk feat/x:main
git --git-dir="$tmp/trunk.git" symbolic-ref HEAD refs/heads/trunk
git -C "$repo" remote add trunk "$tmp/trunk.git"
reset; A commit -q --allow-empty -m "another"
A push -q trunk feat/x:trunk; rc=$?
check "a push to the remote's HEAD branch (trunk) is refused" '[ "$rc" != 0 ] && grep -q "default branch (trunk)" "$STUB/out"'
A push -q trunk feat/x:main; rc=$?
check "a push to main where the remote's HEAD is trunk goes through" '[ "$rc" = 0 ]'
reset; M push -q origin feat/x:main; rc=$?
check "the maintainer's git runs no template: a push to the default branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head main)" = "$(head_of)" ]'
check "the pushes leave no temporary files" '[ -z "$(ls -A "$TMPDIR")" ]'
git --git-dir="$tmp/origin.git" update-ref refs/heads/main "$main"

# The repository's own hooks. Each records its arguments, its stdin and MENTAT_OWN_HOOK
# in $STUB/<label>.args, .stdin and .env, and exits with $STUB/<label>.exit, else 0.
own() { # own <file> <label>
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "[%%s]" "$a"; done >"$STUB/%s.args"\ncat >"$STUB/%s.stdin"\nprintf "%%s" "${MENTAT_OWN_HOOK:-}" >"$STUB/%s.env"\nexit "$(cat "$STUB/%s.exit" 2>/dev/null || echo 0)"\n' "$2" "$2" "$2" "$2" >"$1"
  chmod +x "$1"
}
own "$repo/.git/hooks/pre-commit" gitdir-commit
own "$repo/.git/hooks/pre-push" gitdir-push

reset; stage_clean chained; h=$(head_of)
A commit -q -m "add chained"; rc=$?
check "after its checks pass, the pre-commit template runs the repository's own hook in .git/hooks" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -e "$STUB/gitdir-commit.args" ] && [ -s "$STUB/calls" ]'
check "the repository's own hook runs with MENTAT_OWN_HOOK set" '[ "$(cat "$STUB/gitdir-commit.env")" = 1 ]'
reset; stage_clean refused; echo 1 >"$STUB/gitdir-commit.exit"; h=$(head_of)
A commit -q -m "add refused"; rc=$?
check "the own pre-commit hook's refusal refuses the commit" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ]'
reset; stage_hit; h=$(head_of)
A commit -q -m "add file"; rc=$?
check "the own pre-commit hook does not run when the template refuses" '[ "$rc" != 0 ] && [ ! -e "$STUB/gitdir-commit.args" ]'
reset; stage_clean ownonly; h=$(head_of)
M commit -q -m "maintainer, own hook only"; rc=$?
check "the maintainer's git runs the repository's own pre-commit hook alone" '[ "$rc" = 0 ] && [ -e "$STUB/gitdir-commit.args" ] && [ ! -e "$STUB/calls" ] && [ -z "$(cat "$STUB/gitdir-commit.env")" ]'

# What the own pre-push hook gets through the template is what git hands it directly.
reset; A commit -q --allow-empty -m "to push"
M push -q --dry-run origin feat/x:feat/through feat/x:feat/through2; rc_direct=$?
direct_args=$(cat "$STUB/gitdir-push.args"); direct_stdin=$(cat "$STUB/gitdir-push.stdin")
reset; A push -q origin feat/x:feat/through feat/x:feat/through2; rc=$?
check "the own pre-push hook gets the same arguments through the template" '[ "$rc_direct" = 0 ] && [ "$rc" = 0 ] && [ -n "$direct_args" ] && [ "$(cat "$STUB/gitdir-push.args")" = "$direct_args" ]'
check "the own pre-push hook gets the same ref lines through the template" '[ -n "$direct_stdin" ] && [ "$(cat "$STUB/gitdir-push.stdin")" = "$direct_stdin" ] && [ "$(printf "%s\n" "$direct_stdin" | wc -l | tr -d " ")" = 2 ]'
check "the template scanned before the own pre-push hook ran" '[ -s "$STUB/calls" ] && [ "$(remote_head feat/through)" = "$(head_of)" ]'
reset; echo 3 >"$STUB/gitdir-push.exit"; A commit -q --allow-empty -m "refused push"
A push -q origin feat/x:feat/refused; rc=$?
check "the own pre-push hook's refusal refuses the push" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/refused)" ]'
reset; A push -q origin feat/x:main; rc=$?
check "the own pre-push hook does not run when the template refuses" '[ "$rc" != 0 ] && [ ! -e "$STUB/gitdir-push.args" ]'
chmod -x "$repo/.git/hooks/pre-push"
reset; A push -q origin feat/x:feat/notexec; rc=$?
check "an own hook that is not executable is skipped, as git skips it" '[ "$rc" = 0 ] && [ ! -e "$STUB/gitdir-push.args" ] && [ "$(remote_head feat/notexec)" = "$(head_of)" ]'
chmod +x "$repo/.git/hooks/pre-push"

# A linked worktree uses the hooks in the main git directory.
git -C "$repo" worktree add -q -b feat/wt "$tmp/wt"
in="$tmp/wt"
reset; stage_clean worktree
A commit -q -m "in a worktree"; rc=$?
check "in a linked worktree, the own hook in the main .git/hooks runs" '[ "$rc" = 0 ] && [ -e "$STUB/gitdir-commit.args" ] && [ -s "$STUB/calls" ]'
reset; A push -q origin feat/wt; rc=$?
check "in a linked worktree, a push runs the own pre-push hook" '[ "$rc" = 0 ] && [ -e "$STUB/gitdir-push.args" ]'
in=$repo

# A repository with its own local core.hooksPath, relative and absolute. Its hooks run,
# and those in .git/hooks do not.
own "$repo/.githooks/pre-commit" local-commit
own "$repo/.githooks/pre-push" local-push
git -C "$repo" add .githooks; git -C "$repo" commit -q -m "own hooks"
n=0
for hp in .githooks "$repo/.githooks"; do
  n=$((n + 1))
  git -C "$repo" config core.hooksPath "$hp"
  reset; stage_clean "local$n"
  A commit -q -m "local hook path"; rc=$?
  check "with core.hooksPath $hp, its own pre-commit hook runs after the template, not .git/hooks'" \
    '[ "$rc" = 0 ] && [ -e "$STUB/local-commit.args" ] && [ ! -e "$STUB/gitdir-commit.args" ] && [ -s "$STUB/calls" ]'
  reset; A push -q origin feat/x:feat/local; rc=$?
  check "with core.hooksPath $hp, its own pre-push hook runs after the template" \
    '[ "$rc" = 0 ] && [ -e "$STUB/local-push.args" ] && [ ! -e "$STUB/gitdir-push.args" ] && [ -s "$STUB/calls" ]'
  reset; A push -q origin feat/x:main; rc=$?
  check "with core.hooksPath $hp, the template still refuses the default branch" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && [ ! -e "$STUB/local-push.args" ]'
  reset; stage_clean "maint$n"; M commit -q -m "maintainer, local hook path"; rc=$?
  check "with core.hooksPath $hp, the maintainer's git runs its own hook alone" '[ "$rc" = 0 ] && [ -e "$STUB/local-commit.args" ] && [ ! -e "$STUB/calls" ]'
done
git -C "$repo" config --unset core.hooksPath

# No recursion: a local core.hooksPath naming the templates, or an own hook that runs
# a template, runs Mentat's checks and ends. A loop is stopped after 20 seconds.
bounded() { # bounded <command...>: runs it in its own process group, killing the group after 20 seconds; prints its exit status
  set -m
  "$@" &
  local pid=$! sleeper rc
  set +m
  (sleep 20; kill -TERM -- "-$pid" 2>/dev/null) >/dev/null 2>&1 &
  sleeper=$!
  wait "$pid"; rc=$?
  kill "$sleeper" 2>/dev/null
  echo "$rc"
}
git -C "$repo" config core.hooksPath "$tpl"
reset; stage_clean loop1; h=$(head_of)
rc=$(bounded A commit -q -m "templates as own hook path")
check "a local core.hooksPath naming the templates commits once, scanned, with no loop" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -s "$STUB/calls" ]'
reset; rc=$(bounded A push -q origin feat/x:feat/loop)
check "a local core.hooksPath naming the templates pushes, with no loop" '[ "$rc" = 0 ] && [ "$(remote_head feat/loop)" = "$(head_of)" ]'
reset; rc=$(bounded A push -q origin feat/x:main)
check "a local core.hooksPath naming the templates still refuses the default branch" '[ "$rc" != 0 ] && [ "$rc" != 143 ] && [ "$(remote_head main)" = "$main" ] && grep -q "default branch (main)" "$STUB/out"'
git -C "$repo" config --unset core.hooksPath
printf '#!/bin/sh\nexec "%s/pre-commit" "$@"\n' "$tpl" >"$repo/.git/hooks/pre-commit"
reset; stage_clean loop2; h=$(head_of)
rc=$(bounded A commit -q -m "own hook runs the template")
check "an own hook that runs the template commits, with no loop" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -s "$STUB/calls" ]'
reset; stage_clean loop3; h=$(head_of)
rc=$(bounded M commit -q -m "maintainer, own hook runs the template")
check "for the maintainer, an own hook that runs the template commits, scanned, with no loop" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -s "$STUB/calls" ]'
reset; stage_hit; h=$(head_of)
rc=$(bounded M commit -q -m "maintainer, own hook runs the template")
check "for the maintainer, an own hook that runs the template still refuses a staged secret" '[ "$rc" != 0 ] && [ "$rc" != 143 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in file two.txt" "$STUB/out"'

# Without own-hook.sh beside them, the templates refuse after their checks.
cp -Rp "$root/git-templates" "$tmp/partial"; rm "$tmp/partial/own-hook.sh"
reset; stage_clean partial; h=$(head_of)
(cd "$repo" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$tmp/partial/hooks" git commit -q -m partial) >"$STUB/out" 2>&1; rc=$?
check "a missing own-hook.sh refuses the commit and says so" '[ "$rc" = 1 ] && [ "$(head_of)" = "$h" ] && grep -q "own-hook.sh could not be loaded" "$STUB/out"'
reset; (cd "$repo" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$tmp/partial/hooks" git push -q origin feat/x:feat/partial) >"$STUB/out" 2>&1; rc=$?
check "a missing own-hook.sh refuses the push and says so" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/partial)" ] && grep -q "own-hook.sh could not be loaded" "$STUB/out"'

# The session-start check of the installed copy.
inst="$tmp/installed"
cp -Rp "$root/git-templates" "$inst"
start() { MENTAT_GIT_TEMPLATES_DIR=$inst "$root/hooks/session-start" >"$STUB/start" 2>&1; }
problem_first() { head -n 1 "$STUB/start" | grep -qF "Mentat PROBLEM: the git hook templates in $inst $1" && tail -n +3 "$STUB/start" | cmp -s - "$root/rules.md"; }
rm -rf "${STUB:?}"/*; start; rc=$?
check "session start: an installed and current copy prints rules.md alone" '[ "$rc" = 0 ] && cmp -s "$STUB/start" "$root/rules.md"'
for f in scan own-hook.sh hooks/pre-commit hooks/pre-push; do
  mv "$inst/$f" "$tmp/away"; start; rc=$?; mv "$tmp/away" "$inst/$f"
  check "session start: a missing $f prints a problem line naming it, then rules.md" '[ "$rc" = 0 ] && problem_first "are missing or not executable ($f)"'
  cp -p "$inst/$f" "$tmp/keep"; printf '# changed\n' >>"$inst/$f"; start; rc=$?; mv "$tmp/keep" "$inst/$f"
  check "session start: a changed $f prints a problem line naming it, then rules.md" '[ "$rc" = 0 ] && problem_first "differ from this copy of Mentat ($f)"'
done
chmod -x "$inst/hooks/pre-push"; start; rc=$?; chmod +x "$inst/hooks/pre-push"
check "session start: a template that is not executable is a problem" '[ "$rc" = 0 ] && problem_first "are missing or not executable (hooks/pre-push)"'
rm -rf "$inst"; start; rc=$?
check "session start: a missing folder names every file" '[ "$rc" = 0 ] && problem_first "are missing or not executable (scan own-hook.sh hooks/pre-commit hooks/pre-push)"'
# A plugin copy without lib/templates.sh still prints the rules, after a problem line.
mkdir -p "$tmp/plugin/hooks"
cp "$root/hooks/session-start" "$tmp/plugin/hooks/"; cp "$root/rules.md" "$tmp/plugin/"
"$tmp/plugin/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: a check that cannot run says so, then prints rules.md" \
  '[ "$rc" = 0 ] && [ "$(head -n 1 "$STUB/start")" = "Mentat PROBLEM: the installed git hook templates could not be checked. Tell the maintainer before anything else, and run mentat check." ] && tail -n +3 "$STUB/start" | cmp -s - "$root/rules.md"'

[ "$failures" -eq 0 ]
