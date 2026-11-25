#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat worktree snapshot` and `mentat worktree verify` (the
# main-checkout check of skills/build/helpers.md), run through bin/mentat on real git
# checkouts at paths with spaces. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home"
failures=0
check() { if eval "$2"; then printf 'PASS: worktree check %s\n' "$1"; else printf 'FAIL: worktree check %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$root/home"
export GIT_CEILING_DIRECTORIES="$root"

# An origin, a seed clone that pushes to it, the main checkout W (a clone) and a linked
# worktree of W under its .claude/worktrees, as the host makes them.
O="$root/the origin.git" SEED="$root/seed" W="$root/main checkout" L="$root/main checkout/.claude/worktrees/a helper"
git init -q --bare -b main "$O"
git init -q -b main "$SEED"
git -C "$SEED" remote add origin "$O"
advance() { git -C "$SEED" commit -q --allow-empty -m "$1" && git -C "$SEED" push -q origin HEAD:main; }
advance one && advance two || exit 1
git clone -q "$O" "$W" || exit 1
git -C "$W" worktree add -q -b helper "$L" || exit 1

# snapshot [<checkout>] from directory $1: the line on stdout.
snap() { local d=$1; shift; (cd "$d" && "$mentat" worktree snapshot "$@" 2>"$root/err"); }
# verify <line> [<checkout>] from directory $1: the exit status; stdout in $root/out.
verify() { local d=$1; shift; (cd "$d" && "$mentat" worktree verify "$@" >"$root/out" 2>"$root/err"); echo $?; }
said() { grep -qF -- "$1" "$root/out"; }
head_of() { git -C "${1:-$W}" rev-parse HEAD; }
form='^[^ ]+ [0-9a-f]{40} (clean|dirty) [0-9a-f]{64}$'

# snapshot: four tokens, the main checkout by default, from a linked worktree too.
line=$(snap "$W"); rc=$?
check "snapshot of a clean main checkout: exit 0, four tokens, branch, HEAD, clean" '[ "$rc" = 0 ] && printf "%s" "$line" | grep -Eq "$form" &&
  [ "$(printf "%s" "$line" | cut -d " " -f 1-3)" = "main $(head_of) clean" ]'
check "the linked worktree under .claude/worktrees does not count as a change" '[ "$(printf "%s" "$line" | cut -d " " -f 3)" = clean ]'
check "snapshot of a clean checkout: the hash is that of empty output" '[ "${line##* }" = "$(printf "" | shasum -a 256 | cut -d " " -f 1)" ]'
line_l=$(snap "$L"); rc=$?
check "snapshot from a linked worktree, no checkout named: the main checkout" '[ "$rc" = 0 ] && [ "$line_l" = "$line" ]'
line_h=$(snap "$W" "$L"); rc=$?
check "snapshot of a named checkout: that one" '[ "$rc" = 0 ] && [ "$(printf "%s" "$line_h" | cut -d " " -f 1)" = helper ]'

# verify: unchanged.
rc=$(verify "$L" "$line")
check "verify, nothing changed: exit 0, unchanged, no weaker-check note" '[ "$rc" = 0 ] && said "unchanged" && ! said "not clean"'
rc=$(verify "$root" "$line" "$W")
check "verify of a named checkout from outside any repository: exit 0" '[ "$rc" = 0 ]'

# Status changed: exit 1 naming it and listing the current status paths.
printf 'x\n' >"$W/new file.txt"
rc=$(verify "$W" "$line")
check "verify, a new file: exit 1, names the status and lists its path" '[ "$rc" = 1 ] && said "status" && said "new file.txt"'
rm "$W/new file.txt"
printf 'x\n' >"$L/inside helper.txt"
rc=$(verify "$W" "$line")
check "verify, a change only under .claude/worktrees: exit 0" '[ "$rc" = 0 ]'
rm "$L/inside helper.txt"

# Branch changed.
git -C "$W" checkout -q -b other || exit 1
rc=$(verify "$W" "$line")
check "verify, another branch checked out: exit 1, names the branch change" '[ "$rc" = 1 ] && said "branch" && said "other"'
git -C "$W" checkout -q main || exit 1

# HEAD moved only forward along origin/main as last fetched: unchanged.
advance three && git -C "$W" fetch -q origin || exit 1
line=$(snap "$W")
git -C "$W" merge -q --ff-only origin/main || exit 1
rc=$(verify "$W" "$line")
check "verify, HEAD moved forward to origin/main as fetched: exit 0" '[ "$rc" = 0 ] && said "unchanged"'

# HEAD moved forward to a commit the remote has but origin/main as last fetched lacks:
# verify fetches nothing, so it is a change.
line=$(snap "$W")
advance four || exit 1
git -C "$W" fetch -q "$O" main && git -C "$W" merge -q --ff-only FETCH_HEAD || exit 1
tracked=$(git -C "$W" rev-parse refs/remotes/origin/main)
rc=$(verify "$W" "$line")
check "verify, HEAD moved past origin/main as last fetched: exit 1 naming HEAD, nothing fetched" '[ "$rc" = 1 ] && said "HEAD" && [ "$(git -C "$W" rev-parse refs/remotes/origin/main)" = "$tracked" ]'
git -C "$W" fetch -q origin || exit 1

# HEAD moved forward by a local commit not on origin/main.
line=$(snap "$W")
git -C "$W" commit -q --allow-empty -m local || exit 1
rc=$(verify "$W" "$line")
check "verify, a local commit not on origin/main: exit 1 naming HEAD" '[ "$rc" = 1 ] && said "HEAD"'

# HEAD moved back.
line=$(snap "$W")
git -C "$W" reset -q --hard HEAD~1 || exit 1
rc=$(verify "$W" "$line")
check "verify, HEAD moved back: exit 1 naming HEAD" '[ "$rc" = 1 ] && said "HEAD"'

# Detached at the snapshot: only the same HEAD passes, even a move forward along origin/main.
git -C "$W" checkout -q --detach HEAD~1 || exit 1
line=$(snap "$W")
check "snapshot, detached: the first token is detached" '[ "$(printf "%s" "$line" | cut -d " " -f 1)" = detached ]'
rc=$(verify "$W" "$line")
check "verify, detached and unmoved: exit 0" '[ "$rc" = 0 ]'
git -C "$W" checkout -q --detach origin/main || exit 1
rc=$(verify "$W" "$line")
check "verify, detached and moved forward along origin/main: exit 1 naming HEAD" '[ "$rc" = 1 ] && said "HEAD"'
git -C "$W" checkout -q main || exit 1
rc=$(verify "$W" "$line")
check "verify, detached at the snapshot, on a branch now: exit 1 naming the branch" '[ "$rc" = 1 ] && said "branch"'

# The snapshot's checkout was not clean: said, on an unchanged result and on a change.
printf 'x\n' >"$W/left over.txt"
line=$(snap "$W")
check "snapshot, an untracked file: dirty" '[ "$(printf "%s" "$line" | cut -d " " -f 3)" = dirty ]'
check "snapshot, dirty: the hash is that of git status --porcelain's exact output" '[ "${line##* }" = "$(git -C "$W" status --porcelain -- ":(exclude).claude/worktrees" | shasum -a 256 | cut -d " " -f 1)" ]'
rc=$(verify "$W" "$line")
check "verify, dirty at the snapshot and unchanged: exit 0, says it was not clean" '[ "$rc" = 0 ] && said "not clean"'
printf 'y\n' >>"$W/left over.txt"
rc=$(verify "$W" "$line")
check "verify, an untracked file edited: same status line, exit 0" '[ "$rc" = 0 ]'
rm "$W/left over.txt"
rc=$(verify "$W" "$line")
check "verify, dirty at the snapshot, clean now: exit 1, says it was not clean" '[ "$rc" = 1 ] && said "status" && said "not clean"'

# A line it cannot parse, or a checkout it cannot read: exit 2.
line=$(snap "$W")
h=$(head_of)
for bad in "" "main" "main $h clean" "$line extra" "main  ${line#main }" " $line" "main ${h%?} clean ${line##* }" "main $h tidy ${line##* }" "main $h clean xyz" "bad..name ${line#main }" "$line"$'\n'"$line"; do
  rc=$(verify "$W" "$bad")
  check "verify, unparsable line [$bad]: exit 2" '[ "$rc" = 2 ] && [ ! -s "$root/out" ] && [ -s "$root/err" ]'
done
mkdir "$root/plain dir"
rc=$(verify "$root" "$line" "$root/plain dir")
check "verify, a folder that is no git checkout: exit 2" '[ "$rc" = 2 ]'
rc=$(verify "$root" "$line" "$root/missing")
check "verify, a missing checkout: exit 2" '[ "$rc" = 2 ]'
rc=$( (cd "$root" && "$mentat" worktree verify "$line" >"$root/out" 2>"$root/err"); echo $?)
check "verify outside any repository, no checkout named: exit 2" '[ "$rc" = 2 ]'
rc=$( (cd "$root" && "$mentat" worktree snapshot "$root/plain dir" >"$root/out" 2>"$root/err"); echo $?)
check "snapshot of a folder that is no git checkout: exit 2, nothing on stdout" '[ "$rc" = 2 ] && [ ! -s "$root/out" ]'

# Usage.
rc=$( (cd "$W" && "$mentat" worktree verify >"$root/out" 2>"$root/err"); echo $?)
check "verify with no line: usage error (exit 64)" '[ "$rc" = 64 ] && grep -qF "usage: mentat worktree verify <line> [<checkout>]" "$root/err"'
rc=$( (cd "$W" && "$mentat" worktree snapshot a b >"$root/out" 2>"$root/err"); echo $?)
check "snapshot with two checkouts: usage error (exit 64)" '[ "$rc" = 64 ] && grep -qF "usage: mentat worktree snapshot [<checkout>]" "$root/err"'
rc=$("$mentat" nonsense >/dev/null 2>"$root/err"; echo $?)
check "mentat's usage names snapshot and verify" '[ "$rc" = 64 ] && grep -qF "| mentat worktree snapshot [<checkout>] | mentat worktree verify <line> [<checkout>]" "$root/err"'

[ "$failures" -eq 0 ]
