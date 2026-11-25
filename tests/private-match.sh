#!/usr/bin/env bash
# The publish check's matcher (private_text in lib/publish.sh) and the mentat-public-text
# module's hook, run over the same text with a temporary home and a stub word list. Each
# row gives the outcome expected from each side: a local path, a private name or none.
# Rows where the two differ name the deliberate difference; any other drift fails. The
# hook is run through its MCP route, which passes the text straight to its matcher.
# Prints PASS/FAIL per row; exits 1 on any FAIL.
set -uo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root_dir/plugins/mentat-public-text/hooks/public-text"
failures=0

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOME="$root/stub home"
mkdir -p "$HOME/.config/mentat"
printf '# stubcommentword\n\nStubPlainWord\nexact:StubExactWord\n' >"$HOME/.config/mentat/private-words"

# shellcheck source=/dev/null
. "$root_dir/lib/publish.sh"

# outcome <category>: path, name or none, from a matcher's category text.
outcome() {
  case "$1" in
    "") echo none ;;
    *"a local path"*) echo path ;;
    *"a configured private name"*) echo name ;;
    *) echo "unexpected: $1" ;;
  esac
}
publish_side() { outcome "$(private_text "$1")"; }
# The hook's reason, or what it wrote on stderr when it let the call through unchecked.
hook_side() {
  local out
  out=$(jq -n --arg b "$1" '{hook_event_name: "PreToolUse", tool_name: "mcp__github__add_issue_comment",
    tool_input: {owner: "stubowner", repo: "stubrepo", issue_number: 1, body: $b}}' | "$hook" 2>&1)
  case "$out" in
    "" | "{"*) outcome "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)" ;;
    *) echo "unchecked: $out" ;;
  esac
}
# row <label> <publish expects> <hook expects> <text>
row() {
  local p h
  p=$(publish_side "$4") h=$(hook_side "$4")
  if [ "$p" = "$2" ] && [ "$h" = "$3" ]; then
    printf 'PASS: private-match %s\n' "$1"
  else
    printf 'FAIL: private-match %s: publish %s (expected %s), hook %s (expected %s)\n' "$1" "$p" "$2" "$h" "$3"
    failures=$((failures + 1))
  fi
}

row "this home as a whole path" path path "notes at $HOME/notes.md"
row "this home as the whole text" path path "$HOME"
row "this home in another case" path path "notes at $(printf '%s' "$HOME" | tr '[:lower:]' '[:upper:]')/notes.md"
row "this home followed by a dash" path path "notes at $HOME-old/notes.md"
row "this home with more name after it (deliberate: publish matches this home as an unanchored substring, the hook as a bounded path)" path none "notes at ${HOME}x/notes.md"
row "this home inside a longer path (deliberate: publish matches this home as an unanchored substring, the hook as a bounded path)" path none "notes at /backup$HOME/notes.md"
row "another user's home (deliberate: publish matches only this machine's home)" none path "notes at /Users/stubperson/notes.md"
row "another user's Linux home (deliberate: publish matches only this machine's home)" none path "notes at /home/stubperson/notes.md"
row "a placeholder home" none none "see /Users/you/notes.md and /home/runner/work"
row "a shared folder" none none "see /Users/Shared/notes.md"
row "an exact: word in its case" name name "about StubExactWord here"
row "an exact: word in another case" none none "about stubexactword here"
row "an exact: word inside a longer word" none none "about StubExactWordy here"
row "a plain word in its case" name name "about StubPlainWord here"
row "a plain word in another case" name name "about STUBPLAINWORD here"
row "a plain word inside a longer word" name name "about xstubplainwordx here"
row "a word only on a # line" none none "about stubcommentword here"
row "text with no hit" none none "about nothing here"

[ "$failures" = 0 ]
