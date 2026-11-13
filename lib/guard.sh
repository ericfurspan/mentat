# shellcheck shell=bash
# shellcheck disable=SC2154 # root, Mentat's folder, is set by bin/mentat.
# mentat guard install | status. Sourced by bin/mentat.

# The trusted folder outside every repository that holds the git hooks and scanner,
# the wrapper's place first on PATH, and the files the installer copies there.
guard_dir() { printf '%s/mentat/git-guard' "${XDG_DATA_HOME:-$HOME/.local/share}"; }
guard_wrapper() { printf '%s/.local/bin/git' "$HOME"; }
GUARD_FILES="scan git hooks/pre-commit hooks/prepare-commit-msg hooks/pre-push"

# guard_copy <source> <destination>: writes the file beside its destination, then
# renames it there, so a symlink at the destination is replaced, never followed.
guard_copy() {
  local tmp
  tmp=$(mktemp "$(dirname "$2")/.mentat-guard.XXXXXX") || return 1
  if cp "$1" "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$2"; then
    printf 'wrote %s\n' "$2"
  else
    rm -f "$tmp"
    return 1
  fi
}

guard_install() {
  local dir bin f
  [ -n "${HOME:-}" ] || die "HOME is not set"
  dir=$(guard_dir) bin=$(guard_wrapper)
  mkdir -p "$dir/hooks" "$(dirname "$bin")" || die "could not create $dir or $(dirname "$bin")"
  for f in $GUARD_FILES; do
    guard_copy "$root/git-guard/$f" "$dir/$f" || die "could not write $dir/$f"
  done
  guard_copy "$root/git-guard/git" "$bin" || die "could not write $bin"
}

# guard_state: prints, read-only, one line for the guard folder and one for the
# wrapper; returns 0 only when both are installed and the same as this copy of Mentat.
guard_state() {
  local dir bin f missing="" stale="" rc=0
  dir=$(guard_dir) bin=$(guard_wrapper)
  for f in $GUARD_FILES; do
    if [ ! -f "$dir/$f" ] || [ ! -x "$dir/$f" ]; then missing+=" $f"
    elif ! cmp -s "$root/git-guard/$f" "$dir/$f"; then stale+=" $f"; fi
  done
  if [ -n "$missing" ]; then printf 'git guard: not installed in %s (missing:%s)\n' "$dir" "$missing"; rc=1
  elif [ -n "$stale" ]; then printf 'git guard: not current in %s (differs:%s)\n' "$dir" "$stale"; rc=1
  else printf 'git guard: installed and current in %s\n' "$dir"; fi
  if [ ! -f "$bin" ] || [ ! -x "$bin" ]; then printf 'git wrapper: not installed at %s\n' "$bin"; rc=1
  elif ! cmp -s "$root/git-guard/git" "$bin"; then printf 'git wrapper: not current at %s\n' "$bin"; rc=1
  else printf 'git wrapper: installed and current at %s\n' "$bin"; fi
  return "$rc"
}

guard() {
  case "${1:-} $#" in
    "install 1") guard_install ;;
    "status 1")
      [ -n "${HOME:-}" ] || die "HOME is not set"
      guard_state || exit 1
      ;;
    *) die "usage: mentat guard install | mentat guard status" 64 ;;
  esac
}
