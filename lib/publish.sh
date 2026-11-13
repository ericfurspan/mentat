# shellcheck shell=bash
# The publish check: text about to be posted on GitHub holds a local path or a
# private name. Reports a hit by category only, never the match. Sourced by
# bin/mentat.

PRIVATE_WORDS="$HOME/.config/mentat/private-words"

# Prints the category of the first hit in text $1, or returns 1 with none. Each line
# of the word list is a fixed string, ignoring case. A line starting with exact:
# matches the rest only in that case and as a whole word, bounded by a character
# that is not a letter, digit or underscore or by the text's edge, so one whose
# first or last character is not a letter, digit or underscore can miss. Blank
# lines, lines starting with # and a line that is only exact: are skipped. A missing
# or unreadable list counts as empty. Here-strings, not pipes: under pipefail,
# grep -q stopping early on long text would read as no hit.
private_text() {
  local words exact
  if grep -aiqF -e "$HOME" <<<"$1"; then printf 'a local path'; return 0; fi
  words=$(grep -v -e '^[[:space:]]*$' -e '^#' -e '^exact:' "$PRIVATE_WORDS" 2>/dev/null)
  exact=$(sed -n 's/^exact:\(..*\)$/\1/p' "$PRIVATE_WORDS" 2>/dev/null)
  if { [ -n "$words" ] && grep -aiqF -e "$words" <<<"$1"; } ||
    { [ -n "$exact" ] && grep -aqFw -e "$exact" <<<"$1"; }; then
    printf 'a configured private name'; return 0
  fi
  return 1
}

# Prints the category when text $1 must not go to repository $2 (owner/name, or empty
# for this checkout's) without a look, or returns 1. A private repository's own names
# are expected in its text. A failed lookup counts as public, and only a hit looks.
publish_hit() {
  local hit
  hit=$(private_text "$1") || return 1
  [ "$(gh repo view ${2:+"$2"} --json isPrivate --jq .isPrivate 2>/dev/null)" != true ] || return 1
  printf '%s' "$hit"
}

# For a review about to post comment text $1 on repository $2: on a hit, keeps the
# comment in a private file and prints the sentence that names the file and the
# category. Returns 1 with no hit.
held_comment() {
  local hit kept
  hit=$(publish_hit "$1" "$2") || return 1
  if kept=$(mktemp "${TMPDIR:-/tmp}/mentat-held-comment.XXXXXX") && printf '%s\n' "$1" >"$kept"; then
    printf 'the comment holds %s, so it was not posted; the maintainer can read it at %s' "$hit" "$kept"
  else
    printf 'the comment holds %s, so it was not posted, and it could not be kept' "$hit"
  fi
}
