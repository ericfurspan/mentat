#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for git-guard/ (the git hooks, scanner and wrapper) and mentat guard
# install and status. Everything installs into a temp HOME and runs git through the
# installed wrapper, with a stub gitleaks and local bare repositories as remotes.
# Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mentat="$root/bin/mentat"
failures=0
check() { if eval "$2"; then printf 'PASS: git-guard %s\n' "$1"; else printf 'FAIL: git-guard %s\n' "$1"; failures=$((failures + 1)); fi; }

realgit=$(command -v git)
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
tmp="$base/with space"
export STUB="$tmp/stub"
export HOME="$tmp/home"
unset XDG_DATA_HOME XDG_CONFIG_HOME GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS CLAUDECODE
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
export PATH="$HOME/.local/bin:$tmp/bin:$PATH"
guard="$HOME/.local/share/mentat/git-guard"

# Install and status.
out=$("$mentat" guard install 2>&1); rc=$?
check "guard install exits 0" '[ "$rc" = 0 ]'
for f in scan git hooks/pre-commit hooks/prepare-commit-msg hooks/pre-push; do
  check "guard install copies $f into the trusted folder, mode 755, and says so" \
    'cmp -s "$root/git-guard/$f" "$guard/$f" && [ "$(stat -f %Lp "$guard/$f" 2>/dev/null || stat -c %a "$guard/$f")" = 755 ] && grep -qxF "wrote $guard/$f" <<<"$out"'
done
check "guard install copies the wrapper to ~/.local/bin/git, mode 755, and says so" \
  'cmp -s "$root/git-guard/git" "$HOME/.local/bin/git" && [ "$(stat -f %Lp "$HOME/.local/bin/git" 2>/dev/null || stat -c %a "$HOME/.local/bin/git")" = 755 ] && grep -qxF "wrote $HOME/.local/bin/git" <<<"$out"'
check "git on PATH is the wrapper" '[ "$(command -v git)" = "$HOME/.local/bin/git" ]'
out=$("$mentat" guard status 2>&1); rc=$?
want="git guard: installed and current in $guard"$'\n'"git wrapper: installed and current at $HOME/.local/bin/git"
check "guard status: both installed and current, exit 0" '[ "$rc" = 0 ] && [ "$out" = "$want" ]'
printf '# changed\n' >>"$guard/scan"
out=$("$mentat" guard status 2>&1); rc=$?
check "guard status: a changed file is not current, exit 1" '[ "$rc" = 1 ] && grep -qxF "git guard: not current in $guard (differs: scan)" <<<"$out"'
rm "$HOME/.local/bin/git"
out=$("$mentat" guard status 2>&1); rc=$?
check "guard status: a missing wrapper is not installed, exit 1" '[ "$rc" = 1 ] && grep -qxF "git wrapper: not installed at $HOME/.local/bin/git" <<<"$out"'
check "guard status changes nothing" '[ ! -e "$HOME/.local/bin/git" ] && ! cmp -s "$root/git-guard/scan" "$guard/scan"'
out=$("$mentat" guard nonsense 2>&1); rc=$?
check "guard with another argument is a usage error (64)" '[ "$rc" = 64 ]'
# A symlink where the wrapper goes is replaced, never followed.
printf 'keep me\n' >"$tmp/link-target"
ln -s "$tmp/link-target" "$HOME/.local/bin/git"
"$mentat" guard install >/dev/null 2>&1
check "guard install replaces a symlink at the wrapper's place and leaves its target" \
  '[ ! -L "$HOME/.local/bin/git" ] && cmp -s "$root/git-guard/git" "$HOME/.local/bin/git" && [ "$(cat "$tmp/link-target")" = "keep me" ]'
check "guard install makes the changed file current again" '"$mentat" guard status >/dev/null 2>&1'

# Repositories: a bare origin whose HEAD is main, seeded with the real git, and a clone.
"$realgit" init -q --bare "$tmp/origin.git"
# The remote itself would let its HEAD branch be deleted, so only the hook refuses it.
"$realgit" --git-dir="$tmp/origin.git" config receive.denyDeleteCurrent ignore
"$realgit" init -q "$tmp/seed"
printf 'one\ntoken = stubmatchedtext\n' >"$tmp/seed/kept.txt"
"$realgit" -C "$tmp/seed" add -A
"$realgit" -C "$tmp/seed" commit -q -m first
"$realgit" -C "$tmp/seed" push -q "$tmp/origin.git" main
"$realgit" clone -q "$tmp/origin.git" "$tmp/repo"
repo="$tmp/repo"
"$realgit" -C "$repo" checkout -q -b feat/x

