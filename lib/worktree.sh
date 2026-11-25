# shellcheck shell=bash
# mentat worktree: the git checks a build makes on branches and worktrees, as
# skills/build/helpers.md words them. Sourced by bin/mentat.

worktree_usage="usage: mentat worktree branch <name>"

worktree_command() {
  local sub=${1:-}
  [ $# -eq 0 ] || shift
  case "$sub" in
    branch) worktree_branch "$@" ;;
    *) die "$worktree_usage" 64 ;;
  esac
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
