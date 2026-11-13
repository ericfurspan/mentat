# shellcheck shell=bash
# The installed git hook templates. Sourced by bin/mentat and hooks/session-start.

# Where the git hook templates and their scanner are expected to be installed; agents'
# git names its hooks folder in core.hooksPath. MENTAT_GIT_TEMPLATES_DIR overrides it.
GIT_TEMPLATES_DIR=${MENTAT_GIT_TEMPLATES_DIR:-/Library/Application Support/Mentat/git-templates}
GIT_TEMPLATE_FILES="scan own-hook.sh hooks/pre-commit hooks/pre-push"

# templates_state <Mentat folder>: prints, read-only, one line saying whether every file
# in <Mentat folder>/git-templates is installed in GIT_TEMPLATES_DIR, executable where
# the source is, and the same as the source. 0 all are, 1 not.
templates_state() {
  local src=$1/git-templates f missing="" differs=""
  for f in $GIT_TEMPLATE_FILES; do
    if [ ! -f "$GIT_TEMPLATES_DIR/$f" ] || { [ -x "$src/$f" ] && [ ! -x "$GIT_TEMPLATES_DIR/$f" ]; }; then missing+=" $f"
    elif ! cmp -s "$src/$f" "$GIT_TEMPLATES_DIR/$f"; then differs+=" $f"; fi
  done
  if [ -n "$missing" ]; then
    printf 'the git hook templates in %s are missing or not executable (%s), so agents'"'"' git may run no commit or push checks\n' "$GIT_TEMPLATES_DIR" "${missing# }"
    return 1
  fi
  if [ -n "$differs" ]; then
    printf 'the git hook templates in %s differ from this copy of Mentat (%s), so agents'"'"' git runs other commit and push checks\n' "$GIT_TEMPLATES_DIR" "${differs# }"
    return 1
  fi
  printf 'the git hook templates in %s are installed and current\n' "$GIT_TEMPLATES_DIR"
}