# G <args>: git through the wrapper in an agent's shell, from the repository.
G() { (cd "$repo" && CLAUDECODE=1 git "$@") >"$STUB/out" 2>&1; }
remote_head() { "$realgit" --git-dir="$tmp/origin.git" rev-parse -q --verify "refs/heads/$1" 2>/dev/null; }
head_of() { "$realgit" -C "$repo" rev-parse HEAD; }
no_leak() { ! grep -q -e stubmatchedtext -e stubgitleaksoutput "$STUB/out"; }
reset() { rm -f "$STUB"/*; "$realgit" -C "$repo" reset -q --hard; "$realgit" -C "$repo" clean -q -fdx; }
stage_hit() { printf 'a\ntoken = stubmatchedtext\n' >"$repo/file two.txt"; "$realgit" -C "$repo" add -A; }

# Commits.
reset; stage_hit; h=$(head_of)
G commit -q -m "add file"; rc=$?
check "a staged invented secret is refused by the installed pre-commit" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ]'
check "the refusal names the rule and the file" 'grep -qF "stub-rule in file two.txt" "$STUB/out" && grep -q "commit refused" "$STUB/out"'
check "the refusal never shows the match or gitleaks output" 'no_leak'
check "gitleaks runs on stdin with redaction and a JSON report" 'grep -q "^stdin --no-banner --redact --log-level fatal --exit-code 3 --report-format json --report-path " "$STUB/calls"'
check "leaves no temporary files" '[ -z "$(ls -A "$TMPDIR")" ]'
for f in --no-verify -n; do
  reset; stage_hit; h=$(head_of)
  G commit "$f" -q -m "add file"; rc=$?
  check "git commit $f through the wrapper is still scanned and refused" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in file two.txt" "$STUB/out"'
done
reset; stage_hit; h=$(head_of)
G commit -qanm "add file"; rc=$?
check "git commit -anm through the wrapper is still scanned and refused" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ]'
# prepare-commit-msg runs when pre-commit is skipped: real git with the trusted hooks and --no-verify.
reset; stage_hit; h=$(head_of)
(cd "$repo" && "$realgit" -c "core.hooksPath=$guard/hooks" commit --no-verify -q -m "add file") >"$STUB/out" 2>&1; rc=$?
check "with pre-commit skipped, prepare-commit-msg still refuses the staged secret" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in file two.txt" "$STUB/out"'
reset; printf 'clean\n' >"$repo/new.txt"; "$realgit" -C "$repo" add -A; h=$(head_of)
G commit -q -m "token = stubmatchedtext"; rc=$?
check "a secret in the commit message is refused, naming the message" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in the commit message" "$STUB/out" && no_leak'
reset; printf 'clean\n' >"$repo/new.txt"; "$realgit" -C "$repo" add -A; h=$(head_of)
G commit -q -m "add new"; rc=$?
check "a clean commit goes through" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ]'
reset; printf 'more\ntoken = stubmatchedtext\n' >>"$repo/new.txt"; h=$(head_of)
G commit -q -a -m "edit"; rc=$?
check "git commit -a with nothing staged before is scanned for what it commits" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in new.txt" "$STUB/out"'
reset; "$realgit" -C "$repo" rm -q kept.txt; h=$(head_of)
G commit -q -m "remove kept"; rc=$?
check "a removed line with a finding passes" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -s "$STUB/calls" ]'
reset; stage_hit; touch "$STUB/error"; h=$(head_of)
G commit -q -m "add file"; rc=$?
check "a gitleaks error refuses as a failed scan" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -q "could not run" "$STUB/out" && ! grep -q stub-rule "$STUB/out" && no_leak'

# A local core.hooksPath in the repository's config is overridden, and so are -c,
# --config-env and GIT_CONFIG_* entries for it.
mkdir -p "$tmp/local-hooks"
printf '#!/bin/sh\ntouch "%s/local-hook-ran"\nexit 0\n' "$STUB" >"$tmp/local-hooks/pre-commit"
cp "$tmp/local-hooks/pre-commit" "$tmp/local-hooks/prepare-commit-msg"
chmod +x "$tmp/local-hooks/pre-commit" "$tmp/local-hooks/prepare-commit-msg"
"$realgit" -C "$repo" config core.hooksPath "$tmp/local-hooks"
reset; stage_hit; h=$(head_of)
G commit -q -m "add file"; rc=$?
check "a local core.hooksPath is overridden: the trusted hooks refuse, the local ones never run" \
  '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && [ ! -e "$STUB/local-hook-ran" ]'
"$realgit" -C "$repo" config --unset core.hooksPath
reset; stage_hit; h=$(head_of)
G -c "core.hooksPath=$tmp/local-hooks" commit -q -m "add file"; rc=$?
check "a -c core.hooksPath is dropped" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && [ ! -e "$STUB/local-hook-ran" ]'
reset; stage_hit; h=$(head_of)
LOCALHOOKS="$tmp/local-hooks" G --config-env=core.hooksPath=LOCALHOOKS commit -q -m "add file"; rc=$?
check "a --config-env core.hooksPath is dropped" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && [ ! -e "$STUB/local-hook-ran" ]'
reset; printf 'clean\n' >"$repo/other.txt"; "$realgit" -C "$repo" add -A
GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=first GIT_CONFIG_KEY_1=core.hooksPath \
  GIT_CONFIG_VALUE_1="$tmp/local-hooks" GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=third@t G commit -q -m "add other"; rc=$?
check "a GIT_CONFIG_* entry for core.hooksPath in the middle is dropped and the rest still apply" \
  '[ "$rc" = 0 ] && [ ! -e "$STUB/local-hook-ran" ] && [ "$("$realgit" -C "$repo" log -1 --format=%an/%ae)" = "first/third@t" ] && [ -s "$STUB/calls" ]'

# A missing scanner refuses.
mkdir "$tmp/nogitleaks"
ln -s "$realgit" "$tmp/nogitleaks/git"
ln -s "$(command -v jq)" "$tmp/nogitleaks/jq"
reset; printf 'clean\n' >"$repo/plain.txt"; "$realgit" -C "$repo" add -A; h=$(head_of)
(cd "$repo" && CLAUDECODE=1 PATH="$HOME/.local/bin:$tmp/nogitleaks:/usr/bin:/bin" git commit -q -m "add plain") >"$STUB/out" 2>&1; rc=$?
check "a missing scanner refuses a commit" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -q "could not run" "$STUB/out"'
reset
(cd "$repo" && CLAUDECODE=1 PATH="$HOME/.local/bin:$tmp/nogitleaks:/usr/bin:/bin" git push -q origin feat/x) >"$STUB/out" 2>&1; rc=$?
check "a missing scanner refuses a push" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/x)" ]'

# Pushes.
reset; G push -q origin feat/x; rc=$?
check "a clean push of a feature branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/x)" = "$(head_of)" ]'
main=$(remote_head main)
for spec in feat/x:main HEAD:main refs/heads/feat/x:refs/heads/main; do
  reset; G push -q origin "$spec"; rc=$?
  check "a push to the default branch is refused: $spec" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "default branch (main)" "$STUB/out"'
done
reset; G push -q origin --delete main; rc=$?
check "a delete of the default branch is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "never delete the default branch" "$STUB/out"'
reset; G push -q origin :main; rc=$?
check "a delete of the default branch by refspec is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ] && grep -q "never delete the default branch" "$STUB/out"'
reset; G push -q --force origin feat/x:main; rc=$?
check "a force push to the default branch is refused" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ]'
reset; G commit -q --amend -m "add new, amended"; G push -q -f origin feat/x; rc=$?
check "a force push to another branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/x)" = "$(head_of)" ]'
reset; G push -q origin +feat/x:feat/y; rc=$?
check "a +refspec to another branch goes through" '[ "$rc" = 0 ] && [ "$(remote_head feat/y)" = "$(head_of)" ]'
reset; G push -q origin --delete feat/y; rc=$?
check "a delete of another branch goes through" '[ "$rc" = 0 ] && [ -z "$(remote_head feat/y)" ]'
reset; "$realgit" -C "$repo" tag v1; G push -q origin --tags; rc=$?
check "--tags alone is not a branch change and goes through" '[ "$rc" = 0 ] && "$realgit" --git-dir="$tmp/origin.git" rev-parse -q --verify refs/tags/v1 >/dev/null'
reset; G push -q -n origin feat/x:main; rc=$?
check "push -n stays a dry run and is still refused for the default branch" '[ "$rc" != 0 ] && grep -q "default branch (main)" "$STUB/out"'
reset; touch "$repo/untracked.txt"; G push -q origin feat/x:feat/dirty; rc=$?
check "a push from a dirty tree is refused" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/dirty)" ] && grep -q "uncommitted changes" "$STUB/out"'
reset; printf 'x\n' >>"$repo/new.txt"; G push -q origin feat/x:feat/dirty; rc=$?
check "a push with an edited tracked file is refused" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/dirty)" ]'
reset; G push -q --no-verify origin feat/x:main; rc=$?
check "push --no-verify through the wrapper is still refused for the default branch" '[ "$rc" != 0 ] && [ "$(remote_head main)" = "$main" ]'
# Outgoing commits made without the guard are scanned on push, added lines only.
reset; "$realgit" -C "$repo" checkout -q -b feat/leak
printf 'token = stubmatchedtext\n' >"$repo/leak.txt"
"$realgit" -C "$repo" add -A; "$realgit" -C "$repo" commit -q -m leak
printf 'clean\n' >"$repo/leak.txt"; "$realgit" -C "$repo" commit -q -am "clean it"
G push -q origin feat/leak; rc=$?
check "an outgoing commit that adds a secret is refused, naming the file, even if a later commit removes it" \
  '[ "$rc" != 0 ] && [ -z "$(remote_head feat/leak)" ] && grep -qF "stub-rule in leak.txt" "$STUB/out" && no_leak'
reset; "$realgit" -C "$repo" checkout -q feat/x
G push -q origin feat/x:feat/clean; rc=$?
check "outgoing commits already on the remote are not scanned again" '[ "$rc" = 0 ] && { [ ! -e "$STUB/stdin" ] || ! grep -q "token = stubmatchedtext" "$STUB/stdin"; }'
# The remote's own HEAD names the default branch: here trunk, not main.
"$realgit" init -q --bare "$tmp/trunk.git"
"$realgit" -C "$repo" push -q "$tmp/trunk.git" feat/x:trunk feat/x:main
"$realgit" --git-dir="$tmp/trunk.git" symbolic-ref HEAD refs/heads/trunk
"$realgit" -C "$repo" remote add trunk "$tmp/trunk.git"
reset; G commit -q --allow-empty -m "another"
G push -q trunk feat/x:trunk; rc=$?
check "a push to the remote's HEAD branch (trunk) is refused" '[ "$rc" != 0 ] && grep -q "default branch (trunk)" "$STUB/out"'
G push -q trunk feat/x:main; rc=$?
check "a push to main where the remote's HEAD is trunk goes through" '[ "$rc" = 0 ]'

# Without CLAUDECODE the wrapper is transparent.
reset; stage_hit; h=$(head_of)
(cd "$repo" && git commit -q -m "maintainer commit") >"$STUB/out" 2>&1; rc=$?
check "without CLAUDECODE a commit runs no guard hook" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ ! -e "$STUB/calls" ]'
"$realgit" -C "$repo" reset -q --hard "$h"

# The arguments the wrapper hands the real git, read from a recording git after it on PATH.
mkdir "$tmp/rec"
printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "[%%s]" "$a"; done\nprintf "\\n"\nenv | grep -E "^GIT_CONFIG_(COUNT|KEY_|VALUE_)" | sort\n' >"$tmp/rec/git"
chmod +x "$tmp/rec/git"
args() { PATH="$HOME/.local/bin:$tmp/rec:/usr/bin:/bin" "$@" | head -n 1; }
hp="[-c][core.hooksPath=$guard/hooks]"
check "without CLAUDECODE every argument passes untouched" \
  '[ "$(args git -c core.hooksPath=x commit --no-verify -n -m y)" = "[-c][core.hooksPath=x][commit][--no-verify][-n][-m][y]" ]'
while IFS='|' read -r given want; do
  [ -n "$given" ] || continue
  eval "set -- $given"
  got=$(CLAUDECODE=1 args git "$@")
  want=${want//HP/$hp}
  check "with CLAUDECODE: git $given -> $want" '[ "$got" = "$want" ]'
done <<'CASES'
commit -m x|HP[commit][-m][x]
commit --no-verify -m x|HP[commit][-m][x]
commit --no-verif -m x|HP[commit][-m][x]
commit -n -m x|HP[commit][-m][x]
commit -an -m x|HP[commit][-a][-m][x]
commit -nm x|HP[commit][-m][x]
commit -mn|HP[commit][-mn]
commit -m -n|HP[commit][-m][-n]
commit --message -n|HP[commit][--message][-n]
commit -F -n|HP[commit][-F][-n]
commit -- -n|HP[commit][--][-n]
push -n origin x|HP[push][-n][origin][x]
push --no-verify origin x|HP[push][origin][x]
-C dir commit -n|[-C][dir]HP[commit]
-c user.name=a -c core.hooksPath=/x commit|[-c][user.name=a]HP[commit]
-c CORE.HOOKSPATH=/x status|HP[status]
-c core.hooksPath status|HP[status]
--config-env core.hooksPath=V status|HP[status]
--config-env=core.hookspath=V status|HP[status]
--config-env=user.name=V status|[--config-env=user.name=V]HP[status]
--no-pager log -n 1|[--no-pager]HP[log][-n][1]
--version|HP[--version]
CASES
got=$(PATH="$HOME/.local/bin:$tmp/rec:/usr/bin:/bin" CLAUDECODE=1 GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=a.b GIT_CONFIG_VALUE_0=1 \
  GIT_CONFIG_KEY_1=Core.HooksPath GIT_CONFIG_VALUE_1=/x GIT_CONFIG_KEY_2=c.d GIT_CONFIG_VALUE_2=2 git status | tail -n +2 | tr '\n' ' ')
check "GIT_CONFIG_* entries for core.hooksPath go and the rest are renumbered" \
  '[ "$got" = "GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=a.b GIT_CONFIG_KEY_1=c.d GIT_CONFIG_VALUE_0=1 GIT_CONFIG_VALUE_1=2 " ]'
# A second copy of the wrapper on PATH is skipped, not looped through.
mkdir "$tmp/copy"; cp "$root/git-guard/git" "$tmp/copy/git"
# A loop between the copies would never end (each exec keeps the process id), so it is
# stopped after 10 seconds.
PATH="$HOME/.local/bin:$tmp/copy:$tmp/rec:/usr/bin:/bin" CLAUDECODE=1 git status >"$STUB/copy-out" 2>/dev/null &
copy_pid=$!
(sleep 10; kill "$copy_pid" 2>/dev/null) >/dev/null 2>&1 &
sleeper=$!
wait "$copy_pid"
kill "$sleeper" 2>/dev/null
got=$(head -n 1 "$STUB/copy-out")
check "another copy of the wrapper on PATH is skipped" '[ "$got" = "${hp}[status]" ]'

# With the guard folder missing, an agent's commit or push is refused; other commands run.
rm -rf "$guard"
(cd "$repo" && CLAUDECODE=1 git commit -q --allow-empty -m x) >"$STUB/out" 2>&1; rc=$?
check "with the guard missing, an agent's commit exits 1 and says to run mentat guard install" '[ "$rc" = 1 ] && grep -q "run mentat guard install" "$STUB/out"'
(cd "$repo" && CLAUDECODE=1 git push -q origin feat/x) >"$STUB/out" 2>&1; rc=$?
check "with the guard missing, an agent's push exits 1 and says to run mentat guard install" '[ "$rc" = 1 ] && grep -q "run mentat guard install" "$STUB/out"'
(cd "$repo" && CLAUDECODE=1 git status --short) >"$STUB/out" 2>&1; rc=$?
check "with the guard missing, an agent's git status still runs" '[ "$rc" = 0 ]'
(cd "$repo" && git commit -q --allow-empty -m x) >"$STUB/out" 2>&1; rc=$?
check "with the guard missing, the maintainer's commit still runs" '[ "$rc" = 0 ]'
out=$("$mentat" guard status 2>&1); rc=$?
check "guard status: a missing guard folder is not installed, exit 1" '[ "$rc" = 1 ] && grep -q "^git guard: not installed in $guard (missing: scan git hooks/pre-commit hooks/prepare-commit-msg hooks/pre-push)$" <<<"$out"'

[ "$failures" -eq 0 ]
