#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for git-templates/ (the pre-commit and pre-push templates, the
# chain-only templates, the scanner and own-hook.sh) and the session-start check of the
# installed copy. An agent's git names the templates' folder in core.hooksPath through
# GIT_CONFIG_* entries; the maintainer's git has no such entries. A stub gitleaks and
# local bare repositories stand in for the real ones. Prints PASS/FAIL per case; exits
# 1 on any FAIL.
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
lines=$(grep -an stubmatchedtext "$STUB/stdin" | cut -d: -f1)
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
# A merge commit is scanned on what its resolution changed. g: git for setup, with no templates.
g() { git -C "$repo" "$@" >/dev/null 2>&1; }
g checkout -q -b feat/m1 feat/x; printf 'x\n' >"$repo/m.txt"; g add m.txt; g commit -q -m "m base"
g checkout -q -b feat/m2; printf 'two\n' >"$repo/m.txt"; g commit -q -am two
g checkout -q feat/m1; printf 'one\n' >"$repo/m.txt"; g commit -q -am one
g merge feat/m2; printf 'token = stubmatchedtext\n' >"$repo/m.txt"; g add m.txt; g commit -q --no-edit
reset; A push -q origin feat/m1; rc=$?
check "a secret added only while resolving a merge is refused, naming the file" \
  '[ "$rc" != 0 ] && [ -z "$(remote_head feat/m1)" ] && grep -qF "stub-rule in m.txt" "$STUB/out" && no_leak'
g checkout -q -b feat/side feat/x; printf 'token = stubmatchedtext\n' >"$repo/side.txt"; g add side.txt; g commit -q -m side
M push -q origin feat/side
g checkout -q -b feat/m3 feat/x; g commit -q --allow-empty -m m3; g merge --no-ff -m "merge side" feat/side
reset; A push -q origin feat/m3; rc=$?
check "a clean merge of commits already on the remote is not refused for what they added" '[ "$rc" = 0 ] && [ "$(remote_head feat/m3)" = "$(head_of)" ]'
# A merge of three or more parents is scanned on its diff from git's own merge of its parents.
for b in o1 o2; do g checkout -q -b "feat/$b" feat/x; printf '%s\n' "$b" >"$repo/$b.txt"; g add "$b.txt"; g commit -q -m "$b"; done
g checkout -q -b feat/o0 feat/x; g merge --no-ff --no-commit feat/o1 feat/o2
printf 'token = stubmatchedtext\n' >"$repo/oct.txt"; g add oct.txt; g commit -q -m "octopus with a secret"
reset; A push -q origin feat/o0; rc=$?
check "a secret added while completing an octopus merge is refused, naming the file" \
  '[ "$(git -C "$repo" rev-list --parents -n 1 feat/o0 | wc -w)" -eq 4 ] && [ "$rc" != 0 ] && [ -z "$(remote_head feat/o0)" ] && grep -qF "stub-rule in oct.txt" "$STUB/out" && no_leak'
g checkout -q -b feat/o3 feat/x; g merge --no-ff -m "clean octopus" feat/o1 feat/o2
reset; A push -q origin feat/o3; rc=$?
check "a clean octopus merge is pushed" '[ "$rc" = 0 ] && [ "$(remote_head feat/o3)" = "$(head_of)" ] && [ "$(git -C "$repo" rev-list --parents -n 1 HEAD | wc -w)" -eq 4 ]'
g checkout -q -b feat/o4 feat/x; g commit -q --allow-empty -m o4; g merge --no-ff -m "octopus of a pushed side" feat/side feat/o1
reset; A push -q origin feat/o4; rc=$?
check "a clean octopus merge whose second parent is on the remote with a match is pushed" \
  '[ "$rc" = 0 ] && [ "$(remote_head feat/o4)" = "$(head_of)" ] && [ "$(git -C "$repo" rev-list --parents -n 1 HEAD | wc -w)" -eq 4 ]'
# One whose parents conflict, so git cannot merge them, is scanned on its diff from the first parent.
for b in c1 c2; do g checkout -q -b "feat/$b" feat/x; printf '%s\n' "$b" >"$repo/c.txt"; g add c.txt; g commit -q -m "$b"; done
printf 'token = stubmatchedtext\n' >"$repo/oct5.txt"; g add oct5.txt
g checkout -q -b feat/o5 "$(git -C "$repo" commit-tree "$(git -C "$repo" write-tree)" -p feat/x -p feat/c1 -p feat/c2 -m "conflicted octopus")"
reset; A push -q origin feat/o5; rc=$?
check "a secret in an octopus merge whose parents conflict is refused, naming the file" \
  '[ "$(git -C "$repo" rev-list --parents -n 1 feat/o5 | wc -w)" -eq 4 ] && [ "$rc" != 0 ] && [ -z "$(remote_head feat/o5)" ] && grep -qF "stub-rule in oct5.txt" "$STUB/out"'
