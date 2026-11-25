#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat worktree cleanup` (skills/build/helpers.md "After merge"),
# run through bin/mentat on real git checkouts at paths with spaces, with a stub gh that
# answers the one pull request read from files and records every call. Prints PASS/FAIL
# per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/failing git" "$root/home"
failures=0
check() { if eval "$2"; then printf 'PASS: worktree cleanup %s\n' "$1"; else printf 'FAIL: worktree cleanup %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$root/home"
export GIT_CEILING_DIRECTORIES="$root"

# gh: the one read cleanup makes, answered from $STUB/pr, or failing as a signed-out gh
# does when $STUB/gh_fail exists. Every call is recorded.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/gh_calls"
if [ -f "$STUB/gh_fail" ]; then echo "To get started with GitHub CLI, please run:  gh auth login" >&2; exit 4; fi
case "$*" in
  "pr view 12 --json state,headRefName,headRefOid") cat "$STUB/pr" ;;
  *) echo "no pull requests found" >&2; exit 1 ;;
esac
STUBEOF
# A git that passes everything to the real one but fails a branch delete, for the case
# where the delete fails after the worktree is removed.
real_git=$(command -v git)
cat >"$root/failing git/git" <<STUBEOF
#!/usr/bin/env bash
case " \$* " in *" branch -D "*) echo "error: could not delete the branch (test)" >&2; exit 1 ;; esac
exec $(printf %q "$real_git") "\$@"
STUBEOF
chmod +x "$root/bin/gh" "$root/failing git/git"
export PATH="$root/bin:$PATH"

# An origin, a seed clone that pushes to it, and the main checkout W (a clone). main holds
# a .gitignore so a worktree can hold an ignored file.
O="$root/the origin.git" SEED="$root/seed" W="$root/main checkout"
git init -q --bare -b main "$O"
git init -q -b main "$SEED"
git -C "$SEED" remote add origin "$O"
(cd "$SEED" && printf '*.log\n' >.gitignore && printf 'a\n' >file.txt && git add -A && git commit -qm one && git push -q origin HEAD:main) || exit 1
git clone -q "$O" "$W" || exit 1

n=0
# A fresh branch with one commit of its own, pushed to origin; with $2 "wt", a worktree on
# it under W's .claude/worktrees. Sets B (the branch), P (its worktree path) and OID.
fresh() {
  n=$((n + 1)) B="feat/item-$n" P="$W/.claude/worktrees/item $n"
  git -C "$W" branch -q --no-track "$B" origin/main || exit 1
  if [ "${1:-}" = wt ]; then
    git -C "$W" worktree add -q "$P" "$B" && git -C "$P" commit -q --allow-empty -m "work $n" && git -C "$P" push -q origin "$B" || exit 1
  else
    git -C "$W" push -q origin "$B" || exit 1
  fi
  OID=$(git -C "$W" rev-parse "refs/heads/$B")
  rm -f "$STUB/gh_calls" "$STUB/gh_fail"
}
pr() { # $1 state, $2 head branch name, $3 head commit
  printf '{"state":"%s","headRefName":"%s","headRefOid":"%s"}\n' "$1" "$2" "$3" >"$STUB/pr"
}
# cleanup <PR> <branch> from directory $1 (W by default); stdout and stderr in $root/out.
run() { local d=${CWD:-$W}; (cd "$d" && "$mentat" worktree cleanup "$@" >"$root/out" 2>&1); echo $?; }
said() { grep -qF -- "$1" "$root/out"; }
has_branch() { git -C "$W" show-ref --verify --quiet "refs/heads/$1"; }
has_wt() { [ -d "$1" ] && git -C "$W" worktree list --porcelain | grep -qxF "worktree $(cd "$1" && pwd -P)"; }
on_origin() { git -C "$O" show-ref --verify --quiet "refs/heads/$1"; }
only_read() { [ -f "$STUB/gh_calls" ] && [ "$(cat "$STUB/gh_calls")" = "pr view 12 --json state,headRefName,headRefOid" ]; }
kept() { has_branch "$B" && has_wt "$P" && on_origin "$B"; }

# c. All checks pass: the worktree goes, then the branch; the remote branch stays.
fresh wt; pr MERGED "$B" "$OID"
rc=$(run 12 "$B")
check "c. merged, same head, clean worktree: exit 0, worktree and branch removed" '[ "$rc" = 0 ] && ! has_branch "$B" && [ ! -d "$P" ] && ! git -C "$W" worktree list | grep -qF "item $n"'
check "c. the remote branch is left alone and gh only read the pull request" 'on_origin "$B" && only_read && said "$B"'

# f. No worktree has the branch: the branch is deleted.
fresh; pr MERGED "$B" "$OID"
rc=$(run 12 "$B")
check "f. no worktree, checks pass: exit 0, branch deleted, remote kept" '[ "$rc" = 0 ] && ! has_branch "$B" && on_origin "$B"'

