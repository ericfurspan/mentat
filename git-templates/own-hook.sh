# shellcheck shell=bash
# Sourced by Mentat's git hook templates after their own checks pass, and by the
# chain-only templates, which have none.

# own_git_dir: prints the repository's git directory without starting git where it can:
# GIT_DIR, else ./.git (a folder, or a file naming one), else this folder for a bare
# repository (git runs hooks at the top of the working tree, or in the git directory of
# a bare one). Else it asks git, and when git cannot tell, as while git init creates the
# repository, it uses GIT_DIR. Returns 1 when none is found.
own_git_dir() {
  local d=""
  if [ -n "${GIT_DIR:-}" ]; then d=$GIT_DIR
  elif [ -d .git ]; then d=.git
  elif [ -f .git ]; then
    IFS= read -r d <.git || d=""
    case "$d" in "gitdir: "*) d=${d#gitdir: } ;; *) d="" ;; esac
  elif [ -f HEAD ] && [ -d objects ] && [ -d refs ]; then d=.
  fi
  [ -n "$d" ] || d=$(git rev-parse --git-dir 2>/dev/null) || d=""
  [ -n "$d" ] && printf '%s\n' "$d"
}

# own_hook <name> [arguments]: replaces this process with the repository's own <name>
# hook, from its local core.hooksPath, else the hooks folder in its git common directory,
# so the hook gets these arguments and this process's stdin, and its exit status is the
# template's. Like git, it skips a hook that is missing or not executable (exit 0).
# The local setting is read because core.hooksPath as a whole names these templates; git
# is asked for it only when the repository's config names hooksPath or an include.
# MENTAT_OWN_HOOK lists, one per line, each "<name> <git common dir>" entered on the way
# here. A hook already on the list is a re-entry of the same hook in the same repository,
# which skips its own hook (exit 0); Mentat's checks still run each time.
own_hook() {
  local name=$1 gitdir common="" dir="" key nl=$'\n'
  shift
  gitdir=$(own_git_dir) || {
    printf 'Mentat: %s refused: the repository folder could not be found, so its own %s hook could not run.\n' "$name" "$name" >&2
    exit 1
  }
  if [ -f "$gitdir/commondir" ]; then
    IFS= read -r common <"$gitdir/commondir" || common=""
    case "$common" in "") common=$gitdir ;; /*) ;; *) common=$gitdir/$common ;; esac
  else common=$gitdir; fi
  common=$(cd "$common" 2>/dev/null && pwd -P) || common=$gitdir
  key="$name $common"
  case "$nl${MENTAT_OWN_HOOK:-}$nl" in *"$nl$key$nl"*) exit 0 ;; esac
  if [ -f "$common/config" ] && grep -qi -e hookspath -e include "$common/config" 2>/dev/null; then
    dir=$(git config --local --includes --type=path --get core.hooksPath 2>/dev/null) || dir=""
  fi
  [ -n "$dir" ] || dir=$common/hooks
  [ -f "$dir/$name" ] && [ -x "$dir/$name" ] || exit 0
  # The hook and the git commands it runs inherit the list, so a hook entered again in
  # the same repository is found; another hook or repository still runs its own.
  MENTAT_OWN_HOOK="${MENTAT_OWN_HOOK:+$MENTAT_OWN_HOOK$nl}$key" exec "$dir/$name" "$@"
}
