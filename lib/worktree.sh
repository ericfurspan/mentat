# shellcheck shell=bash
# mentat worktree: the git checks a build makes on branches and worktrees, as
# skills/build/helpers.md words them. Sourced by bin/mentat.

worktree_usage="usage: mentat worktree branch <name> | mentat worktree snapshot [<checkout>] | mentat worktree verify <line> [<checkout>]"

worktree_command() {
  local sub=${1:-}
  [ $# -eq 0 ] || shift
  case "$sub" in
    branch) worktree_branch "$@" ;;
    snapshot) worktree_snapshot "$@" ;;
    verify) worktree_verify "$@" ;;
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
# .claude/worktrees), wt_clean (clean or dirty) and wt_hash (the SHA-256 of wt_status).
# Returns 1 when the checkout cannot be read.
wt_read() { # $1 checkout
  wt_top="" wt_branch="" wt_head="" wt_status="" wt_clean="" wt_hash=""
  [ -n "$1" ] || return 1
  if ! wt_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || [ -z "$wt_top" ]; then return 1; fi
  wt_head=$(git -C "$wt_top" rev-parse --verify -q HEAD) || return 1
  wt_branch=$(git -C "$wt_top" symbolic-ref -q --short HEAD) || wt_branch=detached
  wt_status=$(git -C "$wt_top" status --porcelain -- ':(exclude).claude/worktrees') || return 1
  if ! wt_hash=$(printf '%s' "$wt_status" | shasum -a 256 | cut -d ' ' -f 1) || [ ${#wt_hash} != 64 ]; then return 1; fi
  wt_clean=clean
  [ -z "$wt_status" ] || wt_clean=dirty
}

# mentat worktree snapshot [<checkout>]: one line, "<branch|detached> <HEAD> <clean|dirty>
# <status hash>", for checkout $1, by default the main checkout. 2 when it cannot be read.
worktree_snapshot() {
  local c
  [ $# -le 1 ] || die "usage: mentat worktree snapshot [<checkout>]" 64
  if [ $# -eq 1 ]; then c=$1; else c=$(main_checkout); fi
  wt_read "$c" || die "could not read the checkout${c:+: $c}" 2
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
# 2 the line cannot be parsed or the checkout cannot be read. Either way it says when the
# snapshot's checkout was not clean, which makes the check weaker.
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
  wt_read "$c" || die "could not read the checkout${c:+: $c}" 2
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
