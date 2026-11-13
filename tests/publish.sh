#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for lib/publish.sh, with a temporary home, a stub word list and a
# stub gh. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
check() { if eval "$2"; then printf 'PASS: publish %s\n' "$1"; else printf 'FAIL: publish %s\n' "$1"; failures=$((failures + 1)); fi; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOME="$root/stub home" STUB="$root/stub" TMPDIR="$root/tmp"
LIST="$HOME/.config/mentat/private-words"
mkdir -p "$STUB" "$root/bin" "$TMPDIR" "$HOME/.config/mentat"
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD: $*" >>"$STUB/calls"
[ -f "$STUB/private" ] && echo true || echo false
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

reset() {
  rm -f "$STUB"/*
  printf '# a comment names commentword\n\n   \nStubCodename\n-dashword\ntwo words\nlastword' >"$LIST"
}
looked_up() { [ -f "$STUB/calls" ]; }

reset
# shellcheck source=/dev/null
. "$root_dir/lib/publish.sh"
# A newline right after the match lets grep -q stop early, which is what fails a pipe
# under pipefail. On one long line grep reads to the end, and a pipe would pass.
long=$(printf 'stubcodename\n%0100000d\n%0100000d' 0 0)
check "a hit early in long text is found under pipefail" '[ "$(private_text "$long")" = "a configured private name" ] && [ "$(publish_hit "$long" owner/repo)" = "a configured private name" ]'
long_path=$(printf '%s\n%0100000d\n%0100000d' "$HOME" 0 0)
check "the home path early in long text is found under pipefail" '[ "$(private_text "$long_path")" = "a local path" ]'
check "the home path reports its category, and a miss returns 1 and prints nothing" '[ "$(private_text "at $HOME")" = "a local path" ] && ! private_text "nothing here" >/dev/null && [ -z "$(private_text "nothing here")" ]'
reset
check "held_comment returns 1 with no hit and looks nothing up" '! held=$(held_comment "nothing here" owner/repo) && [ -z "$held" ] && ! looked_up'
reset; touch "$STUB/private"
check "held_comment leaves a private repository alone" '! held=$(held_comment "about stubcodename" owner/repo) && [ -z "$held" ]'
reset
held=$(held_comment "about StubCodename" owner/repo); kept=${held##* }
check "held_comment keeps the comment and names the file and the category, not the match" 'case "$held" in *"holds a configured private name"*) true ;; *) false ;; esac && [ "$(cat "$kept")" = "about StubCodename" ] && ! grep -qiF stubcodename <<<"$held" && [ "$(stat -f "%Lp" "$kept")" = 600 ]'

# Entries marked exact: match only in their case, as a whole word.
hits() { [ "$(private_text "$1")" = "a configured private name" ]; }
misses() { ! private_text "$1" >/dev/null; }
printf 'exact:StubExact\nexact:a.b' >"$LIST"
check "a marked entry hits in its case as a whole word, also next to punctuation and at the text's edges" 'hits "about StubExact here" && hits "(StubExact)" && hits "StubExact." && hits "StubExact-client" && hits "StubExact" && hits "StubExact at start" && hits "at end StubExact"'
check "a marked entry misses in another case and inside a longer word" 'misses stubexact && misses STUBEXACT && misses "exact:stubexact" && misses StubExacts && misses preStubExact && misses StubExact_2'
check "a dot in a marked entry stays literal" 'misses "about aXb here" && hits "about a.b here"'
long_exact=$(printf 'StubExact\n%0100000d\n%0100000d' 0 0)
check "a marked entry hit early in long text is found under pipefail" 'hits "$long_exact"'
printf 'exact:StubExact\nStubCodename\n-dashword' >"$LIST"
check "unmarked entries still match in any case and inside a word beside a marked one" 'hits "about stubcodename" && hits "xSTUBCODENAMEx" && hits "a -DASHWORD b" && hits "StubExact" && misses stubexact'
printf 'exact:' >"$LIST"
check "a list that is only exact: matches nothing" 'misses "exact: anything" && misses "exact:" && misses "nothing here"'
printf '\nexact:\n\n   \n' >"$LIST"
check "a list of exact: and blank lines matches nothing" 'misses "exact: anything" && misses "a b"'

# The list's comment and blank lines, and an empty or unreadable list.
reset
check "a comment line and blank lines in the list match nothing, beside entries that do" 'misses "about # a comment names commentword" && misses "# a b" && hits "about stubcodename"'
check "an entry with a space matches as a whole, not word by word" 'hits "say TWO WORDS here" && misses "two" && misses "words"'
check "a last line with no trailing newline still matches" 'hits "about LastWord"'
: >"$LIST"
check "an empty list matches nothing" 'misses "about stubcodename" && misses "anything"'
reset; chmod 000 "$LIST"
check "an unreadable list counts as empty, prints nothing, and the home path still hits" '[ -z "$(private_text "about stubcodename" 2>&1)" ] && misses "about stubcodename" && [ "$(private_text "at $HOME/x")" = "a local path" ]'
chmod 600 "$LIST"
reset

[ "$failures" -eq 0 ]