g checkout -q feat/x
# Files git treats as binary (-diff, binary) are scanned as text; real binary content passes.
g checkout -q -b feat/bin feat/x
printf '*.lock -diff\n*.dat binary\n' >"$repo/.gitattributes"; g add .gitattributes; g commit -q -m attributes
for f in a.lock b.dat; do
  reset; printf 'one\ntoken = stubmatchedtext\n' >"$repo/$f"; git -C "$repo" add "$f"; h=$(head_of)
  A commit -q -m "add $f"; rc=$?
  check "a staged secret in $f, which .gitattributes marks as binary, is refused" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && grep -qF "stub-rule in $f" "$STUB/out"'
done
reset; head -c 4096 /dev/urandom >"$repo/random.bin"; printf 'x\0y\n' >>"$repo/random.bin"; git -C "$repo" add random.bin; h=$(head_of)
A commit -q -m "add random.bin"; rc=$?
check "a binary file with no secret commits" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ]'
reset; printf 'token = stubmatchedtext\n' >"$repo/c.lock"; g add c.lock; g commit -q -m "c.lock"
A push -q origin feat/bin; rc=$?
check "an outgoing secret in a file .gitattributes marks as binary is refused" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/bin)" ] && grep -qF "stub-rule in c.lock" "$STUB/out"'
g reset -q --hard HEAD~1
reset; A push -q origin feat/bin; rc=$?
check "outgoing binary content with no secret is pushed" '[ "$rc" = 0 ] && [ "$(remote_head feat/bin)" = "$(head_of)" ]'
g checkout -q feat/x
# A root commit is scanned even with log.showRoot off.
g config log.showRoot false
g checkout -q --orphan feat/root; g rm -rq --cached .; g clean -fdxq
printf 'token = stubmatchedtext\n' >"$repo/root.txt"; g add root.txt; g commit -q -m root
reset; A push -q origin feat/root; rc=$?
check "with log.showRoot off, a secret in a root commit is refused" '[ "$rc" != 0 ] && [ -z "$(remote_head feat/root)" ] && grep -qF "stub-rule in root.txt" "$STUB/out"'
g config --unset log.showRoot
g checkout -q -f feat/x
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
# A remote whose pushurl names another repository: the default branch of the repository
# pushed to counts, here trunk, while the fetch repository's is main.
git init -q --bare "$tmp/fetch.git"; git init -q --bare "$tmp/pushto.git"
git -C "$repo" push -q "$tmp/fetch.git" feat/x:main feat/x:trunk
git -C "$repo" push -q "$tmp/pushto.git" feat/x:main feat/x:trunk
git --git-dir="$tmp/pushto.git" symbolic-ref HEAD refs/heads/trunk
git -C "$repo" remote add split "$tmp/fetch.git"; git -C "$repo" remote set-url --push split "$tmp/pushto.git"
pushed_trunk=$(git --git-dir="$tmp/pushto.git" rev-parse refs/heads/trunk)
reset; A commit -q --allow-empty -m "split"
A push -q split feat/x:trunk; rc=$?
check "with a pushurl, the default branch of the repository pushed to is refused" '[ "$rc" != 0 ] && grep -q "default branch (trunk)" "$STUB/out" && [ "$(git --git-dir="$tmp/pushto.git" rev-parse refs/heads/trunk)" = "$pushed_trunk" ]'
A push -q split feat/x:main; rc=$?
check "with a pushurl, the fetch repository's default branch is not the one refused" '[ "$rc" = 0 ] && [ "$(git --git-dir="$tmp/pushto.git" rev-parse refs/heads/main)" = "$(head_of)" ]'
# A commit the fetch repository has, and so a remote-tracking ref here, but the one
# pushed to lacks, is scanned.
g checkout -q -b feat/fetched feat/x; printf 'token = stubmatchedtext\n' >"$repo/fetched.txt"; g add fetched.txt; g commit -q -m fetched
g push -q "$tmp/fetch.git" feat/fetched; g fetch -q split; g checkout -q feat/x
reset; A push -q split feat/fetched:refs/heads/feat/fetched-new; rc=$?
check "with a pushurl, a secret the fetch repository has but the one pushed to lacks is refused" \
  '[ "$rc" != 0 ] && ! git --git-dir="$tmp/pushto.git" rev-parse -q --verify refs/heads/feat/fetched-new >/dev/null && grep -qF "stub-rule in fetched.txt" "$STUB/out"'
