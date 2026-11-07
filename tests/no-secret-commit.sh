#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-secret-commit, the PreToolUse hook, with a stub
# gitleaks. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-secret-commit"
failures=0
check() { if eval "$2"; then printf 'PASS: no-secret-commit %s\n' "$1"; else printf 'FAIL: no-secret-commit %s\n' "$1"; failures=$((failures + 1)); fi; }

base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
tmp="$base/with space"
export STUB="$tmp/stub"
mkdir -p "$STUB" "$tmp/bin" "$tmp/tmpdir"

# gitleaks: records its arguments and stdin, prints text that must never reach the
# output, and writes a JSON report to --report-path. Each stdin line holding
# stubmatchedtext is a finding of stub-rule, its Secret left unredacted. Exits with
# --exit-code on a finding, else 0. $STUB/error: fails with no report.
# $STUB/bad_report: a finding with a report that is not JSON.
cat >"$tmp/bin/gitleaks" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
cat >"$STUB/stdin"
echo "stubgitleaksoutput stubmatchedtext"
echo "stubgitleaksoutput stubmatchedtext" >&2
report="" code=1
while [ $# -gt 0 ]; do
  case "$1" in
    --report-path) report=$2; shift ;;
    --exit-code) code=$2; shift ;;
  esac
  shift
done
[ ! -f "$STUB/error" ] || exit 1
if [ -f "$STUB/bad_report" ]; then echo "stubmatchedtext" >"$report"; exit "$code"; fi
lines=$(grep -n stubmatchedtext "$STUB/stdin" | cut -d: -f1)
if [ -z "$lines" ]; then echo '[]' >"$report"; exit 0; fi
printf '%s\n' "$lines" | jq -R 'tonumber | {RuleID: "stub-rule", StartLine: ., File: "", Secret: "stubmatchedtext", Match: "token = stubmatchedtext"}' | jq -s . >"$report"
exit "$code"
STUBEOF
chmod +x "$tmp/bin/gitleaks"
export PATH="$tmp/bin:$PATH"
export TMPDIR="$tmp/tmpdir"

g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
repo="$tmp/repo"
g init -q "$repo"
mkdir -p "$repo/dir one"
printf 'one\ntoken = stubmatchedtext\n' >"$repo/dir one/kept.txt"
g -C "$repo" add -A
g -C "$repo" commit -q -m first
reset() { rm -f "$STUB"/*; g -C "$repo" reset -q --hard; g -C "$repo" clean -q -fd; }

# run <cwd> <command>: the hook's output in $STUB/out, its exit code in $rc
run() {
  jq -n --arg d "$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' |
    "$hook" >"$STUB/out" 2>&1
  rc=$?
}
decision() { jq -r '.hookSpecificOutput.permissionDecision // empty' "$STUB/out" 2>/dev/null; }
reason() { jq -r '.hookSpecificOutput.permissionDecisionReason // empty' "$STUB/out" 2>/dev/null; }
no_leak() { ! grep -q -e stubmatchedtext -e stubgitleaksoutput "$STUB/out"; }
quiet() { [ "$rc" = 0 ] && [ ! -s "$STUB/out" ]; }
stage_hit() { printf 'a\ntoken = stubmatchedtext\n' >"$repo/dir one/file two.txt"; g -C "$repo" add -A; }
stage_clean() { printf 'nothing to see\n' >"$repo/dir one/file two.txt"; g -C "$repo" add -A; }

reset; stage_hit; run "$repo" 'git commit -m "add file"'
check "a hit asks" '[ "$(decision)" = ask ]'
check "a hit names the rule and the file" 'reason | grep -qF "stub-rule in dir one/file two.txt"'
check "a hit never shows the matched text or gitleaks output" 'no_leak'
check "runs gitleaks on stdin with redaction and a JSON report" 'grep -q "^stdin .*--redact" "$STUB/calls" && grep -q -- "--report-format json" "$STUB/calls"'
check "pipes the staged diff into gitleaks" 'grep -qx "+++ b/dir one/file two.txt.*" "$STUB/stdin"'
check "leaves no temporary files" '[ -z "$(ls -A "$TMPDIR")" ]'

reset; stage_clean; run "$repo" 'git commit -m "add file"'
check "a clean diff passes" 'quiet && [ -s "$STUB/calls" ]'

reset; stage_hit; touch "$STUB/error"; run "$repo" 'git commit -m "add file"'
check "a gitleaks error asks as a failed scan, not a finding" '[ "$(decision)" = ask ] && reason | grep -q "scan of the staged changes failed" && ! reason | grep -q stub-rule'
check "a gitleaks error never shows the matched text or gitleaks output" 'no_leak'
reset; stage_hit; touch "$STUB/bad_report"; run "$repo" 'git commit -m "add file"'
check "an unreadable report asks as a failed scan" '[ "$(decision)" = ask ] && reason | grep -q "scan of the staged changes failed" && no_leak'

reset; g -C "$repo" rm -q "dir one/kept.txt"; run "$repo" 'git commit -m "remove it"'
check "a removed line with a finding passes" 'quiet && [ -s "$STUB/calls" ]'

reset; stage_hit; run "$base" "git -C \"$repo\" commit -m x"
check "git -C scans the repository it names" '[ "$(decision)" = ask ] && reason | grep -qF "dir one/file two.txt"'
reset; stage_hit; run "$base" "cd '$repo/dir one' && git commit -m x"
check "a leading cd scans the repository it enters" '[ "$(decision)" = ask ] && reason | grep -qF "dir one/file two.txt"'

reset; run "$repo" 'git commit -m "empty"'
check "nothing staged passes without a scan" 'quiet && [ ! -f "$STUB/calls" ]'
reset; stage_hit; run "$repo" 'git status && echo "no commit yet"'
check "a command that is not a commit is left alone" 'quiet && [ ! -f "$STUB/calls" ]'

# Without gitleaks the hook does nothing.
mkdir "$tmp/nogitleaks"; for t in git jq; do ln -s "$(command -v $t)" "$tmp/nogitleaks/$t"; done
reset; stage_hit
rc=$(jq -n --arg d "$repo" '{tool_name: "Bash", cwd: $d, tool_input: {command: "git commit -m x"}}' |
  PATH="$tmp/nogitleaks:/usr/bin:/bin" "$hook" >"$STUB/out" 2>&1; echo $?)
check "with gitleaks missing it does nothing" 'quiet'

check "hooks.json runs it on PreToolUse for Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | select(endswith(\"/hooks/no-secret-commit\"))] | length == 1" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
