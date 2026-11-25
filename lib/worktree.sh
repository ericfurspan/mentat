# shellcheck shell=bash
# mentat worktree: the git checks a build makes on branches and worktrees, as
# skills/build/helpers.md words them. Sourced by bin/mentat.

worktree_usage="usage: mentat worktree branch <name> | mentat worktree snapshot [<checkout>] | mentat worktree verify <line> [<checkout>] | mentat worktree cleanup <pull request number> <branch>"

worktree_command() {
  local sub=${1:-}
  [ $# -eq 0 ] || shift
  case "$sub" in
    branch) worktree_branch "$@" ;;
    snapshot) worktree_snapshot "$@" ;;
    verify) worktree_verify "$@" ;;
    cleanup) worktree_cleanup "$@" ;;
    *) die "$worktree_usage" 64 ;;
  esac
}

# The main checkout of the repository the current directory is in: the folder above the
# common git directory. Prints nothing outside a repository.
main_checkout() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ -z "$common" ] || dirname "$common"
}

# Reads checkout $1 as the main-checkout check notes it. Sets wt_top, wt_branch (the
# branch, or detached), wt_head, wt_status (git status --porcelain, without
# .claude/worktrees, less its final newline), wt_clean (clean or dirty) and wt_hash (the
# SHA-256 of that command's exact output).
# Returns 1 when the checkout cannot be read, 3 when it is on a branch named detached,
# which the snapshot line cannot tell apart from a detached HEAD.
wt_read() { # $1 checkout
  wt_top="" wt_branch="" wt_head="" wt_status="" wt_clean="" wt_hash=""
  [ -n "$1" ] || return 1
  if ! wt_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || [ -z "$wt_top" ]; then return 1; fi
  wt_head=$(git -C "$wt_top" rev-parse --verify -q HEAD) || return 1
  if wt_branch=$(git -C "$wt_top" symbolic-ref -q --short HEAD); then
    [ "$wt_branch" != detached ] || return 3
  else
    wt_branch=detached
  fi
  # The x keeps the output's trailing newline, so the hash is of git's exact bytes.
  wt_status=$(git -C "$wt_top" status --porcelain -- ':(exclude).claude/worktrees' && printf x) || return 1
  wt_status=${wt_status%x}
  if ! wt_hash=$(printf '%s' "$wt_status" | shasum -a 256 | cut -d ' ' -f 1) || [ ${#wt_hash} != 64 ]; then return 1; fi
  wt_status=${wt_status%$'\n'}
  wt_clean=clean
  [ -z "$wt_status" ] || wt_clean=dirty
}

# wt_read, exiting 2 when checkout $1 cannot be read or is on a branch named detached.
wt_read_or_die() { # $1 checkout
  local rc=0
  wt_read "$1" || rc=$?
  [ "$rc" != 3 ] || die "the checkout is on a branch named detached, which cannot be told apart from a detached HEAD in a snapshot line: $1" 2
  [ "$rc" = 0 ] || die "could not read the checkout${1:+: $1}" 2
}

# mentat worktree snapshot [<checkout>]: one line, "<branch|detached> <HEAD> <clean|dirty>
# <status hash>", for checkout $1, by default the main checkout. 2 when it cannot be read
# or is on a branch named detached.
worktree_snapshot() {
  local c
  [ $# -le 1 ] || die "usage: mentat worktree snapshot [<checkout>]" 64
  if [ $# -eq 1 ]; then c=$1; else c=$(main_checkout); fi
  wt_read_or_die "$c"
  printf '%s %s %s %s\n' "$wt_branch" "$wt_head" "$wt_clean" "$wt_hash"
}

# Whether $1 is 40 or 64 lowercase hex characters (a commit; $2 64 alone, for a hash).
wt_hex() { # $1 text, $2 "64" for 64 only
  case "$1" in '' | *[!0-9a-f]*) return 1 ;; esac
  [ ${#1} = 64 ] || { [ "${2:-}" != 64 ] && [ ${#1} = 40 ]; }
}

# mentat worktree verify <line> [<checkout>]: compares the checkout (by default the main
# checkout) with a snapshot line, by the rule of "Main-checkout check" in
# skills/build/helpers.md: unchanged when the branch is the noted one, the status hash is
# the noted one, and HEAD is the noted one or moved only forward along origin/<branch> as
# last fetched (no fetch). Detached at the snapshot, only the same HEAD passes. 0 unchanged,
# 1 changed (each difference named, with the current status paths on a status change),
# 2 the line cannot be parsed or the checkout cannot be read or is on a branch named
# detached (never reported unchanged). Either way it says when the snapshot's checkout was
# not clean, which makes the check weaker.
worktree_verify() {
  local line c b h s x rest changed=no
  [ $# -eq 1 ] || [ $# -eq 2 ] || die "usage: mentat worktree verify <line> [<checkout>]" 64
  line=$1
  case "$line" in *$'\n'*) die "could not parse the snapshot line: it holds more than one line" 2 ;; esac
  read -r b h s x rest <<<"$line"
  if [ -n "$rest" ] || [ "$b $h $s $x" != "$line" ] || ! wt_hex "$h" || ! wt_hex "$x" 64 ||
    { [ "$s" != clean ] && [ "$s" != dirty ]; } ||
    { [ "$b" != detached ] && ! git check-ref-format "refs/heads/$b"; }; then
    die "could not parse the snapshot line: $line" 2
  fi
  if [ $# -eq 2 ]; then c=$2; else c=$(main_checkout); fi
  wt_read_or_die "$c"
  if [ "$wt_branch" != "$b" ]; then
    changed=yes
    printf 'branch: was %s, now %s\n' "$b" "$wt_branch"
  fi
  if [ "$wt_hash" != "$x" ]; then
    changed=yes
    if [ -z "$wt_status" ]; then printf 'status: changed, now clean\n'
    else printf 'status: changed, now:\n%s\n' "$wt_status" | sed '2,$s/^/  /'; fi
  fi
  if [ "$wt_head" != "$h" ]; then
    if [ "$b" = detached ]; then
      changed=yes
      printf 'HEAD: moved from %s to %s (detached at the snapshot: only the same HEAD passes)\n' "$h" "$wt_head"
    elif ! git -C "$wt_top" merge-base --is-ancestor "$h" "$wt_head" 2>/dev/null ||
      ! git -C "$wt_top" merge-base --is-ancestor "$wt_head" "refs/remotes/origin/$b" 2>/dev/null; then
      changed=yes
      printf 'HEAD: moved from %s to %s, not only forward along origin/%s as last fetched\n' "$h" "$wt_head" "$b"
    fi
  fi
  [ "$s" = clean ] || printf 'note: the checkout was not clean at the snapshot, so this check is weaker (it does not see edits to files already changed)\n'
  if [ "$changed" = yes ]; then printf 'changed: %s\n' "$wt_top"; return 1; fi
  printf 'unchanged: %s\n' "$wt_top"
}

# mentat worktree branch <name>: makes local branch <name> from origin's default branch as
# fetched now, with no upstream. A branch that already exists is the lock a build run skips
# on: exit 1 before any network read. 2 when the fetch fails or the default branch cannot
# be found; no branch is made unless it exits 0.
worktree_branch() {
  local name top def
  case "${1:-}" in '' | -*) die "usage: mentat worktree branch <name>" 64 ;; esac
  if [ $# -ne 1 ] || ! git check-ref-format "refs/heads/$1"; then die "usage: mentat worktree branch <name>" 64; fi
  name=$1
  if ! top=$(git rev-parse --show-toplevel 2>/dev/null) || [ -z "$top" ]; then die "not inside a git checkout" 2; fi
  if git -C "$top" show-ref --verify --quiet "refs/heads/$name"; then die "branch $name already exists; nothing fetched or made" 1; fi
  GIT_TERMINAL_PROMPT=0 git -C "$top" fetch -q origin || die "could not fetch origin; branch $name not made" 2
  def=$(default_branch "$top")
  [ -n "$def" ] || die "origin's default branch could not be found; branch $name not made" 2
  git -C "$top" branch -q --no-track "$name" "refs/remotes/origin/$def" || die "could not make branch $name from origin/$def" 2
  printf 'made branch %s from origin/%s\n' "$name" "$def"
}

# The physical path of folder $1 (symbolic links resolved), or $1 as given when it cannot
# be entered, so paths git records and paths the shell reports compare equal.
wt_phys() { (cd -P "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }

# mentat worktree cleanup <PR> <branch>: after a merge, removes the worktree on <branch>
# and then the local branch, as "After merge" in skills/build/helpers.md says, with every
# check made before anything changes: the pull request is MERGED with head branch name
# <branch>; when the local branch exists, the pull request's head is its commit; when a
# worktree has the branch, it is not the checkout this runs in, no other worktree is
# nested under it, and git status --porcelain --ignored prints nothing in it. The removal
# is never forced and the remote branch is never touched. 0 done or nothing to remove,
# 1 the first failed check named (or git refused the removal, or the branch delete failed
# after it), 2 the pull request could not be read.
worktree_cleanup() {
  local pr branch top json state head_name head_oid tip list l path="" wt="" here wt_p q st err
  case "${1:-}" in '' | *[!0-9]*) die "usage: mentat worktree cleanup <pull request number> <branch>" 64 ;; esac
  case "${2:-}" in '' | -*) die "usage: mentat worktree cleanup <pull request number> <branch>" 64 ;; esac
  if [ $# -ne 2 ] || ! git check-ref-format "refs/heads/$2"; then die "usage: mentat worktree cleanup <pull request number> <branch>" 64; fi
  pr=$1 branch=$2
  if ! top=$(git rev-parse --show-toplevel 2>/dev/null) || [ -z "$top" ]; then die "not inside a git checkout; nothing changed" 1; fi

  # The pull request: one read. A failed or unusable read is not "not merged".
  if ! json=$(gh pr view "$pr" --json state,headRefName,headRefOid 2>/dev/null) ||
    ! state=$(printf '%s' "$json" | jq -er '.state | strings' 2>/dev/null) ||
    ! head_name=$(printf '%s' "$json" | jq -er '.headRefName | strings' 2>/dev/null) ||
    ! head_oid=$(printf '%s' "$json" | jq -er '.headRefOid | strings' 2>/dev/null) ||
    [ -z "$state" ] || [ -z "$head_name" ] || ! wt_hex "$head_oid"; then
    die "could not read pull request #$pr (gh failed or is signed out, or there is no such pull request); nothing changed" 2
  fi
  [ "$state" = MERGED ] || die "pull request #$pr is not merged (its state is $state); nothing changed" 1
  [ "$head_name" = "$branch" ] || die "pull request #$pr's head branch is $head_name, not $branch; nothing changed" 1

  # The local branch, when it exists, is the pull request's head.
  if git -C "$top" show-ref --verify --quiet "refs/heads/$branch"; then
    tip=$(git -C "$top" rev-parse --verify -q "refs/heads/$branch") || die "could not read branch $branch; nothing changed" 1
    [ "$tip" = "$head_oid" ] || die "pull request #$pr's head is $head_oid, but branch $branch is at $tip; nothing changed" 1
  else
    tip=""
  fi

  # The worktree on the branch, if any, from git's list (a path may hold spaces).
  list=$(git -C "$top" worktree list --porcelain) || die "could not list the worktrees; nothing changed" 1
  while IFS= read -r l; do
    case "$l" in
      "worktree "*) path=${l#worktree } ;;
      "branch "*) [ "${l#branch }" != "refs/heads/$branch" ] || wt=$path ;;
    esac
  done <<<"$list"

  if [ -z "$tip" ] && [ -z "$wt" ]; then
    printf 'nothing to remove: branch %s is gone and no worktree has it; pull request #%s merged\n' "$branch" "$pr"
    return 0
  fi

  if [ -n "$wt" ]; then
    wt_p=$(wt_phys "$wt")
    here=$(wt_phys "$top")
    [ "$here" != "$wt_p" ] || die "the worktree at $wt on $branch is the checkout this command runs in; nothing changed" 1
    while IFS= read -r l; do
      case "$l" in "worktree "*) ;; *) continue ;; esac
      q=$(wt_phys "${l#worktree }")
      case "$q" in "$wt_p"/*) die "the worktree at $wt on $branch has another worktree under it: ${l#worktree }; nothing changed" 1 ;; esac
    done <<<"$list"
    st=$(git -C "$wt" status --porcelain --ignored 2>/dev/null) || die "could not read the status of the worktree at $wt on $branch; nothing changed" 1
    [ -z "$st" ] || die "the worktree at $wt on $branch is not clean (git status --porcelain --ignored lists:
$st
); nothing changed" 1
    if ! err=$(git -C "$top" worktree remove "$wt" 2>&1); then
      die "git refused to remove the worktree at $wt: ${err//$'\n'/ }; kept it and branch $branch" 1
    fi
    printf 'removed the worktree at %s\n' "$wt"
  fi
  if ! err=$(git -C "$top" branch -D "$branch" 2>&1); then
    die "could not delete branch $branch: ${err//$'\n'/ }; branch $branch is left" 1
  fi
  printf 'deleted branch %s (the remote branch is left alone)\n' "$branch"
}
