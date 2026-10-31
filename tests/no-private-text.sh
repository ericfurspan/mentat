#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for lib/publish.sh and hooks/no-private-text, the PreToolUse hook,
# with a temporary home, a stub word list and a stub gh. Prints PASS/FAIL per case;
# exits 1 on any FAIL.
set -uo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root_dir/hooks/no-private-text"
failures=0
check() { if eval "$2"; then printf 'PASS: no-private-text %s\n' "$1"; else printf 'FAIL: no-private-text %s\n' "$1"; failures=$((failures + 1)); fi; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOME="$root/stub home" STUB="$root/stub" TMPDIR="$root/tmp"
LIST="$HOME/.config/mentat/private-words"
mkdir -p "$STUB" "$root/bin" "$TMPDIR" "$HOME/.config/mentat" "$root/work/sub" "$root/other"
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD: $*" >>"$STUB/calls"
[ -f "$STUB/lookup_fails" ] && exit 1
[ -f "$STUB/private" ] && echo true || echo false
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

reset() {
  rm -f "$STUB"/*
  printf '# a comment names commentword\n\n   \nStubCodename\n-dashword\ntwo words\nlastword' >"$LIST"
}
# output <command> [cwd]: prints what the hook prints for a Bash command.
output() {
  jq -n --arg c "$1" --arg d "${2:-$root/work}" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$hook"
}
decision() { output "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
reason() { output "$@" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
looked_up() { [ -f "$STUB/calls" ]; }

reset
# Each listed form, with a hit in its command text.
while IFS= read -r form; do
  check "asks before, with a word in the text: $form" '[ "$(decision "$form --body \"about stubcodename\"")" = ask ]'
  check "asks before, with the home path in the text: $form" '[ "$(decision "$form --body \"at $HOME/x\"")" = ask ]'
  check "leaves alone, with no hit: $form" 'rm -f "$STUB/calls"; [ -z "$(decision "$form --body \"about nothing\"")" ] && ! looked_up'
done <<'FORMS'
gh pr create --title t
gh pr edit 7
gh pr comment 7
gh pr review 7 --comment
gh issue create --title t
gh issue edit 7
gh issue comment 7
gh -R owner/repo pr comment 7
gh pr --repo owner/repo comment 7
gh api -X POST repos/o/r/issues/7/comments
gh api --method=PATCH repos/o/r/issues/7
gh api repos/o/r/issues/7/comments -f body=x
FORMS
check "asks through a body in a heredoc" '[ "$(decision "gh pr create --title t --body \"\$(cat <<EOF
Line one
about StubCodename
EOF
)\"")" = ask ]'
check "asks for a word starting with a dash, one with a space, and a last line with no newline" '[ "$(decision "gh pr comment 7 --body \"a -DASHWORD b\"")" = ask ] && [ "$(decision "gh pr comment 7 --body \"Two Words\"")" = ask ] && [ "$(decision "gh pr comment 7 --body LASTWORD")" = ask ]'

# Commands that write nothing, or are not listed.
while IFS= read -r cmd; do
  check "leaves alone a hit outside the listed writes: $cmd" 'rm -f "$STUB/calls"; [ -z "$(decision "$cmd")" ] && ! looked_up'
done <<'PASS'
gh pr view 7 --json title --jq stubcodename
gh pr list --search stubcodename
gh api repos/o/r/issues --jq stubcodename
gh api -X GET search/issues -f q=stubcodename
echo stubcodename
grep stubcodename README
PASS
check "a blank line and a comment in the list match nothing" '[ -z "$(decision "gh pr comment 7 --body \"about commentword\"")" ] && [ -z "$(decision "gh pr comment 7 --body \"# a b\"")" ]'
other_tool() { jq -n '{tool_name: "Other", tool_input: {command: "gh pr comment 7 --body stubcodename"}}' | "$hook"; }
check "a non-Bash tool is left alone" '[ -z "$(other_tool)" ]'

# A file the command names.
printf 'about StubCodename\n' >"$root/work/word.md"
printf 'from %s/x\n' "$HOME" >"$root/work/path.md"
printf 'clean\n' >"$root/work/clean.md"
mkdir -p "$root/work/a dir"
cp "$root/work/word.md" "$root/work/a dir/word file.md"
cp "$root/work/clean.md" "$HOME/clean.md"
cp "$root/work/word.md" "$root/work/sub/word.md"
while IFS= read -r cmd; do
  check "asks for a hit in a file: $cmd" '[ "$(decision "$cmd")" = ask ]'
done <<'FILES'
gh pr create --body-file word.md
gh pr create --body-file=word.md
gh pr comment 7 -F word.md
gh pr create --body-file path.md
gh pr edit 7 --notes-file word.md
gh pr comment 7 --body-file "a dir/word file.md"
gh pr comment 7 --body-file 'a dir/word file.md'
gh api repos/o/r/issues/7/comments -F body=@word.md
gh api repos/o/r/issues/7/comments -F "body=@word.md"
cd sub && gh pr comment 7 --body-file word.md
FILES
check "follows a file at an absolute path" '[ "$(decision "gh pr comment 7 --body-file $root/work/word.md")" = ask ]'
check "leaves alone a clean file, a name that is no file, and standard input" '[ -z "$(decision "gh pr comment 7 --body-file clean.md")" ] && [ -z "$(decision "gh pr comment 7 --body-file missing.md")" ] && [ -z "$(decision "gh pr comment 7 --body-file -")" ]'
# The name of a file it reads and a leading cd are not published.
check "the name of a clean file under the home folder is no hit, as ~/, \$HOME/ or the path" 'rm -f "$STUB/calls"; [ -z "$(decision "gh pr comment 7 --body-file \"$HOME/clean.md\"")" ] && [ -z "$(decision "gh pr comment 7 --body-file ~/clean.md")" ] && [ -z "$(decision "gh pr comment 7 --body-file \$HOME/clean.md")" ] && ! looked_up'
mkdir -p "$HOME/repo"; cp "$root/work/clean.md" "$HOME/repo/clean.md"
check "a leading cd under the home folder is no hit, and a relative file is read from there" '[ -z "$(decision "cd \"$HOME/repo\" && gh pr comment 7 --body-file clean.md")" ] && [ "$(decision "cd \"$HOME/repo\" && gh pr comment 7 --body \"at $HOME/x\"")" = ask ]'
check "a home path in an api field is a hit, even after -F" '[ "$(decision "gh api repos/o/r/issues -F body=$HOME/x")" = ask ]'
check "a home path in a variable set before gh is a hit" '[ "$(decision "b=$HOME/x; gh pr comment 7 --body \"\$b\"")" = ask ]'

# Which repository's visibility counts.
reset; touch "$STUB/private"
check "a private repository is skipped, for the text and for a file" '[ -z "$(decision "gh pr comment 7 --body stubcodename")" ] && [ -z "$(decision "gh pr comment 7 --body-file word.md")" ] && [ -z "$(decision "gh pr comment 7 --body \"at $HOME/x\"")" ]'
reset; touch "$STUB/lookup_fails"
check "a failed visibility lookup counts as public" '[ "$(decision "gh pr comment 7 --body stubcodename")" = ask ]'
reset; decision "gh -R owner/named pr comment 7 --body stubcodename" >/dev/null
check "looks up the repository named by -R" 'grep -qF "repo view owner/named --json isPrivate" "$STUB/calls"'
reset; decision "gh pr comment 7 --repo=owner/named --body stubcodename" >/dev/null
check "looks up the repository named by --repo=" 'grep -qF "repo view owner/named --json isPrivate" "$STUB/calls"'
reset; decision "gh api -X POST repos/owner/named/issues/7/comments -f body=stubcodename" >/dev/null
check "looks up the repository in a gh api path" 'grep -qF "repo view owner/named --json isPrivate" "$STUB/calls"'
reset; decision "gh api -X POST repos/{owner}/{repo}/issues/7/comments -f body=stubcodename" >/dev/null
check "a gh api path with placeholders looks up the checkout" 'grep -qF "repo view --json isPrivate" "$STUB/calls"'
reset; decision "gh pr comment 7 --body \"see repos/other/name\" --body stubcodename" >/dev/null
check "a repos/ path in a body is not the target" 'grep -qF "repo view --json isPrivate" "$STUB/calls"'
reset; decision "cd $root/other && gh pr comment 7 --body stubcodename" >/dev/null
check "looks up the checkout a leading cd goes to, else the session's" 'grep -qF "$root/other: repo view --json isPrivate" "$STUB/calls"'
reset; decision "gh pr comment 7 --body stubcodename" >/dev/null
check "without a cd, looks up the checkout of the session" 'grep -qF "$root/work: repo view --json isPrivate" "$STUB/calls"'

# What the prompt says.
reset
check "the reason names the category, for a word" '[ "$(reason "gh pr comment 7 --body stubcodename")" = "Mentat: this text for a public repository holds a configured private name. Approve only if it is meant to be public." ]'
check "the reason names the category, for a path" '[ "$(reason "gh pr comment 7 --body \"at $HOME/x\"")" = "Mentat: this text for a public repository holds a local path. Approve only if it is meant to be public." ]'
check "nothing printed repeats the match" '! output "gh pr comment 7 --body \"StubCodename at $HOME/x\"" | grep -qiF -e stubcodename -e "$HOME" && ! output "gh pr comment 7 --body-file word.md" | grep -qiF stubcodename'

# A missing list never blocks, and the path check still runs.
reset; rm "$LIST"
check "a missing list: a word is no hit, the home path still is, nothing is printed about the list" '[ -z "$(output "gh pr comment 7 --body stubcodename" 2>&1)" ] && [ "$(decision "gh pr comment 7 --body \"at $HOME/x\"")" = ask ]'
reset; chmod 000 "$LIST"
check "an unreadable list: the same" '[ -z "$(output "gh pr comment 7 --body stubcodename" 2>&1)" ] && [ "$(decision "gh pr comment 7 --body \"at $HOME/x\"")" = ask ]'
chmod 600 "$LIST"
reset; : >"$LIST"
check "an empty list matches nothing" '[ -z "$(decision "gh pr comment 7 --body stubcodename")" ]'

# Missing tools.
reset
mkdir "$root/nogh"; ln -s "$(command -v jq)" "$root/nogh/jq"
json=$(jq -n '{tool_name: "Bash", tool_input: {command: "gh pr comment 7 --body stubcodename"}}')
check "does nothing without gh" '[ -z "$(PATH="$root/nogh:/bin" "$hook" <<<"$json" 2>&1)" ]'
mkdir "$root/nojq"; ln -s "$root/bin/gh" "$root/nojq/gh"
check "does nothing without jq" '[ -z "$(PATH="$root/nojq:/bin" "$hook" <<<"$json" 2>&1)" ]'
check "hooks.json runs it on PreToolUse for Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | endswith(\"/hooks/no-private-text\")] | any" "$root_dir/hooks/hooks.json" >/dev/null'

# The shared check, called directly.
reset
# shellcheck source=/dev/null
. "$root_dir/lib/publish.sh"
long=$(printf 'stubcodename %0200000d' 0)
check "a hit early in long text is found under pipefail" '[ "$(private_text "$long")" = "a configured private name" ] && [ "$(publish_hit "$long" owner/repo)" = "a configured private name" ]'
check "the home path reports its category, and a miss returns 1 and prints nothing" '[ "$(private_text "at $HOME")" = "a local path" ] && ! private_text "nothing here" >/dev/null && [ -z "$(private_text "nothing here")" ]'
reset
check "held_comment returns 1 with no hit and looks nothing up" '! held=$(held_comment "nothing here" owner/repo) && [ -z "$held" ] && ! looked_up'
reset; touch "$STUB/private"
check "held_comment leaves a private repository alone" '! held=$(held_comment "about stubcodename" owner/repo) && [ -z "$held" ]'
reset
held=$(held_comment "about StubCodename" owner/repo); kept=${held##* }
check "held_comment keeps the comment and names the file and the category, not the match" 'case "$held" in *"holds a configured private name"*) true ;; *) false ;; esac && [ "$(cat "$kept")" = "about StubCodename" ] && ! grep -qiF stubcodename <<<"$held" && [ "$(stat -f "%Lp" "$kept")" = 600 ]'

[ "$failures" -eq 0 ]
