#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-commit-secrets, the PreToolUse hook, with a stub
# gitleaks. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-commit-secrets"
failures=0
check() { if eval "$2"; then printf 'PASS: no-commit-secrets %s\n' "$1"; else printf 'FAIL: no-commit-secrets %s\n' "$1"; failures=$((failures + 1)); fi; }

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
printf 'clean\n' >"$repo/clean.txt"
g -C "$repo" add -A
g -C "$repo" commit -q -m first
reset() { rm -f "$STUB"/*; g -C "$repo" reset -q --hard; g -C "$repo" clean -q -fdx; }

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

# A command that stages in the same call is scanned for what its commit would include.
hit() { printf 'a\ntoken = stubmatchedtext\n' >"$1"; }
fine() { printf 'fine\n' >"$1"; }
scanned() { quiet && [ -s "$STUB/calls" ]; }
has() { grep -q "^+++ b/$1" "$STUB/stdin"; }
names() { [ "$(decision)" = ask ] && reason | grep -qF "stub-rule in $1"; }
sim_failed() { [ "$(decision)" = ask ] && reason | grep -q "could not be worked out" && ! reason | grep -q stub-rule && no_leak; }

reset; hit "$repo/dir one/file two.txt"; run "$repo" 'git add "dir one/file two.txt" && git commit -m x'
check "git add <path> then commit scans the path it stages" 'names "dir one/file two.txt" && reason | grep -q "changes this commit would include" && no_leak'
reset; hit "$repo/new.txt"; run "$repo" 'git add -A && git commit -m x'
check "git add -A then commit scans an untracked file" 'names new.txt'
reset; printf 'secret.txt\n' >"$repo/.gitignore"; hit "$repo/secret.txt"; run "$repo" 'git add -A && git commit -m x'
check "git add -A leaves an ignored file out" 'scanned && has .gitignore && ! has secret.txt'
reset; fine "$repo/new.txt"; run "$repo" 'git add -A && git commit -m x && git push origin HEAD 2>&1 | tail -n 3'
check "steps after the commit are not read as its paths" 'scanned && has new.txt'
reset; hit "$repo/new.txt"; run "$base" "git -C '$repo' add -A && git -C '$repo' commit -m x"
check "git -C add and commit scan the repository they name" 'names new.txt'

reset; hit "$repo/top.txt"; fine "$repo/dir one/new.txt"
run "$base" "cd '$repo/dir one' && git add . && git commit -m x"
check "git add . from a subfolder leaves a change outside it out" 'scanned && has "dir one/new.txt" && ! has top.txt'
run "$repo/dir one" 'git add . && git commit -m x'
check "git add . with the session in a subfolder leaves a change outside it out" 'scanned && has "dir one/new.txt" && ! has top.txt'
run "$repo" "git status && cd 'dir one' && git add . && git commit -m x"
check "a cd between steps moves the folder of the add after it" 'scanned && has "dir one/new.txt" && ! has top.txt'
run "$repo" "git -C 'dir one' add . && git commit -m x"
check "git -C <dir> add . covers that folder only" 'scanned && has "dir one/new.txt" && ! has top.txt'
run "$base" "cd '$repo/dir one' && git add -A && git commit -m x"
check "git add -A from a subfolder covers the whole tree" 'names top.txt'
reset; hit "$repo/dir one/new.txt"; run "$base" "cd '$repo/dir one' && git add . && git commit -m x"
check "git add . from a subfolder scans that subfolder" 'names "dir one/new.txt"'
reset; hit "$repo/dir one/new.txt"; run "$repo/dir one" 'git add new.txt && git commit -m x'
check "a relative add path resolves from the session's folder" 'names "dir one/new.txt"'

for c in 'git commit -am "msg"' 'git commit -a -m x' 'git commit --all -m x'; do
  reset; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" "$c"
  check "$c scans a changed tracked file" 'names clean.txt'
done
reset; fine "$repo/clean.txt"; hit "$repo/new.txt"; run "$repo" 'git commit -a -m x'
check "git commit -a leaves an untracked file out" 'scanned && has clean.txt && ! has new.txt'

reset; fine "$repo/clean.txt"; g -C "$repo" add clean.txt; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"
run "$repo" 'git commit -m x'
check "a clean staged version passes while the working version has a hit" 'scanned && has clean.txt'
run "$repo" 'git commit -a -m x'
check "git commit -a scans the working version over the staged one" 'names clean.txt'
reset; hit "$repo/clean.txt"; g -C "$repo" add clean.txt; fine "$repo/clean.txt"
run "$repo" 'git commit -a -m x'
check "git commit -a commits the clean working version over a staged hit" 'scanned && has clean.txt'

reset; stage_hit; fine "$repo/clean.txt"; run "$repo" 'git commit -m x clean.txt'
check "a commit naming paths leaves other staged changes out" 'scanned && has clean.txt && ! has "dir one/file two.txt"'
reset; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" 'git commit -m x clean.txt'
check "a commit naming paths scans their working versions" 'names clean.txt'
reset; stage_hit; fine "$repo/clean.txt"; run "$repo" 'git commit -i -m x clean.txt'
check "git commit -i with paths keeps the staged changes" 'names "dir one/file two.txt"'
reset; hit "$repo/new.txt"; g -C "$repo" add new.txt; run "$repo" 'git commit -m x -- new.txt'
check "a commit naming a newly staged file scans it" 'names new.txt'

for c in 'git commit --amend -m x' 'git commit --allow-empty -m x' 'git commit --author "A <a@b>" -m x'; do
  reset; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" "$c"
  check "$c is not read as -a" 'quiet && [ ! -f "$STUB/calls" ]'
done

IFS= read -r -d '' msg <<'MSGEOF' || true
git commit -m "$(cat <<'EOF'
fix: the -a flag (and clean.txt)

Steps: 1) run "git commit -a" -- clean.txt, don't stage it
EOF
)"
MSGEOF
msg=${msg%$'\n'}
reset; fine "$repo/new.txt"; run "$repo" "git add -A && $msg"
check "git add -A then a heredoc message commit passes when clean" 'scanned && has new.txt'
reset; hit "$repo/new.txt"; run "$repo" "git add -A && $msg"
check "git add -A then a heredoc message commit scans what it stages" 'names new.txt'
reset; fine "$repo/new.txt"; g -C "$repo" add new.txt; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" "$msg"
check "words in a heredoc commit message are not read as flags or paths" 'scanned && has new.txt && ! has clean.txt'
reset; fine "$repo/new.txt"; g -C "$repo" add new.txt; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" 'git commit -m "fix -a clean.txt" -n'
check "a -m message is not read as flags or paths" 'scanned && has new.txt && ! has clean.txt'

reset; hit "$repo/new.txt"; run "$repo" 'git add "$f" && git commit -m x'
check "an add word that cannot be read asks as a failed simulation" 'sim_failed'
reset; hit "$repo/new.txt"; run "$repo" 'git add nothere.txt && git commit -m x'
check "an add that git rejects asks as a failed simulation" 'sim_failed'
for c in 'git commit -m x -- "$file"' 'git commit -m x "$file"' 'git commit -m x "$flag"' 'git commit -n"$x" -m x'; do
  reset; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" "$c"
  check "$c asks as a failed simulation" 'sim_failed'
done
for c in 'git commit -m "$msg"' 'git commit -m"$msg"' 'git commit --message="$msg"' 'git commit -F "$f"'; do
  reset; fine "$repo/new.txt"; g -C "$repo" add new.txt; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" "$c"
  check "$c takes the unread word as its value" 'scanned && has new.txt && ! has clean.txt'
done
reset; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"; run "$repo" 'git commit -am"$msg"'
check "git commit -am\"\$msg\" scans a changed tracked file" 'names clean.txt'

reset; hit "$repo/new.txt"; printf 'token = stubmatchedtext\n' >>"$repo/clean.txt"
for c in 'git add -p && git commit -m x' 'git rm -q "dir one/kept.txt" && git commit -m x' 'git mv clean.txt moved.txt && git commit -m x'; do
  rm -f "$STUB"/*; run "$repo" "$c"
  check "$c keeps the staged-only scan" 'quiet && [ ! -f "$STUB/calls" ]'
done

fresh="$tmp/fresh repo"
g init -q "$fresh"
hit "$fresh/new.txt"; rm -f "$STUB"/*; run "$fresh" 'git add -A && git commit -m x'
check "with no commits yet, git add -A then commit scans what it stages" 'names new.txt'
fine "$fresh/new.txt"; rm -f "$STUB"/*; run "$fresh" 'git add -A && git commit -m x'
check "with no commits yet, a clean add passes" 'scanned && has new.txt'
hit "$fresh/new.txt"; g -C "$fresh" add new.txt; rm -f "$STUB"/*; run "$fresh" 'git commit -m x new.txt'
check "with no commits yet, a commit naming paths scans them" 'names new.txt'

# snap <git dir> <index>: the index checksum, any lock, and the object files. Each
# case writes content no earlier case stored, so a write to the real store shows.
snap() { shasum "$2"; ls "$2.lock" 2>&1; (cd "$1/objects" && find . -type f | sort); }
reset; printf 'only here 1\ntoken = stubmatchedtext\n' >"$repo/new.txt"; printf 'only here 2\n' >>"$repo/clean.txt"
before=$(snap "$repo/.git" "$repo/.git/index")
run "$repo" 'git add -A && git commit -a -m x'
after=$(snap "$repo/.git" "$repo/.git/index")
check "a simulated run leaves the real index and object store unchanged" 'names new.txt && [ "$before" = "$after" ]'
check "a simulated run leaves no temporary files" '[ -z "$(ls -A "$TMPDIR")" ]'
reset; g -C "$repo" worktree add -q "$tmp/wt" -b wt
printf 'only here 3\ntoken = stubmatchedtext\n' >"$tmp/wt/new.txt"; wtindex=$(g -C "$tmp/wt" rev-parse --path-format=absolute --git-path index)
before=$(snap "$repo/.git" "$wtindex")
run "$tmp/wt" 'git add -A && git commit -m x'
after=$(snap "$repo/.git" "$wtindex")
check "in a worktree it scans what the commit stages and changes no real index or object" 'names new.txt && [ "$before" = "$after" ]'
g -C "$repo" worktree remove --force "$tmp/wt"

# Without gitleaks the hook does nothing.
mkdir "$tmp/nogitleaks"; for t in git jq; do ln -s "$(command -v $t)" "$tmp/nogitleaks/$t"; done
reset; stage_hit
rc=$(jq -n --arg d "$repo" '{tool_name: "Bash", cwd: $d, tool_input: {command: "git commit -m x"}}' |
  PATH="$tmp/nogitleaks:/usr/bin:/bin" "$hook" >"$STUB/out" 2>&1; echo $?)
check "with gitleaks missing it does nothing" 'quiet'

check "hooks.json runs it on PreToolUse for Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | select(endswith(\"/hooks/no-commit-secrets\"))] | length == 1" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
