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

# templates_scan <Mentat folder> <templates folder>: compares, read-only, the installed
# copy with <Mentat folder>/git-templates and sets t_nofolder (1 when the folder is
# missing), t_missing and t_differs (the files missing or not executable where the
# source is, and those that differ, each with a leading space) and t_tools (gitleaks
# and jq, which the scan needs, when not installed). 0 no problem, 1 some.
templates_scan() {
  local src=$1/git-templates dir=$2 f p
  t_nofolder="" t_missing="" t_differs="" t_tools=""
  if [ ! -d "$dir" ]; then t_nofolder=1
  else
    for p in "$src/scan" "$src/own-hook.sh" "$src"/hooks/*; do
      f=${p#"$src"/}
      if [ ! -f "$dir/$f" ] || { [ -x "$p" ] && [ ! -x "$dir/$f" ]; }; then t_missing+=" $f"
      elif ! cmp -s "$p" "$dir/$f"; then t_differs+=" $f"; fi
    done
  fi
  for f in gitleaks jq; do command -v "$f" >/dev/null 2>&1 || t_tools+=" $f"; done
  [ -z "$t_nofolder$t_missing$t_differs$t_tools" ]
}

# templates_problems <Mentat folder> <templates folder>: prints one line per problem,
# naming the folder and each file. 0 none, 1 some.
templates_problems() {
  local dir=$2 f IFS=$' \t\n'
  templates_scan "$1" "$dir" && return 0
  [ -z "$t_nofolder" ] || printf 'the git hook templates folder %s is missing, so agents'"'"' git runs no hooks\n' "$dir"
  [ -z "$t_missing" ] || printf 'the git hook templates in %s are missing or not executable (%s), so agents'"'"' git may skip checks or the repository'"'"'s own hooks\n' "$dir" "${t_missing# }"
  [ -z "$t_differs" ] || printf 'the git hook templates in %s differ from this copy of Mentat (%s), so agents'"'"' git runs other checks\n' "$dir" "${t_differs# }"
  for f in $t_tools; do
    printf '%s is not installed, so the git hook templates in %s refuse every agent commit and push\n' "$f" "$dir"
  done
  return 1
}

# templates_summary <Mentat folder> <templates folder>: prints one line of counts, with
# no folder or file names, so its length has a fixed bound. 0 no problem (nothing
# printed), 1 some.
templates_summary() {
  local parts="" n IFS=$' \t\n'
  templates_scan "$1" "$2" && return 0
  [ -z "$t_nofolder" ] || parts+=", the folder is missing"
  # shellcheck disable=SC2086 # counts the words of each list.
  n=$(set -- $t_missing; echo $#); [ "$n" = 0 ] || parts+=", $n missing or not executable"
  # shellcheck disable=SC2086
  n=$(set -- $t_differs; echo $#); [ "$n" = 0 ] || parts+=", $n changed"
  [ -z "$t_tools" ] || parts+=", not installed:$t_tools"
  printf 'the git hook templates agents'"'"' git uses have problems (%s), so agents'"'"' commits and pushes may be refused or unchecked\n' "${parts#, }"
  return 1
}
