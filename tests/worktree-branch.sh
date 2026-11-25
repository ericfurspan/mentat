#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat worktree branch`, run through bin/mentat on real git
# origins at paths with spaces. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home"
failures=0
check() { if eval "$2"; then printf 'PASS: worktree branch %s\n' "$1"; else printf 'FAIL: worktree branch %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$root/home"
export GIT_CEILING_DIRECTORIES="$root"

# An origin whose main a seed clone pushes to, and a clone of it, all at paths with spaces.
O="$root/the origin.git" SEED="$root/seed" W="$root/work tree"
git init -q --bare -b main "$O"
git init -q -b main "$SEED"
git -C "$SEED" remote add origin "$O"
advance() { git -C "$SEED" commit -q --allow-empty -m "$1" && git -C "$SEED" push -q origin "HEAD:${2:-main}"; }
advance one || exit 1
git clone -q "$O" "$W" || exit 1

run() { (cd "$W" && "$mentat" worktree branch "$@" >"$root/out" 2>"$root/err"); echo $?; }
has_branch() { git -C "$W" show-ref --verify --quiet "refs/heads/$1"; }
fetch_mark() { cksum "$W/.git/FETCH_HEAD" 2>/dev/null || echo none; }

# Created: from origin/main as fetched now (the remote moved after the clone), with no upstream.
advance two || exit 1
rc=$(run "feat/new-one")
check "created: exit 0, at origin's main as just fetched, with no upstream" '[ "$rc" = 0 ] && has_branch "feat/new-one" &&
  [ "$(git -C "$W" rev-parse "refs/heads/feat/new-one")" = "$(git -C "$SEED" rev-parse HEAD)" ] &&
  ! git -C "$W" config --get "branch.feat/new-one.merge" >/dev/null'
check "created: says so on stdout, nothing on stderr" 'grep -qF "feat/new-one" "$root/out" && [ ! -s "$root/err" ]'
check "the checkout stays on main" '[ "$(git -C "$W" branch --show-current)" = main ]'

# Exists: exit 1 before any network read. With origin unreachable, a fetch or ls-remote
# would give exit 2; the branch stays where it was and nothing was fetched.
git -C "$W" branch taken HEAD || exit 1
was=$(git -C "$W" rev-parse refs/heads/taken) mark=$(fetch_mark)
git -C "$W" remote set-url origin "$root/gone.git"
rc=$(run taken)
git -C "$W" remote set-url origin "$O"
check "branch exists: exit 1, before any fetch (origin unreachable), branch unmoved" '[ "$rc" = 1 ] && [ "$(git -C "$W" rev-parse refs/heads/taken)" = "$was" ] && [ "$(fetch_mark)" = "$mark" ] && grep -qF "taken" "$root/err"'
advance three || exit 1
before=$(git -C "$W" rev-parse refs/remotes/origin/main)
rc=$(run taken)
check "branch exists, origin moved: exit 1, origin/main not fetched" '[ "$rc" = 1 ] && [ "$(git -C "$W" rev-parse refs/remotes/origin/main)" = "$before" ]'

# The fetch fails: exit 2, no branch.
git -C "$W" remote set-url origin "$root/gone.git"
rc=$(run fetchless)
git -C "$W" remote set-url origin "$O"
check "fetch fails: exit 2, no branch, the fetch named" '[ "$rc" = 2 ] && ! has_branch fetchless && grep -qi "fetch" "$root/err"'

# The default branch is the one origin's HEAD names (trunk), not the clone's origin/HEAD.
advance "on trunk" trunk || exit 1
git -C "$O" symbolic-ref HEAD refs/heads/trunk
rc=$(run from-trunk)
check "origin's HEAD names trunk: branch made from origin/trunk (exit 0)" '[ "$rc" = 0 ] && [ "$(git -C "$W" rev-parse refs/heads/from-trunk)" = "$(git -C "$O" rev-parse trunk)" ]'

# No default branch: origin's HEAD names none and the clone has no origin/HEAD. Newer git's
# fetch would make origin/HEAD again from the commit the remote's HEAD is at; this clone
# is told not to, so the lookup finds nothing.
git -C "$O" update-ref --no-deref HEAD "$(git -C "$O" rev-parse main)" && git -C "$W" remote set-head origin -d || exit 1
git -C "$W" config remote.origin.followRemoteHEAD never || exit 1
rc=$(run headless)
check "no default branch found: exit 2, no branch, said so" '[ "$rc" = 2 ] && ! has_branch headless && grep -qF "default branch" "$root/err"'
git -C "$O" symbolic-ref HEAD refs/heads/main

# Outside a git repository: exit 2.
mkdir "$root/plain"
rc=$( (cd "$root/plain" && "$mentat" worktree branch x >"$root/out" 2>"$root/err"); echo $?)
check "outside a git repository: exit 2" '[ "$rc" = 2 ]'

# Usage.
for args in "" "a b" "bad..name"; do
  # shellcheck disable=SC2086 # the words are the arguments
  rc=$(run $args)
  check "usage error (exit 64) for: mentat worktree branch $args" '[ "$rc" = 64 ] && grep -qF "usage: mentat worktree branch <name>" "$root/err"'
done
rc=$( (cd "$W" && "$mentat" worktree >/dev/null 2>"$root/err"); echo $?)
check "mentat worktree alone is a usage error (exit 64)" '[ "$rc" = 64 ] && grep -qF "usage: mentat worktree" "$root/err"'
rc=$("$mentat" nonsense >/dev/null 2>"$root/err"; echo $?)
check "mentat's usage names mentat worktree branch" '[ "$rc" = 64 ] && grep -qF "| mentat worktree branch <name>" "$root/err"'

[ "$failures" -eq 0 ]
