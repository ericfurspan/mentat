#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for the mentat-public-text module's PreToolUse hook, with a temporary
# home, a stub word list and a stub gh that must never be called. Prints PASS/FAIL per
# case; exits 1 on any FAIL.
set -uo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
module="$root_dir/plugins/mentat-public-text"
hook="$module/hooks/public-text"
failures=0
check() { if eval "$2"; then printf 'PASS: public-text %s\n' "$1"; else printf 'FAIL: public-text %s\n' "$1"; failures=$((failures + 1)); fi; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOME="$root/stub home" STUB="$root/stub" TMPDIR="$root/tmp"
LIST="$HOME/.config/mentat/private-words"
mkdir -p "$STUB" "$root/bin" "$TMPDIR" "$HOME/.config/mentat" "$root/work/sub"
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/gh_calls"
echo false
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
# mcp <tool> <tool_input JSON>: prints what the hook prints for an MCP tool call.
mcp() { jq -n --arg t "$1" --argjson i "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i}' | "$hook"; }
mcp_decision() { mcp "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
word_hit="Mentat: this text for a public repository holds a configured private name, so it was not published. Take it out; if only a file's name or a leading command holds it, put the text in a file and run gh alone with --body-file."
path_hit="Mentat: this text for a public repository holds a local path, so it was not published. Take it out; if only a file's name or a leading command holds it, put the text in a file and run gh alone with --body-file."

reset
# Each listed form, with a hit in its command text.
while IFS= read -r form; do
  check "denies a word in the text: $form" '[ "$(decision "$form --body \"about stubcodename\"")" = deny ]'
  check "denies the home path in the text: $form" '[ "$(decision "$form --body \"at $HOME/x\"")" = deny ]'
  check "allows text with no hit: $form" '[ -z "$(output "$form --body \"about nothing\"")" ]'
done <<'FORMS'
gh pr create --title t
gh pr edit 7
gh pr comment 7
gh pr review 7 --comment
gh issue create --title t
gh issue edit 7
gh issue comment 7
gh -R owner/repo pr comment 7
gh api -X POST repos/o/r/issues/7/comments
gh api --method=PATCH repos/o/r/issues/7
gh api repos/o/r/issues/7/comments -f body=x
FORMS
check "denies a word in a heredoc body" '[ "$(decision "gh pr create --title t --body \"\$(cat <<EOF
Line one
about StubCodename
EOF
)\"")" = deny ]'
check "denies a word starting with a dash, one with a space, and a last line with no newline" '[ "$(decision "gh pr comment 7 --body \"a -DASHWORD b\"")" = deny ] && [ "$(decision "gh pr comment 7 --body \"Two Words\"")" = deny ] && [ "$(decision "gh pr comment 7 --body LASTWORD")" = deny ]'

# Home paths written out, by any name.
while IFS= read -r p; do
  check "denies a home path written out: $p" '[ "$(reason "gh pr comment 7 --body \"see $p\"")" = "$path_hit" ]'
done <<'PATHS'
/Users/stubperson/notes.md
/home/stubperson/notes.md
(/Users/stub.person/x)
/Users/username2/x
/home/runners/x
/Users/Shared2/x
see /Users/Shared/x and /Users/stubperson/x
PATHS
# ~/, a shared folder, a CI runner's home and a placeholder name name no person.
while IFS= read -r p; do
  check "allows text that only looks like a home path: $p" '[ -z "$(output "gh pr comment 7 --body \"see $p\"")" ]'
done <<'NOTPATHS'
/Users/<name>/
https://example.com/home/stubpage/
/Users
a~/b
~/notes.md
~/.config/mentat/private-words
/home/runner/work/repo
/Users/Shared/x
/Users/you/x
/home/me/x
/Users/user/x
/home/username/x
/Users/name/x
/Users/you/ and /home/runner/ and /Users/Shared/
NOTPATHS
check "allows a git -C ~/ command before gh when nothing else hits" '[ -z "$(output "git -C ~/x push && gh pr create --body ok")" ]'

# Commands that publish nothing, or are not listed, and other tools.
while IFS= read -r cmd; do
  check "allows a hit outside the listed writes: $cmd" '[ -z "$(output "$cmd")" ]'
done <<'PASS'
gh pr view 7 --json title --jq stubcodename
gh pr list --search stubcodename
gh api repos/o/r/issues --jq stubcodename
gh api -X GET search/issues -f q=stubcodename
gh api repos/o/r/x -f q=stubcodename -X GET
echo stubcodename
grep stubcodename README
git commit -m stubcodename
PASS
check "a blank line and a comment in the list match nothing" '[ -z "$(decision "gh pr comment 7 --body \"about commentword\"")" ] && [ -z "$(decision "gh pr comment 7 --body \"# a b\"")" ]'
other_tool() { jq -n '{tool_name: "Read", tool_input: {command: "gh pr comment 7 --body stubcodename", file_path: "/Users/stubperson/x"}}' | "$hook" 2>&1; }
check "an unrelated tool is allowed with no output" '[ -z "$(other_tool)" ]'

# Files the command names: their text is published, their names are not.
printf 'about StubCodename\n' >"$root/work/word.md"
printf 'from /Users/stubperson/x\n' >"$root/work/path.md"
printf 'clean\n' >"$root/work/clean.md"
cp "$root/work/clean.md" "$HOME/clean.md"
cp "$root/work/word.md" "$root/work/sub/word.md"
while IFS= read -r cmd; do
  check "denies a hit in a file: $cmd" '[ "$(decision "$cmd")" = deny ]'
done <<'FILES'
gh pr create --body-file word.md
gh pr create --body-file=word.md
gh pr comment 7 -F word.md
gh pr create --body-file path.md
gh pr edit 7 --notes-file word.md
gh api repos/o/r/issues/7/comments -F body=@word.md
gh api repos/o/r/issues/7/comments --field=body=@word.md
cd sub && gh pr comment 7 --body-file word.md
FILES
check "allows a clean file named under the home folder, as the path, ~/ or \$HOME/" '[ -z "$(output "gh pr comment 7 --body-file \"$HOME/clean.md\"")" ] && [ -z "$(output "gh pr comment 7 --body-file ~/clean.md")" ] && [ -z "$(output "gh pr comment 7 --body-file \$HOME/clean.md")" ]'
mkdir -p "$HOME/repo"; cp "$root/work/clean.md" "$HOME/repo/clean.md"
check "allows a leading cd under the home folder, and reads a relative file from there" '[ -z "$(output "cd \"$HOME/repo\" && gh pr comment 7 --body-file clean.md")" ] && [ -z "$(output "cd ~/repo && gh pr create --body ok")" ]'
check "denies a hit after a leading cd" '[ "$(decision "cd \"$HOME/repo\" && gh pr comment 7 --body \"at $HOME/x\"")" = deny ]'
tdir="$TMPDIR/StubCodename"
mkdir -p "$tdir"; cp "$root/work/clean.md" "$tdir/pr.md"
while IFS= read -r c; do
  check "allows a temp path holding a word that only locates a clean file: $c" '[ -z "$(output "$c")" ]'
done <<EOF
gh pr edit 1 --body-file $tdir/pr.md
S=$tdir; gh pr edit 1 --body-file \$S/pr.md
sed -i '' 's/a/b/' $tdir/pr.md; gh pr edit 1 --body-file $tdir/pr.md
printf x > $tdir/out.md && gh pr edit 1 --body-file $tdir/pr.md
EOF
check "denies a temp path holding a word when it is published" '[ "$(decision "S=$tdir; gh pr edit 1 --body \"see \$S\"")" = deny ]'

# The word list.
reset; rm "$LIST"
check "a missing list: a word is allowed with no output, a home path is still denied" '[ -z "$(output "gh pr comment 7 --body stubcodename" 2>&1)" ] && [ "$(decision "gh pr comment 7 --body \"at /Users/stubperson/x\"")" = deny ]'
reset; : >"$LIST"
check "an empty list: a word is allowed, a home path is still denied" '[ -z "$(output "gh pr comment 7 --body stubcodename" 2>&1)" ] && [ "$(decision "gh pr comment 7 --body \"at /home/stubperson/x\"")" = deny ]'
reset; printf 'exact:StubExact\n' >"$LIST"
check "a marked entry is denied only in its case and as a whole word" '[ "$(decision "gh pr comment 7 --body \"about StubExact\"")" = deny ] && [ -z "$(decision "gh pr comment 7 --body \"about stubexact\"")" ] && [ -z "$(decision "gh pr comment 7 --body \"about StubExacts\"")" ]'
reset
long=$(printf 'stubcodename\n%0100000d\n%0100000d' 0 0)
check "a hit early in long text is denied under pipefail" '[ "$(decision "gh pr comment 7 --body \"$long\"")" = deny ]'

# GitHub MCP writes: every text value but owner and repo.
reset
word_body='{"owner": "o", "repo": "r", "body": "about stubcodename"}'
clean_body='{"owner": "o", "repo": "r", "body": "about nothing"}'
nested_path='{"title": "t", "issue_fields": [{"value": "see /home/stubperson/x"}]}'
owner_repo='{"owner": "stubcodename", "repo": "stubcodename", "body": "ok"}'
mcp_tools="add_comment_to_pending_review add_issue_comment add_reply_to_pull_request_comment create_gist create_issue create_or_update_file create_pull_request create_pull_request_review create_pull_request_with_copilot create_repository discussion_comment_write issue_write merge_pull_request pull_request_review_write push_files sub_issue_write submit_pending_pull_request_review update_gist update_issue update_issue_comment update_pull_request"
for t in $mcp_tools; do
  check "denies a word in the MCP tool $t" '[ "$(mcp_decision "mcp__github__$t" "$word_body")" = deny ]'
  check "allows clean text in the MCP tool $t" '[ -z "$(mcp "mcp__github__$t" "$clean_body")" ]'
done
check "denies a home path in any MCP text value, nested ones too" '[ "$(mcp_decision mcp__plugin_x_github__issue_write "$nested_path")" = deny ]'
check "allows a listed word that is only the MCP owner or repo" '[ -z "$(mcp mcp__github__add_issue_comment "$owner_repo")" ]'
check "allows an MCP tool that publishes nothing" '[ -z "$(mcp mcp__github__issue_read "$word_body")" ]'

# What it prints: a deny with the category, never an ask, never the match.
reset
check "the reason names the category, for a word" '[ "$(reason "gh pr comment 7 --body stubcodename")" = "$word_hit" ]'
check "the reason names the category, for a path" '[ "$(reason "gh pr comment 7 --body \"at $HOME/x\"")" = "$path_hit" ]'
check "the output is a PreToolUse deny" 'output "gh pr comment 7 --body stubcodename" | jq -e ".hookSpecificOutput.hookEventName == \"PreToolUse\" and .hookSpecificOutput.permissionDecision == \"deny\"" >/dev/null'
check "nothing printed repeats the match" '! output "gh pr comment 7 --body \"StubCodename at /Users/stubperson/x\"" | grep -qiF -e stubcodename -e stubperson && ! output "gh pr comment 7 --body-file word.md" | grep -qiF stubcodename'
check "never looks up the repository" '[ ! -f "$STUB/gh_calls" ]'
check "the hook never asks" '! grep -q "\"ask\"" "$hook"'

# Input it cannot read is allowed, with a note on stderr.
note() { printf '%s' "$1" | "$hook" 2>"$STUB/err"; }
while IFS= read -r bad; do
  check "allows malformed input with a note and no decision: $bad" 'out=$(note "$bad"); rc=$?; [ "$rc" = 0 ] && [ -z "$out" ] && grep -q "^mentat-public-text: .*allowed unchecked" "$STUB/err"'
done <<'BAD'
not json
{"tool_name": "Bash", "tool_input":
[1, 2]
"gh pr comment 7 --body stubcodename"
BAD
check "allows empty input with no output" 'out=$(printf "" | "$hook" 2>&1); [ $? = 0 ] && [ -z "$out" ]'
mkdir "$root/nojq"; ln -s "$root/bin/gh" "$root/nojq/gh"
json=$(jq -n '{tool_name: "Bash", tool_input: {command: "gh pr comment 7 --body stubcodename"}}')
check "allows without jq, with a note" 'out=$(PATH="$root/nojq:/bin" "$hook" <<<"$json" 2>"$STUB/err"); [ $? = 0 ] && [ -z "$out" ] && grep -q "jq is not installed" "$STUB/err"'

# The wiring: Bash and the listed MCP tools, from any server name, run the hook.
hooks="$module/hooks/hooks.json"
check "hooks.json runs it on PreToolUse for Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | endswith(\"/hooks/public-text\")] | any" "$hooks" >/dev/null'
mcp_matches() { jq -e --arg t "$1" '[.hooks.PreToolUse[] | select(.matcher != "Bash") | select(.hooks | map(.command | endswith("/hooks/public-text")) | any) | .matcher as $m | $t | test($m)] | any' "$hooks" >/dev/null; }
for t in $mcp_tools; do
  check "hooks.json runs it for $t from any MCP server" 'mcp_matches "mcp__github__$t" && mcp_matches "mcp__plugin_x_github__$t"'
done
check "hooks.json does not run it for MCP reads or lookalike names" '! mcp_matches mcp__github__issue_read && ! mcp_matches mcp__github__create_pull_request_x && ! mcp_matches create_pull_request'
check "hooks.json never blocks a call when the hook fails" '! jq -e "[.. | objects | select(has(\"onFailure\"))] | any" "$hooks" >/dev/null'

[ "$failures" -eq 0 ]