# d. Each failed check: nothing changed, exit 1, the check named.
fresh wt
pr OPEN "$B" "$OID"; rc=$(run 12 "$B")
check "d. pull request open: exit 1, says not merged, nothing changed" '[ "$rc" = 1 ] && said "not merged" && said "OPEN" && kept'
pr CLOSED "$B" "$OID"; rc=$(run 12 "$B")
check "d. pull request closed unmerged: exit 1, says not merged, nothing changed" '[ "$rc" = 1 ] && said "not merged" && said "CLOSED" && kept'
pr MERGED "feat/other" "$OID"; rc=$(run 12 "$B")
check "d. head branch name differs: exit 1, names both, nothing changed" '[ "$rc" = 1 ] && said "feat/other" && said "head branch" && kept'
pr MERGED "$B" 1111111111111111111111111111111111111111; rc=$(run 12 "$B")
check "d. pull request head differs from the local branch: exit 1, names both commits, nothing changed" '[ "$rc" = 1 ] && said 1111111111111111111111111111111111111111 && said "$OID" && kept'
pr MERGED "$B" "$OID"
printf 'b\n' >>"$P/file.txt"; rc=$(run 12 "$B"); git -C "$P" checkout -q -- file.txt
check "d. worktree has an uncommitted change: exit 1, names the path, nothing changed" '[ "$rc" = 1 ] && said "not clean" && said "file.txt" && kept'
printf 'x\n' >"$P/untracked file"; rc=$(run 12 "$B"); rm "$P/untracked file"
check "d. worktree has an untracked file: exit 1, names it, nothing changed" '[ "$rc" = 1 ] && said "untracked file" && kept'
printf 'x\n' >"$P/build.log"; rc=$(run 12 "$B"); rm "$P/build.log"
check "d. worktree has an ignored file: exit 1, names it, nothing changed" '[ "$rc" = 1 ] && said "build.log" && kept'
rc=$(CWD="$P" run 12 "$B")
check "d. run from inside the worktree: exit 1, names the running checkout, nothing changed" '[ "$rc" = 1 ] && said "runs in" && kept'
mkdir -p "$P/deeper dir"
rc=$(CWD="$P/deeper dir" run 12 "$B")
check "d. run from a folder inside the worktree: exit 1, nothing changed" '[ "$rc" = 1 ] && said "runs in" && kept'
rmdir "$P/deeper dir"
git -C "$W" worktree add -q --detach "$P/nested one" HEAD || exit 1
printf '/nested one\n' >>"$(git -C "$P" rev-parse --git-path info/exclude)"
rc=$(run 12 "$B")
check "d. another worktree nested under it: exit 1, names the nested one, nothing changed" '[ "$rc" = 1 ] && said "nested one" && kept && has_wt "$P/nested one"'
pr OPEN "$B" "$OID"; printf 'x\n' >"$P/untracked file"; rc=$(run 12 "$B"); rm "$P/untracked file"
check "d. several checks fail: only the first, not merged, is named" '[ "$rc" = 1 ] && said "not merged" && ! said "untracked file" && ! said "nested"'
git -C "$W" worktree remove "$P/nested one" || exit 1

# e. The pull request cannot be read: exit 2, worded apart from "not merged", nothing changed.
fresh wt; pr MERGED "$B" "$OID"
touch "$STUB/gh_fail"; rc=$(run 12 "$B"); rm "$STUB/gh_fail"
check "e. gh fails (signed out): exit 2, could not read, not \"not merged\", nothing changed" '[ "$rc" = 2 ] && said "could not read pull request #12" && ! said "not merged" && kept'
rc=$(run 99 "$B")
check "e. no such pull request: exit 2, nothing changed" '[ "$rc" = 2 ] && said "could not read pull request #99" && kept'
printf 'not json\n' >"$STUB/pr"; rc=$(run 12 "$B")
check "e. gh prints something that is not the pull request: exit 2, nothing changed" '[ "$rc" = 2 ] && said "could not read pull request #12" && kept'
printf '{"headRefName":"%s","headRefOid":"%s"}\n' "$B" "$OID" >"$STUB/pr"; rc=$(run 12 "$B")
check "e. the reply has no state: exit 2, nothing changed" '[ "$rc" = 2 ] && ! said "not merged" && kept'

# g. git refuses the removal (a locked worktree): worktree and branch kept, exit 1, named.
pr MERGED "$B" "$OID"
git -C "$W" worktree lock "$P" || exit 1
rc=$(run 12 "$B")
check "g. locked worktree: exit 1, names the refused removal, worktree and branch kept" '[ "$rc" = 1 ] && said "refused" && said "item $n" && kept'
git -C "$W" worktree unlock "$P" || exit 1

# h. The worktree is removed, then the branch delete fails: exit 1, names the branch left.
rc=$(PATH="$root/failing git:$PATH" run 12 "$B")
check "h. branch delete fails after the removal: exit 1, worktree gone, names the branch left" '[ "$rc" = 1 ] && [ ! -d "$P" ] && has_branch "$B" && said "$B" && said "left"'
git -C "$W" branch -q -D "$B" || exit 1

# i. The branch is already gone and no worktree has it.
fresh; git -C "$W" branch -q -D "$B" || exit 1
pr MERGED "$B" "$OID"; rc=$(run 12 "$B")
check "i. branch gone, merged with that head name: exit 0, says nothing to remove" '[ "$rc" = 0 ] && said "nothing to remove" && on_origin "$B" && only_read'
pr OPEN "$B" "$OID"; rc=$(run 12 "$B")
check "i. branch gone, pull request not merged: exit 1, says not merged" '[ "$rc" = 1 ] && said "not merged"'
pr MERGED "feat/other" "$OID"; rc=$(run 12 "$B")
check "i. branch gone, another head branch name: exit 1, names it" '[ "$rc" = 1 ] && said "feat/other"'

# Usage.
for args in "" "12" "x feat/a" "12 a b" "12 bad..name"; do
  # shellcheck disable=SC2086 # the words are the arguments
  rc=$(run $args)
  check "usage error (exit 64) for: mentat worktree cleanup $args" '[ "$rc" = 64 ] && said "usage: mentat worktree cleanup <pull request number> <branch>"'
done
rc=$("$mentat" nonsense >/dev/null 2>"$root/out"; echo $?)
check "mentat's usage names mentat worktree cleanup" '[ "$rc" = 64 ] && said "| mentat worktree cleanup <pull request number> <branch>"'

[ "$failures" -eq 0 ]