# When the refs of the repository pushed to cannot be read, commits it may have are
# scanned too: here kept.txt's secret, which origin has.
reset; (cd "$repo" && printf 'refs/heads/feat/x %s refs/heads/feat/unread %040d\n' "$(head_of)" 0 | "$tpl/pre-push" origin "$tmp/unreadable.git") >"$STUB/out" 2>&1; rc=$?
check "when the refs of the repository pushed to cannot be read, every commit reachable from the push is scanned" '[ "$rc" != 0 ] && grep -qF "stub-rule in kept.txt" "$STUB/out"'
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
check "the repository's own hook runs with MENTAT_OWN_HOOK naming that hook and repository" '[ "$(cat "$STUB/gitdir-commit.env")" = "pre-commit $(cd "$repo/.git" && pwd -P)" ]'
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

# The chain-only templates: one for every other client-side hook git runs from
# core.hooksPath, each running only the repository's own hook of its name.
chain="applypatch-msg pre-applypatch post-applypatch pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge post-rewrite pre-auto-gc sendemail-validate push-to-checkout"
# shellcheck disable=SC2086 # $chain is a list of words.
want_hooks=$(printf '%s\n' pre-commit pre-push $chain | sort | tr '\n' ' ')
check "the templates' hooks folder holds pre-commit, pre-push and the chain-only templates, nothing else" '[ "$(ls "$tpl" | sort | tr "\n" " ")" = "$want_hooks" ]'
printf 'line one\nline two\n' >"$tmp/chain-stdin"
for name in $chain; do
  own "$repo/.git/hooks/$name" "chain-$name"
  rm -rf "${STUB:?}"/*; echo 5 >"$STUB/chain-$name.exit"
  (cd "$repo" && "$tpl/$name" "first arg" second <"$tmp/chain-stdin") >"$STUB/out" 2>&1; rc=$?
  check "the $name template runs the repository's own hook with its arguments, stdin and exit status" \
    '[ "$rc" = 5 ] && [ "$(cat "$STUB/chain-$name.args")" = "[first arg][second]" ] && cmp -s "$STUB/chain-$name.stdin" "$tmp/chain-stdin"'
  rm "$repo/.git/hooks/$name"
done
own "$repo/.git/hooks/commit-msg" own-commit-msg
own "$repo/.git/hooks/post-checkout" own-post-checkout
reset; stage_clean msg; echo 1 >"$STUB/own-commit-msg.exit"; h=$(head_of)
A commit -q -m "refused by commit-msg"; rc=$?
check "a repository commit-msg hook that refuses still refuses an agent's commit" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ] && [ "$(cat "$STUB/own-commit-msg.args")" = "[.git/COMMIT_EDITMSG]" ] && [ -s "$STUB/calls" ]'
reset; stage_clean msg2; h=$(head_of)
A commit -q -m "passed by commit-msg"; rc=$?
check "a repository commit-msg hook that passes lets an agent's commit through" '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -e "$STUB/own-commit-msg.args" ]'
reset; A checkout -q -b feat/pc; rc=$?
check "a repository post-checkout hook still runs for an agent's checkout, with git's arguments" \
  '[ "$rc" = 0 ] && grep -qE "^\[[0-9a-f]{40}\]\[[0-9a-f]{40}\]\[1\]$" "$STUB/own-post-checkout.args"'
git -C "$repo" checkout -q feat/x
rm "$repo/.git/hooks/commit-msg" "$repo/.git/hooks/post-checkout"

# One hook may run another: a repository pre-merge-commit that runs git hook run
# pre-commit still gets the repository's own pre-commit, refusal included.
printf '#!/bin/sh\nexec git hook run pre-commit\n' >"$repo/.git/hooks/pre-merge-commit"
chmod +x "$repo/.git/hooks/pre-merge-commit"
g checkout -q -b feat/d2 feat/x; g commit -q --allow-empty -m d2
g checkout -q -b feat/d1 feat/x; g commit -q --allow-empty -m d1
reset; h=$(head_of)
A merge --no-ff -q -m "merge d2" feat/d2; rc=$?
check "a repository hook that runs another hook still gets the repository's own hook of that name" \
  '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ -e "$STUB/gitdir-commit.args" ] && grep -q "^pre-merge-commit " "$STUB/gitdir-commit.env" && grep -q "^pre-commit " "$STUB/gitdir-commit.env"'
g reset -q --hard "$h"
reset; echo 1 >"$STUB/gitdir-commit.exit"
A merge --no-ff -q -m "merge d2" feat/d2; rc=$?
check "that delegated own hook's refusal refuses the merge" '[ "$rc" != 0 ] && [ "$(head_of)" = "$h" ]'
g merge --abort; g checkout -q feat/x
rm "$repo/.git/hooks/pre-merge-commit" "$STUB/gitdir-commit.exit"

# Hooks that run git: a repository pre-commit that runs git checkout -- . and a
# post-commit that pushes a branch still get the repository's own post-checkout and pre-push.
cp -p "$repo/.git/hooks/pre-commit" "$tmp/pre-commit.keep"
printf '#!/bin/sh\ngit checkout -- . || exit 1\nexec "%s" "$@"\n' "$tmp/pre-commit.keep" >"$repo/.git/hooks/pre-commit"
printf '#!/bin/sh\ngit push -q origin HEAD:refs/heads/feat/from-post-commit\n' >"$repo/.git/hooks/post-commit"
chmod +x "$repo/.git/hooks/pre-commit" "$repo/.git/hooks/post-commit"
own "$repo/.git/hooks/post-checkout" nested-post-checkout
reset; stage_clean nested; h=$(head_of)
A commit -q -m "hooks that run git"; rc=$?
check "a repository pre-commit that runs git checkout still gets the repository's own post-checkout" \
  '[ "$rc" = 0 ] && [ "$(head_of)" != "$h" ] && [ "$(cat "$STUB/nested-post-checkout.args" 2>/dev/null)" = "[$h][$h][0]" ]'
check "a repository post-commit that pushes still gets the template's checks and the repository's own pre-push" \
  '[ "$(remote_head feat/from-post-commit)" = "$(head_of)" ] && [ -e "$STUB/gitdir-push.args" ] && [ -s "$STUB/calls" ]'
mv "$tmp/pre-commit.keep" "$repo/.git/hooks/pre-commit"; rm "$repo/.git/hooks/post-commit" "$repo/.git/hooks/post-checkout"

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
# A local core.hooksPath set through an included file counts too.
printf '[core]\n\thooksPath = .githooks\n' >"$repo/.git/hooks.cfg"
git -C "$repo" config include.path hooks.cfg
reset; stage_clean included
A commit -q -m "included hook path"; rc=$?
check "a core.hooksPath from an included config file names the repository's own hooks" \
  '[ "$rc" = 0 ] && [ -e "$STUB/local-commit.args" ] && [ ! -e "$STUB/gitdir-commit.args" ]'
git -C "$repo" config --unset include.path
# With extensions.worktreeConfig on, a linked worktree's core.hooksPath in its
# config.worktree names its own hooks.
git -C "$repo" config extensions.worktreeConfig true
git -C "$repo" worktree add -q "$tmp/wt" -b feat/wt feat/x
git -C "$tmp/wt" config --worktree core.hooksPath "$tmp/wt-hooks"
own "$tmp/wt-hooks/pre-commit" wt-commit
reset; printf 'wt\n' >"$tmp/wt/wt.txt"; git -C "$tmp/wt" add wt.txt
in=$tmp/wt; A commit -q -m "worktree hook path"; rc=$?; in=$repo
check "a linked worktree's core.hooksPath in config.worktree names its own hooks" \
  '[ "$rc" = 0 ] && [ -e "$STUB/wt-commit.args" ] && [ ! -e "$STUB/gitdir-commit.args" ]'
git -C "$repo" worktree remove --force "$tmp/wt"; git -C "$repo" config --unset extensions.worktreeConfig

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

# git init runs under the templates: plain, bare and in place.
A init -q "$tmp/new-plain"; rc=$?
check "git init of a new repository works under the templates" '[ "$rc" = 0 ] && git -C "$tmp/new-plain" rev-parse --git-dir >/dev/null 2>&1'
A init -q --bare "$tmp/new-bare.git"; rc=$?
check "git init --bare works under the templates" '[ "$rc" = 0 ] && [ "$(git --git-dir="$tmp/new-bare.git" rev-parse --is-bare-repository)" = true ]'
mkdir "$tmp/new-inplace"
(cd "$tmp/new-inplace" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$tpl" git init -q) >"$STUB/out" 2>&1; rc=$?
check "git init in place works under the templates" '[ "$rc" = 0 ] && [ -d "$tmp/new-inplace/.git" ]'
# Where git cannot tell the repository yet, as while git init creates it, GIT_DIR names it.
mkdir -p "$tmp/half/hooks" "$tmp/elsewhere"
own "$tmp/half/hooks/post-commit" half
rm -rf "${STUB:?}"/*; (cd "$tmp/elsewhere" && GIT_DIR="$tmp/half" "$tpl/post-commit" one) </dev/null >"$STUB/out" 2>&1; rc=$?
check "with no repository git can read, a template runs the own hook in GIT_DIR/hooks" '[ "$rc" = 0 ] && [ "$(cat "$STUB/half.args" 2>/dev/null)" = "[one]" ]'

# The session-start check of the installed copy.
inst="$tmp/installed"
cp -Rp "$root/git-templates" "$inst"
start() { MENTAT_GIT_TEMPLATES_DIR=$inst "$root/hooks/session-start" >"$STUB/start" 2>&1; }
# problem_is <counts>: the output is one problem line of counts, with no folder or file
# name, a blank line, then rules.md.
problem_is() {
  [ "$rc" = 0 ] && [ "$(head -n 1 "$STUB/start")" = "Mentat PROBLEM: the git hook templates agents' git uses have problems ($1), so agents' commits and pushes may be refused or unchecked. Tell the maintainer before anything else, and run mentat check." ] &&
    tail -n +3 "$STUB/start" | cmp -s - "$root/rules.md"
}
rm -rf "${STUB:?}"/*; start; rc=$?
check "session start: an installed and current copy prints rules.md alone" '[ "$rc" = 0 ] && cmp -s "$STUB/start" "$root/rules.md"'
alone() { [ "$rc" = 0 ] && cmp -s "$STUB/start" "$root/rules.md"; }
"$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: with no templates in use, it prints rules.md alone" 'alone'
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=x "$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: GIT_CONFIG_* entries that name no core.hooksPath are not a use of the templates" 'alone'
PATH="$tmp/nogitleaks:/usr/bin:/bin" "$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: with no templates in use, a missing gitleaks prints nothing extra" 'alone'
GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$tmp/nowhere/hooks" GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=x \
  GIT_CONFIG_KEY_2=Core.HooksPath GIT_CONFIG_VALUE_2="$inst/hooks/" "$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: the last core.hooksPath entry in GIT_CONFIG_* names a current copy, so rules.md prints alone" 'alone'
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$tmp/nowhere/hooks" "$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: a core.hooksPath entry naming a missing folder prints a problem line, then rules.md" 'problem_is "the folder is missing"'
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$inst/hooks" PATH="$tmp/nogitleaks:/usr/bin:/bin" "$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: with the templates in use, a missing gitleaks prints a problem line, then rules.md" 'problem_is "not installed: gitleaks"'
for f in scan own-hook.sh hooks/pre-commit hooks/pre-push hooks/commit-msg hooks/post-checkout; do
  mv "$inst/$f" "$tmp/away"; start; rc=$?; mv "$tmp/away" "$inst/$f"
  check "session start: a missing $f prints a problem line counting it, then rules.md" 'problem_is "1 missing or not executable"'
  cp -p "$inst/$f" "$tmp/keep"; printf '# changed\n' >>"$inst/$f"; start; rc=$?; mv "$tmp/keep" "$inst/$f"
  check "session start: a changed $f prints a problem line counting it, then rules.md" 'problem_is "1 changed"'
done
chmod -x "$inst/hooks/pre-push"; start; rc=$?; chmod +x "$inst/hooks/pre-push"
check "session start: a template that is not executable is a problem" 'problem_is "1 missing or not executable"'
mv "$inst/scan" "$tmp/away"; rm "$inst/hooks/commit-msg"; printf '# changed\n' >>"$inst/hooks/pre-push"
MENTAT_GIT_TEMPLATES_DIR=$inst PATH="$tmp/nogitleaks:/usr/bin:/bin" "$root/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: several problems print one line of counts" 'problem_is "2 missing or not executable, 1 changed, not installed: gitleaks"'
mv "$tmp/away" "$inst/scan"
rm -rf "$inst"; start; rc=$?
check "session start: a missing folder is a problem" 'problem_is "the folder is missing"'
# A plugin copy without lib/templates.sh still prints the rules, after a problem line.
mkdir -p "$tmp/plugin/hooks"
cp "$root/hooks/session-start" "$tmp/plugin/hooks/"; cp "$root/rules.md" "$tmp/plugin/"
"$tmp/plugin/hooks/session-start" >"$STUB/start" 2>&1; rc=$?
check "session start: a check that cannot run says so, then prints rules.md" \
  '[ "$rc" = 0 ] && [ "$(head -n 1 "$STUB/start")" = "Mentat PROBLEM: the installed git hook templates could not be checked. Tell the maintainer before anything else, and run mentat check." ] && tail -n +3 "$STUB/start" | cmp -s - "$root/rules.md"'

[ "$failures" -eq 0 ]
