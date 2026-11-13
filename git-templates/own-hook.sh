# shellcheck shell=bash
# Sourced by Mentat's git hook templates after their own checks pass, and by the
# chain-only templates, which have none.

# own_hook <name> [arguments]: replaces this process with the repository's own <name>
# hook, from its local core.hooksPath, else the hooks folder in its git directory, so
# the hook gets these arguments and this process's stdin, and its exit status is the
# template's. Like git, it skips a hook that is missing or not executable (exit 0).
# The local setting is read because core.hooksPath as a whole names these templates.
# MENTAT_OWN_HOOK, set for the repository's hook, stops a hook that leads back here
# from running its own hook again; Mentat's checks still run each time.
own_hook() {
  local name=$1 dir
  shift
  [ -z "${MENTAT_OWN_HOOK:-}" ] || exit 0
  dir=$(git config --local --type=path --get core.hooksPath 2>/dev/null) || dir=""
  if [ -z "$dir" ]; then
    dir=$(git rev-parse --git-common-dir 2>/dev/null) && [ -n "$dir" ] || {
      printf 'Mentat: %s refused: git could not find the repository folder, so its own %s hook could not run.\n' "$name" "$name" >&2
      exit 1
    }
    dir=$dir/hooks
  fi
  [ -f "$dir/$name" ] && [ -x "$dir/$name" ] || exit 0
  # Git commands the hook runs inherit MENTAT_OWN_HOOK; clearing it would drop the guard.
  MENTAT_OWN_HOOK=1 exec "$dir/$name" "$@"
}
