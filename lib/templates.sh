# shellcheck shell=bash
# The installed git hook templates. Sourced by bin/mentat and hooks/session-start.

# templates_dir: prints the folder agents' git takes its hook templates from:
# MENTAT_GIT_TEMPLATES_DIR, else the parent of the hooks folder that the last
# core.hooksPath entry among GIT_CONFIG_COUNT, GIT_CONFIG_KEY_<n> and GIT_CONFIG_VALUE_<n>
# names (keys match ignoring case, as git's do). Returns 1, printing nothing, when
# neither names one: the templates are not in use.
templates_dir() {
  local i=0 n=${GIT_CONFIG_COUNT:-0} k v hooks=""
  if [ -n "${MENTAT_GIT_TEMPLATES_DIR:-}" ]; then printf '%s\n' "$MENTAT_GIT_TEMPLATES_DIR"; return 0; fi
  case "$n" in '' | *[!0-9]*) return 1 ;; esac
  while [ "$i" -lt "$n" ]; do
    k=GIT_CONFIG_KEY_$i v=GIT_CONFIG_VALUE_$i
    if [ "$(printf '%s' "${!k:-}" | tr '[:upper:]' '[:lower:]')" = core.hookspath ]; then hooks=${!v:-}; fi
    i=$((i + 1))
  done
  hooks=${hooks%/}
  [ -n "$hooks" ] || return 1
  case "$hooks" in */*) printf '%s\n' "${hooks%/*}" ;; *) printf '.\n' ;; esac
}

# templates_problems <Mentat folder> <templates folder>: prints, read-only, one line per
# problem with the installed copy: a file of <Mentat folder>/git-templates missing,
# not executable where the source is, or different, and gitleaks or jq not installed,
# which the scan needs. 0 none, 1 some.
templates_problems() {
  local src=$1/git-templates dir=$2 f p missing="" differs="" rc=0
  if [ ! -d "$dir" ]; then
    printf 'the git hook templates folder %s is missing, so agents'"'"' git runs no hooks\n' "$dir"
    rc=1
  else
    for p in "$src/scan" "$src/own-hook.sh" "$src"/hooks/*; do
      f=${p#"$src"/}
      if [ ! -f "$dir/$f" ] || { [ -x "$p" ] && [ ! -x "$dir/$f" ]; }; then missing+=" $f"
      elif ! cmp -s "$p" "$dir/$f"; then differs+=" $f"; fi
    done
    if [ -n "$missing" ]; then
      printf 'the git hook templates in %s are missing or not executable (%s), so agents'"'"' git may skip checks or the repository'"'"'s own hooks\n' "$dir" "${missing# }"
      rc=1
    fi
    if [ -n "$differs" ]; then
      printf 'the git hook templates in %s differ from this copy of Mentat (%s), so agents'"'"' git runs other checks\n' "$dir" "${differs# }"
      rc=1
    fi
  fi
  for f in gitleaks jq; do
    command -v "$f" >/dev/null 2>&1 && continue
    printf '%s is not installed, so the git hook templates in %s refuse every agent commit and push\n' "$f" "$dir"
    rc=1
  done
  return "$rc"
}
