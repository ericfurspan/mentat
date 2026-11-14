#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat review` and `mentat review --local`, the Claude review,
# using a real git origin, a stub gh and a stub claude. Prints PASS/FAIL per case;
# exits 1 on any FAIL. tests/review-codex.sh covers `mentat review --codex`.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
# A temporary home: the publish check reads the home path and the word list from it.
export HOME="$root/home"
# Kept logs and held comments, and the folders the start sweep reads, are the test's own.
export TMPDIR="$root/tmp" XDG_CACHE_HOME="$root/cache"
LIST="$HOME/.config/mentat/private-words"
mkdir -p "$STUB" "$root/tools/bin" "$(dirname "$LIST")" "$TMPDIR"
failures=0
check() { if eval "$2"; then printf 'PASS: review --local %s\n' "$1"; else printf 'FAIL: review --local %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset MENTAT_REVIEW_MODEL MENTAT_REVIEW_TIMEOUT_SECONDS

# An origin with main and pull request 7, whose head changes README.
git init -q --bare -b main "$root/origin.git"
git init -q -b main "$root/seed"
(cd "$root/seed" && echo base >README && git add README && git commit -qm base && git push -q "$root/origin.git" main &&
  git checkout -qb feature && echo change >README && git commit -qam change && git push -q "$root/origin.git" HEAD:refs/pull/7/head)
H=$(git -C "$root/seed" rev-parse feature)
BASE=$(git -C "$root/seed" rev-parse main)
git clone -q "$root/origin.git" "$root/work"
# A dirty working tree that must not be what gets reviewed.
echo dirty >"$root/work/README"

# gh: pr view serves $STUB/head (moved_head replaces it after the first read);
# check runs come from $STUB/check_runs.json (check_runs_later.json from the second
# read on), and a file named push_on_ci holds a head to switch to when CI is read;
# pr comment records the body, or fails when comment_fails exists, and adds it to
# the comments mentat status reads, as this account's.
cat >"$root/tools/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "pr view")
    n=$(($(cat "$STUB/head_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/head_reads"
    h=$(cat "$STUB/head"); [ "$n" -gt 1 ] && [ -f "$STUB/moved_head" ] && h=$(cat "$STUB/moved_head")
    case "$*" in
      *--jq*) echo "$h" ;;
      *) jq -n --arg h "$h" --argjson c "$(cat "$STUB/closes" 2>/dev/null || echo '[]')" '{headRefOid: $h, baseRefName: "main", title: "Change README", body: "Requirement: README says change.", closingIssuesReferences: $c}' ;;
    esac ;;
  "repo view")
    case "$*" in
      *isPrivate*) [ -f "$STUB/lookup_fails" ] && exit 1; if [ -f "$STUB/private" ]; then echo true; else echo false; fi ;;
      *) echo owner/repo ;;
    esac ;;
  "issue view")
    r=$5; f="$STUB/issue_${r/\//_}_$3"
    [ "$4" = --repo ] && [ -f "$f" ] || exit 1
    printf 'Issue %s#%s: %s\n\n%s' "$r" "$3" "$(head -1 "$f")" "$(tail -n +2 "$f")" ;;
  "api --paginate")
    case "$3" in
      */check-runs)
        n=$(($(cat "$STUB/ci_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/ci_reads"
        [ -f "$STUB/push_on_ci" ] && cp "$STUB/push_on_ci" "$STUB/head"
        if [ "$n" -ge 2 ] && [ -f "$STUB/check_runs_later.json" ]; then cat "$STUB/check_runs_later.json"; else cat "$STUB/check_runs.json"; fi ;;
      */comments) cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]' ;;
      *) exit 99 ;;
    esac ;;
  "api user") echo agent-bot ;;
  "pr comment")
    [ -f "$STUB/comment_fails" ] && exit 1
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$STUB/comment"; shift; done
    jq --rawfile b "$STUB/comment" '. + [{user: {login: "agent-bot"}, body: $b}]' <<<"$(cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]')" >"$STUB/ic.tmp" && mv "$STUB/ic.tmp" "$STUB/issue_comments.json"
    echo https://example.test/comment ;;
  *) exit 99 ;;
esac
STUBEOF
# claude: records its arguments, where it ran, what it read on stdin and in the folder
# after --add-dir, and its run in the calls gh records. Then prints Claude's JSON result
# with $STUB/reply as the reply, $STUB/model_ran as the models that ran (comma-separated,
# default claude-opus-4-9), $STUB/subtype and $STUB/denials; or $STUB/raw as it is.
# Exits with $STUB/exit (default 0).
cat >"$root/tools/bin/claude" <<'STUBEOF'
#!/usr/bin/env bash
[ "$*" = --version ] && { echo "2.1.322 (Claude Code)"; exit 0; }
echo claude >>"$STUB/calls"
printf '%s\n' "$@" >"$STUB/args"
cat >"$STUB/prompt"
git rev-parse HEAD >"$STUB/model_head"; cat README >"$STUB/model_readme"
# @TREE@, @TREEP@ and @DATA@ in the reply become the checkout's path as created and
# resolved (macOS: /var and /private/var) and the data folder's.
pwd >"$STUB/tree"; pwd -P >"$STUB/treep"
prev=""
for a in "$@"; do
  if [ "$prev" = --add-dir ]; then printf '%s\n' "$a" >"$STUB/data"; cp "$a/diff" "$STUB/seen_diff"; cp "$a/log" "$STUB/seen_log"; fi
  prev=$a
done
[ -f "$STUB/hang" ] && { echo $$ >"$STUB/model_pid"; exec sleep 30; }
rc=$(cat "$STUB/exit" 2>/dev/null || echo 0)
[ -f "$STUB/raw" ] && { cat "$STUB/raw"; exit "$rc"; }
reply=$(sed -e "s|@TREE@|$(pwd)|g" -e "s|@TREEP@|$(pwd -P)|g" -e "s|@DATA@|$(cat "$STUB/data")|g" "$STUB/reply")
jq -n --arg r "$reply" --arg m "$(cat "$STUB/model_ran" 2>/dev/null || echo claude-opus-4-9)" --arg s "$(cat "$STUB/subtype" 2>/dev/null || echo success)" \
  --argjson d "$(cat "$STUB/denials" 2>/dev/null || echo '[]')" \
  '{type: "result", subtype: $s, is_error: false, result: $r, permission_denials: $d, modelUsage: ($m | split(",") | map({key: ., value: {}}) | from_entries)}'
exit "$rc"
STUBEOF
chmod +x "$root/tools/bin/gh" "$root/tools/bin/claude"
# CI waits are short, as in tests/review.sh; a passed check with no finish time returns at once.
export PATH="$root/tools/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_CI_TIMEOUT_SECONDS=2 MENTAT_CI_GRACE_SECONDS=1

reset() {
  rm -f "$STUB"/*
  echo "$H" >"$STUB/head"
  printf 'Nothing to flag.\n\nREVIEW RESULT: NO FINDINGS\n' >"$STUB/reply"
  echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' >"$STUB/check_runs.json"
}
run() { (cd "$root/work" && "$mentat" review --local "${1:-7}" >"$STUB/out" 2>&1); echo $?; }
posted() { [ -f "$STUB/comment" ]; }
# The posted review: a heading line, then the bullets and the reply folded, then the result line.
heading() { [ "$(head -n 1 "$STUB/comment")" = "## Local Claude review of $H: $1, spec fingerprint ${2:-none}" ]; }
folded() { sed -n '/^<details><summary>Full review<\/summary>$/,/^<\/details>$/p' "$STUB/comment"; }
fold_shape() { # $1 the final REVIEW RESULT line
  [ "$(sed -n '/^<details><summary>Full review<\/summary>$/{n;s/^$/blank/;p;}' "$STUB/comment")" = blank ] && [ "$(tail -n 3 "$STUB/comment")" = "</details>

$1" ] && [ "$(grep -c '^</details>$' "$STUB/comment")" = 1 ] && [ "$(tail -n 1 "$STUB/comment")" = "$1" ] && [ "$(grep -v '^[[:space:]]*$' "$STUB/comment" | tail -n 1)" = "$1" ]
}
# The argument after $1 in the stub's arguments, and whether $1 is one of them.
arg() { sed -n "/^$1\$/{n;p;q;}" "$STUB/args"; }
has_arg() { grep -qx -- "$1" "$STUB/args"; }

# A git that, right after any fetch of pull/7/head, also fetches main in the same checkout:
# what a second review running at the same time does. Only the cases that use it (race)
# put it on the PATH, and the git it calls is the one found here, before that.
mkdir -p "$root/racebin"
cat >"$root/racebin/git" <<RACEEOF
#!/usr/bin/env bash
"$(command -v git)" "\$@" || exit \$?
case "\$*" in
  *pull/7/head*) [ "\${1:-}" = -C ] && "$(command -v git)" -C "\$2" fetch -q origin main ;;
esac
RACEEOF
chmod +x "$root/racebin/git"
race() { PATH="$root/racebin:$PATH" run; }

# Claude runs at once; the wait for CI on the same head comes after it, and the post only once CI passed.
runs() { printf '{"check_runs":[{"name":"test","status":"%s","conclusion":%s}]}\n' "$1" "$2"; }
# The model run, the CI reads and the post, in the order gh and claude saw them.
order() { sed -n -e 's/^claude$/model/p' -e 's#.*/check-runs$#ci#p' -e 's/^pr comment .*/post/p' "$STUB/calls" | uniq | tr '\n' ' '; }
# The text printed after the exit-4 line naming the head, without the blank line that follows it.
unposted() { sed "1,/^Review of $H, not posted and not a round:\$/d" "$STUB/out" | sed 1d; }
status() { (cd "$root/work" && "$mentat" status 7 2>&1); }
reset; runs in_progress null >"$STUB/check_runs.json"; runs completed '"success"' >"$STUB/check_runs_later.json"; rc=$(run)
check "a review that finishes before CI is posted only after CI passes on its head (exit 0)" '[ "$rc" = 0 ] && posted && [ "$(order)" = "model ci post " ] && [ "$(cat "$STUB/ci_reads")" -ge 2 ] && grep -q "found nothing on $H" "$STUB/out" && ! grep -q "not posted" "$STUB/out"'
check "a posted review counts as a round" 'status | grep -q "local rounds 1,"'
reset; printf -- '- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; runs in_progress null >"$STUB/check_runs.json"; runs completed '"failure"' >"$STUB/check_runs_later.json"; rc=$(run)
check "CI failing after the review exits 4, posts nothing and names the failing check" '[ "$rc" = 4 ] && ! posted && ! grep -q "pr comment" "$STUB/calls" && [ "$(order)" = "model ci " ] && grep -q "CI did not pass on $H" "$STUB/out" && grep -qx -- "- test" "$STUB/out"'
check "CI failing after the review prints the review after a line saying it was not posted and is not a round" '[ "$(unposted)" = "$(cat "$STUB/reply")" ]'
check "a review not posted for failed CI counts no round" 'status | grep -q "local rounds 0,"'
reset; printf -- '- P2 README:1 still running\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; runs queued null >"$STUB/check_runs.json"; rc=$(run)
check "CI still running at the timeout exits 4, posts nothing and prints the review" '[ "$rc" = 4 ] && ! posted && grep -q "CI did not finish on $H within 2 seconds" "$STUB/out" && [ "$(unposted)" = "$(cat "$STUB/reply")" ]'
reset; runs in_progress null >"$STUB/check_runs.json"; runs completed '"success"' >"$STUB/check_runs_later.json"; echo 3333333333333333333333333333333333333333 >"$STUB/push_on_ci"; rc=$(run)
check "a head that moves during the wait for CI exits 3 and posts nothing" '[ "$rc" = 3 ] && ! posted && [ "$(order)" = "model ci " ] && grep -q "the head moved from $H" "$STUB/out"'
reset; runs completed '"failure"' >"$STUB/check_runs.json"; echo 3333333333333333333333333333333333333333 >"$STUB/push_on_ci"; rc=$(run)
check "a head that moves while CI fails on the reviewed head exits 3, not 4, and posts nothing" '[ "$rc" = 3 ] && ! posted && grep -q "the head moved from $H" "$STUB/out" && ! grep -q "CI did not pass\|not posted" "$STUB/out"'
reset; runs queued null >"$STUB/check_runs.json"; echo 3333333333333333333333333333333333333333 >"$STUB/push_on_ci"; rc=$(run)
check "a head that moves while CI on the reviewed head never finishes exits 3, not 4, and posts nothing" '[ "$rc" = 3 ] && ! posted && grep -q "the head moved from $H" "$STUB/out" && ! grep -q "CI did not finish" "$STUB/out"'
reset; echo '{"check_runs":[]}' >"$STUB/check_runs.json"; rc=$(run)
check "no CI check on the head: says so, then posts (exit 0)" '[ "$rc" = 0 ] && posted && grep -qx "No CI checks ran on $H" "$STUB/out"'
reset; printf 'Looks fine to me.\n' >"$STUB/reply"; runs completed '"failure"' >"$STUB/check_runs.json"; rc=$(run)
check "a reply without a result line is not reviewed before any wait for CI" '[ "$rc" = 1 ] && grep -q "no final REVIEW RESULT line" "$STUB/out" && ! grep -q check-runs "$STUB/calls" && ! posted'
reset; rc=$(run)
check "no findings exits 0 and posts the review" '[ "$rc" = 0 ] && grep -q "found nothing on $H: https://example.test/comment" "$STUB/out" && grep -q "^## Local Claude review of $H" "$STUB/comment"'
check "the comment opens with one heading line: the head, no findings and the fingerprint" 'heading "no findings" none && [ "$(sed -n 2p "$STUB/comment")" = "" ] && [ "$(sed -n 3p "$STUB/comment")" = "<details><summary>Full review</summary>" ]'
check "the bullets and the whole reply are folded, a blank line follows the summary, and the result line is last, after the fold" 'fold_shape "REVIEW RESULT: NO FINDINGS" && folded | grep -qx -- "- Agreed request fingerprint: none" && folded | grep -qx -- "- Claude Code: 2.1.322" && folded | grep -qx -- "---" && [ "$(folded | sed -n "/^---\$/,\$p" | sed "1,2d;\$d")" = "$(cat "$STUB/reply")" ]'
check "the record names the model that ran, from Claude's own report" 'folded | grep -qx -- "- Model: claude-opus-4-9"'
check "reviews the pull request head, not the dirty checkout" '[ "$(cat "$STUB/model_head")" = "$H" ] && [ "$(cat "$STUB/model_readme")" = change ]'
check "reviews the change from the merge base" 'grep -q "Review the change from $BASE to $H" "$STUB/prompt" && grep -q "Change reviewed: $BASE..$H" "$STUB/comment"'
check "gives Claude the pull request description as data" 'grep -q "Requirement: README says change." "$STUB/prompt" && grep -q "BEGIN PULL REQUEST DATA" "$STUB/prompt"'
check "the prompt takes the intent from the Summary opening sentence, or the template equivalent" 'grep -q "its intent is the opening sentence of its Summary (or of the equivalent section of the repository.s own template)" "$STUB/prompt"'
check "the prompt says the Summary second sentence gives why the change is needed" 'grep -q "the second sentence of that Summary says why the change is needed, not what it does" "$STUB/prompt"'
check "the prompt finds the finding lines in the Review details" 'grep -q "description.s Review details hold one line for each finding already fixed or answered" "$STUB/prompt"'
check "the prompt finds the hand-check report in the Review details" 'grep -q "description.s Review details report who checked it and what they saw" "$STUB/prompt"'

# How Claude runs: headless, in safe and restricted mode, with read tools only, on the
# review model, in the head's temporary worktree, with the prompt on stdin.
check "runs claude -p in safe mode and restricted mode, with no prompt for permissions and JSON output" 'has_arg -p && has_arg --safe-mode && has_arg --restricted && [ "$(arg --permission-mode)" = dontAsk ] && [ "$(arg --output-format)" = json ]'
check "gives Claude the read tools only, and allows only them" '[ "$(arg --tools)" = "Read,Grep,Glob" ] && [ "$(arg --allowedTools)" = "Read,Grep,Glob" ] && ! grep -qi bash "$STUB/args"'
check "runs on the default review model" '[ "$(arg --model)" = opus ]'
check "runs in the head's temporary worktree, not the caller's checkout" 'tree=$(cat "$STUB/tree") && [ "$tree" != "$root/work" ] && case "$tree" in "$root/work"/*) false ;; *) true ;; esac && [ "$(git -C "$tree" rev-parse HEAD 2>/dev/null || cat "$STUB/model_head")" = "$H" ] && [ ! -e "$tree" ]'
check "takes the prompt on stdin" 'grep -q "^Review pull request #7. " "$STUB/prompt" && ! grep -qF "Review pull request" "$STUB/args"'
check "the diff and the commit log are files in the folder Claude may also read, outside the worktree, and the prompt names them" 'data=$(cat "$STUB/data") && [ "$(dirname "$data")" = "$(dirname "$(cat "$STUB/tree")")" ] && [ "$data" != "$(cat "$STUB/tree")" ] && [ "$(cat "$STUB/seen_diff")" = "$(git -C "$root/seed" diff "$BASE" "$H")" ] && grep -qx "    change" "$STUB/seen_log" && grep -qF "the diff is in $data/diff and its commits are in $data/log" "$STUB/prompt" && ! grep -q "run: git diff" "$STUB/prompt"'
reset; echo claude-sonnet-4-5 >"$STUB/model_ran"; rc=$(MENTAT_REVIEW_MODEL=sonnet run)
check "MENTAT_REVIEW_MODEL sets the review model" '[ "$rc" = 0 ] && [ "$(arg --model)" = sonnet ] && folded | grep -qx -- "- Model: claude-sonnet-4-5"'
reset; rc=$(MENTAT_REVIEW_MODEL=sonnet run)
check "a model that ran other than the one asked for is recorded with the one asked for" '[ "$rc" = 0 ] && folded | grep -qx -- "- Model: claude-opus-4-9 (asked for sonnet)"'
reset; echo "claude-opus-4-9,claude-haiku-4-5" >"$STUB/model_ran"; rc=$(run)
check "every model that ran is named" '[ "$rc" = 0 ] && folded | grep -qx -- "- Model: claude-haiku-4-5, claude-opus-4-9"'

# Fail closed: none of these is a review. Each is not reviewed (exit 1), says why, posts
# nothing and reads no CI.
closed() { # $1 the reason's fragment
  [ "$rc" = 1 ] && ! posted && grep -qF -- "mentat: not reviewed: $1" "$STUB/out" && ! grep -q check-runs "$STUB/calls"
}
reset; echo 1 >"$STUB/exit"; printf '{"type":"result","subtype":"success","is_error":true,"result":"There is an issue with the selected model (nosuch).\\nmore","permission_denials":[],"modelUsage":{}}\n' >"$STUB/raw"; rc=$(run)
check "a claude that exits non-zero is not reviewed, with its error line and how to set the model" 'closed "claude exited with status 1: There is an issue with the selected model (nosuch).; the review model is set with MENTAT_REVIEW_MODEL (now opus)" && ! grep -q more "$STUB/out"'
reset; echo 3 >"$STUB/exit"; rc=$(run)
check "a non-zero exit with a full reply is still not reviewed" 'closed "claude exited with status 3: Nothing to flag."'
reset; : >"$STUB/raw"; rc=$(run)
check "empty output is not reviewed" 'closed "Claude returned no output"'
reset; printf 'Nothing to flag.\n\nREVIEW RESULT: NO FINDINGS\n' >"$STUB/raw"; rc=$(run)
check "output that is not JSON is not reviewed, even with a result line" 'closed "Claude'"'"'s output is not the JSON result it gives with --output-format json"'
reset; printf '{"type":"result","subtype":"success","is_error":false,"result":"REVIEW RESULT: NO FINDINGS"}\n' >"$STUB/raw"; rc=$(run)
check "JSON without the denials and the models that ran is not reviewed" 'closed "Claude'"'"'s output is not the JSON result it gives with --output-format json"'
reset; echo error_max_turns >"$STUB/subtype"; rc=$(run)
check "a run that did not end in success is not reviewed, and says how to set the model" 'closed "Claude'"'"'s run ended with error_max_turns, not success; the review model is set with MENTAT_REVIEW_MODEL (now opus)"'
reset; printf '{"type":"result","subtype":"success","is_error":true,"result":"Prompt is too long","permission_denials":[],"modelUsage":{"claude-opus-4-9":{}}}\n' >"$STUB/raw"; rc=$(run)
check "a result marked as an error is not reviewed" 'closed "Claude reported an error: Prompt is too long; the review model is set with MENTAT_REVIEW_MODEL (now opus)"'
reset; echo '[{"tool_name":"Read","tool_use_id":"t1","tool_input":{"file_path":"/outside/secret"}},{"tool_name":"Read","tool_use_id":"t2","tool_input":{}}]' >"$STUB/denials"; rc=$(run)
check "a denied tool call is not reviewed, naming the tool and not the path" 'closed "Claude was denied 2 tool call(s) (Read), so the review may not have read what it needed" && ! grep -q /outside/secret "$STUB/out"'
reset; printf '{"type":"result","subtype":"success","is_error":false,"result":"REVIEW RESULT: NO FINDINGS","permission_denials":[],"modelUsage":{}}\n' >"$STUB/raw"; rc=$(run)
check "a result that does not say which model ran is not reviewed" 'closed "Claude'"'"'s output does not say which model ran"'
reset; touch "$STUB/hang"; took=$SECONDS; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1 run); took=$((SECONDS - took))
check "a run past the time limit is stopped and not reviewed" 'closed "Claude did not finish within 1 seconds" && [ "$took" -lt 10 ] && ! kill -0 "$(cat "$STUB/model_pid")" 2>/dev/null'

# Without codex installed, the review runs and posts as usual. path_without prints the
# PATH with each folder that holds $1 replaced by a folder of links to all else in it.
path_without() {
  local d f out="" n=0 IFS=:
  for d in $PATH; do
    if [ -e "$d/$1" ]; then
      n=$((n + 1))
      mkdir -p "$root/without-$1/$n"
      for f in "$d"/*; do [ "${f##*/}" = "$1" ] || ln -s "$f" "$root/without-$1/$n/"; done
      d="$root/without-$1/$n"
    fi
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}
NOCODEX=$(path_without codex)
reset; rc=$(PATH="$NOCODEX" run)
check "with no codex on the PATH, the review completes and posts its record (exit 0)" '(PATH="$NOCODEX"; ! command -v codex >/dev/null 2>&1) && [ "$rc" = 0 ] && posted && heading "no findings" none && grep -q "found nothing on $H" "$STUB/out"'
# No claude anywhere on the PATH, the real one included, so the case never runs it.
NOCLAUDE=$(path_without claude)
if (PATH="$NOCLAUDE"; ! command -v claude >/dev/null 2>&1); then
  reset; rc=$(PATH="$NOCLAUDE" run)
  check "with no claude, the review is not reviewed and says claude is not installed" '[ "$rc" = 1 ] && grep -q "not reviewed: claude is not installed" "$STUB/out" && ! posted'
else
  check "with no claude, the review is not reviewed and says claude is not installed (no PATH without claude could be made)" false
fi

# The issues the pull request closes reach Claude as labeled data, ahead of the description.
ref() { printf '{"number":%s,"repository":{"name":"%s","owner":{"login":"%s"}}}' "$3" "$2" "$1"; }
reset; echo "[$(ref owner repo 3)]" >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_owner_repo_3"; rc=$(run)
check "gives Claude the linked issue's request as data" '[ "$rc" = 0 ] && grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt" && grep -q "Issue owner/repo#3: Make the README say change" "$STUB/prompt" && grep -q "The README must say change, nothing else." "$STUB/prompt"'
reset; echo "[$(ref other proj 9)]" >"$STUB/closes"; printf 'Fix the other thing\nIn the other repository.\n' >"$STUB/issue_other_proj_9"; printf 'Wrong issue\nSame number, wrong repository.\n' >"$STUB/issue_owner_repo_9"; rc=$(run)
check "reads a linked issue from its own repository" '[ "$rc" = 0 ] && grep -q "Issue other/proj#9: Fix the other thing" "$STUB/prompt" && ! grep -q "Wrong issue" "$STUB/prompt"'
reset; echo "[$(ref owner repo 4)]" >"$STUB/closes"; rc=$(run)
check "a linked issue that cannot be read is not reviewed" '[ "$rc" = 1 ] && grep -q "could not read issue owner/repo#4" "$STUB/out" && [ ! -f "$STUB/prompt" ]'
reset; rc=$(run)
check "no linked issue: no issue block" '[ "$rc" = 0 ] && ! grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt"'
check "removes its worktree" '[ "$(git -C "$root/work" worktree list | wc -l | tr -d " ")" = 1 ]'

# A later round's head: the range still starts at the merge base, not at the head reviewed before.
(cd "$root/seed" && echo fix >>README && git commit -qam fix && git push -q "$root/origin.git" HEAD:refs/pull/8/head)
H2=$(git -C "$root/seed" rev-parse HEAD)
reset; echo "$H2" >"$STUB/head"; rc=$(run 8)
check "a later round's head is still reviewed from the merge base, not from the head reviewed before" '[ "$rc" = 0 ] && grep -q "Review the change from $BASE to $H2" "$STUB/prompt" && ! grep -q "from $H " "$STUB/prompt" && [ "$(cat "$STUB/seen_diff")" = "$(git -C "$root/seed" diff "$BASE" "$H2")" ] && grep -q "Change reviewed: $BASE..$H2" "$STUB/comment"'

reset; printf -- '- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "findings exit 2 and are posted" '[ "$rc" = 2 ] && grep -q "posted findings on $H" "$STUB/out" && grep -q "P1 README:1" "$STUB/comment"'
check "a FINDINGS reply's heading says findings, and its findings are inside the fold" 'heading findings none && fold_shape "REVIEW RESULT: FINDINGS" && folded | grep -qx -- "- P1 README:1 wrong text"'
reset; printf 'REVIEW RESULT: NO FINDINGS\n\n- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "the heading's result comes from the reply's final line only" '[ "$rc" = 2 ] && heading findings none && fold_shape "REVIEW RESULT: FINDINGS"'

# Claude runs in a temporary checkout and may cite files by its absolute path, as created or
# resolved, or the data folder's. The posted comment holds none, and links the file at the reviewed commit.
REPO_URL="https://github.com/owner/repo/blob/$H"
leaked() { grep -qF "$(cat "$STUB/tree")" "$STUB/comment" || grep -qF "$(cat "$STUB/treep")" "$STUB/comment" || grep -qF "$(dirname "$(cat "$STUB/treep")")" "$STUB/comment" || grep -qF "$(cat "$STUB/data")" "$STUB/comment"; }
reset; cat >"$STUB/reply" <<'REPLYEOF'
Changes README.

- P2 [README:1](@TREE@/README:1): wrong text
- P2 [lib/shared.sh:93-95](@TREEP@/lib/shared.sh:93-95): a range
- P3 [a dir/a file.txt](@TREE@/a dir/a file.txt#L4): a spaced name
- P3 see @TREEP@/lib/x.sh:7 and `@TREE@/lib/y.sh`
REVIEW RESULT: FINDINGS
REPLYEOF
rc=$(run)
check "a finding that cites the temporary checkout is posted with repository links and no temporary path" '[ "$rc" = 2 ] && ! leaked && grep -qF "[README:1]($REPO_URL/README#L1): wrong text" "$STUB/comment" && grep -qF "[lib/shared.sh:93-95]($REPO_URL/lib/shared.sh#L93-L95): a range" "$STUB/comment" && grep -qF "[a dir/a file.txt]($REPO_URL/a%20dir/a%20file.txt#L4): a spaced name" "$STUB/comment"'
check "a plain mention of the temporary checkout, bare or in code, becomes the repository path" 'grep -qF -- "- P3 see lib/x.sh:7 and \`lib/y.sh\`" "$STUB/comment"'
check "the rewrite leaves the rest of the review and its final result line alone" 'grep -qx "Changes README." "$STUB/comment" && [ "$(tail -n 1 "$STUB/comment")" = "REVIEW RESULT: FINDINGS" ]'
check "the rewritten reply is inside the fold, intact, with the result line after the fold" 'fold_shape "REVIEW RESULT: FINDINGS" && [ "$(folded | sed -n "/^---\$/,\$p" | sed "1,2d;\$d")" = "Changes README.

- P2 [README:1]($REPO_URL/README#L1): wrong text
- P2 [lib/shared.sh:93-95]($REPO_URL/lib/shared.sh#L93-L95): a range
- P3 [a dir/a file.txt]($REPO_URL/a%20dir/a%20file.txt#L4): a spaced name
- P3 see lib/x.sh:7 and \`lib/y.sh\`
REVIEW RESULT: FINDINGS" ]'
reset; printf -- '- P3 the diff at @DATA@/diff:3 adds it\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "a mention of the data folder holds no temporary path" '[ "$rc" = 2 ] && ! leaked && grep -qxF -- "- P3 the diff at diff:3 adds it" "$STUB/comment"'
reset; printf -- '- P3 see @TREE@-other/z and /Users/other/tree/w\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "a path that only starts with the checkout's name, and other absolute paths, are left alone" '[ "$rc" = 2 ] && grep -qxF -- "- P3 see $(cat "$STUB/tree")-other/z and /Users/other/tree/w" "$STUB/comment"'
reset; printf 'Could not finish.\n\nREVIEW RESULT: INCOMPLETE - could not read @TREE@/lib/z.sh\n' >"$STUB/reply"; rc=$(run)
check "an INCOMPLETE reason that names the temporary checkout is posted and printed as a repository path" '[ "$rc" = 1 ] && ! leaked && grep -qx "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" "$STUB/comment" && heading incomplete none && fold_shape "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" && grep -q "incomplete: could not read lib/z.sh" "$STUB/out" && ! grep -qF "$(cat "$STUB/tree")" "$STUB/out"'
# Link forms: an angle-bracket target, parentheses in a file name, and a line given only in the link text.
reset; cat >"$STUB/reply" <<'REPLYEOF'
- P2 [a dir/a file.txt:7](<@TREE@/a dir/a file.txt:7>): angle target
- P2 [app/(auth)/page.tsx:7](@TREE@/app/(auth)/page.tsx:7) (see also [x](@TREE@/y.sh:2)): parentheses
- P2 [lib/shared.sh:93](@TREE@/lib/shared.sh): line in the text
- P2 [lib/x.sh:3-5](@TREEP@/lib/x.sh): range in the text
REVIEW RESULT: FINDINGS
REPLYEOF
rc=$(run)
check "an angle-bracket link target becomes a repository link" '[ "$rc" = 2 ] && ! leaked && grep -qF -- "- P2 [a dir/a file.txt:7]($REPO_URL/a%20dir/a%20file.txt#L7): angle target" "$STUB/comment"'
check "a file name with parentheses is linked whole, and the text after the link is kept" 'grep -qF -- "- P2 [app/(auth)/page.tsx:7]($REPO_URL/app/%28auth%29/page.tsx#L7) (see also [x]($REPO_URL/y.sh#L2)): parentheses" "$STUB/comment"'
check "a line given only in the link text goes into the link, a range too" 'grep -qF -- "- P2 [lib/shared.sh:93]($REPO_URL/lib/shared.sh#L93): line in the text" "$STUB/comment" && grep -qF -- "- P2 [lib/x.sh:3-5]($REPO_URL/lib/x.sh#L3-L5): range in the text" "$STUB/comment"'

# Percent-encoded targets and code-formatted link text.
reset; cat >"$STUB/reply" <<'REPLYEOF'
- P2 [a dir/a file.txt:7](@TREE@/a%20dir/a%20file.txt:7): encoded file name
- P2 [caf](@TREE@/caf%C3%A9.txt:2): non-ASCII, and [x](https://example.test/a%20b) is not touched
- P2 [`lib/x.sh:7`](@TREE@/lib/x.sh): code-formatted text
REVIEW RESULT: FINDINGS
REPLYEOF
rc=$(run)
check "a link target with a percent-encoded file name is decoded and encoded once" '[ "$rc" = 2 ] && ! leaked && grep -qF -- "- P2 [a dir/a file.txt:7]($REPO_URL/a%20dir/a%20file.txt#L7): encoded file name" "$STUB/comment" && grep -qF -- "- P2 [caf]($REPO_URL/café.txt#L2)" "$STUB/comment"'
check "a link that does not point into the checkout is not decoded" 'grep -qF -- "[x](https://example.test/a%20b) is not touched" "$STUB/comment"'
check "a line in code-formatted link text goes into the link" 'grep -qF -- "- P2 [\`lib/x.sh:7\`]($REPO_URL/lib/x.sh#L7): code-formatted text" "$STUB/comment"'
spaced="$root/sp ace/tree"
mkdir -p "$spaced"
printf -- '- P1 [lib/a.sh:7](%s/lib/a.sh:7) and [b](<%s/b.sh>) and %s/c.sh\n' "${spaced// /%20}" "${spaced// /%20}" "$spaced" >"$STUB/enc.md"
check "a root with spaces, written as %20 in a link target, is matched" '(. "$(dirname "$mentat")/../lib/shared.sh" && localize_review_paths "$STUB/enc.md" owner/repo "$H" "$spaced") && [ "$(cat "$STUB/enc.md")" = "- P1 [lib/a.sh:7]($REPO_URL/lib/a.sh#L7) and [b]($REPO_URL/b.sh) and c.sh" ]'

# The roots are matched literally: a checkout whose path has spaces and characters sed and
# regular expressions treat specially (the test's temporary directory, where mktemp ignores
# TMPDIR on macOS, cannot be made to have them), called directly.
odd="$root/odd & [dir] (x)+.*|\\ \$HOME/tree"
mkdir -p "$odd"
printf -- '- P1 [README:1](%s/README:1): wrong\n- P2 %s/lib/a b.sh:3 and %s2/keep\n' "$odd" "$odd" "$odd" >"$STUB/odd.md"
check "a checkout path with spaces and special characters is rewritten, and only that path" '(. "$(dirname "$mentat")/../lib/shared.sh" && localize_review_paths "$STUB/odd.md" owner/repo "$H" "$odd") && [ "$(cat "$STUB/odd.md")" = "- P1 [README:1]($REPO_URL/README#L1): wrong
- P2 lib/a b.sh:3 and $odd""2/keep" ]'

# The publish check, on the final comment, right before the post.
held_file() { sed -n 's/.*the maintainer can read it at //p' "$STUB/out"; }
held() { # $1 category, $2 the match: not posted, not reviewed, kept whole, and no message repeats it
  [ "$rc" = 1 ] && ! posted && grep -q "not reviewed: the comment holds $1, so it was not posted" "$STUB/out" &&
    grep -qiF -- "$2" "$(held_file)" && grep -q "^## Local Claude review of $H" "$(held_file)" && [ "$(tail -n 1 "$(held_file)")" = "$(tail -n 1 "$STUB/reply")" ] && ! grep -qiF -- "$2" "$STUB/out"
}
printf '# a comment\n\nStubCodename\n' >"$LIST"
reset; printf -- '- P3 %s/notes.md\n\nREVIEW RESULT: FINDINGS\n' "$HOME" >"$STUB/reply"; rc=$(run)
check "a comment with the home path is not posted, exits as not reviewed, is kept, and no message repeats it" 'held "a local path" "$HOME"'
check "a hit looks up the reviewed repository" 'grep -qF "repo view owner/repo --json isPrivate" "$STUB/calls"'
rm -f "$(held_file)"
reset; printf -- '- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "a comment with a word from the list, in another case, is the same" 'held "a configured private name" stubcodename'
rm -f "$(held_file)"
reset; printf 'Stopped at stubcodename.\n\nREVIEW RESULT: INCOMPLETE - could not read stubcodename\n' >"$STUB/reply"; rc=$(run)
check "an INCOMPLETE reason is checked before it is posted or printed" 'held "a configured private name" stubcodename'
rm -f "$(held_file)"
reset; touch "$STUB/lookup_fails"; printf -- '- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "a failed visibility lookup counts as public" 'held "a configured private name" stubcodename'
rm -f "$(held_file)"
reset; touch "$STUB/private"; printf -- '- P3 about stubcodename at %s/x\n\nREVIEW RESULT: FINDINGS\n' "$HOME" >"$STUB/reply"; rc=$(run)
check "a private repository's comment is posted unchanged" '[ "$rc" = 2 ] && grep -qF "about stubcodename at $HOME/x" "$STUB/comment"'
reset; rc=$(run)
check "no hit: posts, with no visibility lookup" '[ "$rc" = 0 ] && posted && ! grep -q isPrivate "$STUB/calls"'
rm "$LIST"
reset; printf -- '- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "a missing word list never blocks" '[ "$rc" = 2 ] && grep -q "about stubcodename" "$STUB/comment"'
reset; printf -- '- P3 %s/notes.md\n\nREVIEW RESULT: FINDINGS\n' "$HOME" >"$STUB/reply"; rc=$(run)
check "with a missing word list the home path is still found" 'held "a local path" "$HOME"'
rm -f "$(held_file)"

reset; printf 'Looks fine to me.\n' >"$STUB/reply"; rc=$(run)
check "a reply without a result line is not reviewed and not posted" '[ "$rc" = 1 ] && grep -q "no final REVIEW RESULT line" "$STUB/out" && ! posted'

# A reply that could not read a material file or the diff ends INCOMPLETE: it is posted,
# so the reason is on the pull request, and it is not reviewed.
reset; printf 'I could not read the linked issue.\n\nREVIEW RESULT: INCOMPLETE - the linked issue could not be read\n' >"$STUB/reply"; rc=$(run)
check "an INCOMPLETE reply with a reason is posted and not reviewed (exit 1), with the reason" '[ "$rc" = 1 ] && posted && heading incomplete none && fold_shape "REVIEW RESULT: INCOMPLETE - the linked issue could not be read" && folded | grep -qx "I could not read the linked issue." && grep -q "not reviewed: Claude says the review is incomplete: the linked issue could not be read" "$STUB/out" && ! grep -q "posted findings\|found nothing" "$STUB/out"'
for bare in 'REVIEW RESULT: INCOMPLETE' 'REVIEW RESULT: INCOMPLETE -' 'REVIEW RESULT: INCOMPLETE -   '; do
  reset; printf 'Could not finish.\n\n%s\n' "$bare" >"$STUB/reply"; rc=$(run)
  check "an INCOMPLETE line without a reason ('$bare') is no final result line and is not posted" '[ "$rc" = 1 ] && grep -q "no final REVIEW RESULT line" "$STUB/out" && ! posted'
done
reset; printf 'Could not finish.\n\nREVIEW RESULT: INCOMPLETE - the diff could not be read\n' >"$STUB/reply"; echo 3333333333333333333333333333333333333333 >"$STUB/moved_head"; rc=$(run)
check "an INCOMPLETE reply whose head moved is exit 3 and not posted" '[ "$rc" = 3 ] && ! posted'
reset; printf 'Could not finish.\n\nREVIEW RESULT: INCOMPLETE - the diff could not be read\n' >"$STUB/reply"; touch "$STUB/comment_fails"; rc=$(run)
check "an INCOMPLETE reply that cannot be posted is not reviewed" '[ "$rc" = 1 ] && grep -q "could not post the review" "$STUB/out" && ! grep -q "Claude says the review is incomplete" "$STUB/out"'
reset; rc=$(run)
check "the prompt offers the three final lines" '[ "$rc" = 0 ] && grep -qx "REVIEW RESULT: NO FINDINGS" "$STUB/prompt" && grep -qx "REVIEW RESULT: FINDINGS" "$STUB/prompt" && grep -qx "REVIEW RESULT: INCOMPLETE - <what could not be read>" "$STUB/prompt"'

reset; echo 3333333333333333333333333333333333333333 >"$STUB/moved_head"; rc=$(run)
check "a head that moves during the review is not posted (exit 3)" '[ "$rc" = 3 ] && ! posted'

reset; echo 4444444444444444444444444444444444444444 >"$STUB/head"; rc=$(run)
check "a head GitHub reports that the fetch does not match is exit 3" '[ "$rc" = 3 ] && [ ! -f "$STUB/prompt" ]'

# A second review fetching main into the same checkout while this one fetches the pull
# request must not change what this one reads: it is not a moved head.
reset; rc=$(race)
check "a fetch of main by another process between this review's fetch and its read is not a moved head (exit 0)" '[ "$rc" = 0 ] && grep -q "found nothing on $H" "$STUB/out" && posted && [ -z "$(git -C "$root/work" for-each-ref refs/mentat)" ]'

# The review must not write the checkout's origin/main either: another review may be using it.
stale=$(git -C "$root/work" commit-tree -m stale "$(git -C "$root/work" rev-parse 'HEAD^{tree}')")
git -C "$root/work" update-ref refs/remotes/origin/main "$stale"
reset; rc=$(run)
check "a review leaves the checkout's origin/main alone" '[ "$rc" = 0 ] && [ "$(git -C "$root/work" rev-parse refs/remotes/origin/main)" = "$stale" ]'
git -C "$root/work" update-ref refs/remotes/origin/main "$BASE"

reset; touch "$STUB/comment_fails"; rc=$(run)
check "a failed post is not reviewed" '[ "$rc" = 1 ] && grep -q "could not post the review" "$STUB/out"'

rc=$("$mentat" review --local abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

# With no mode flag, mentat review is the Claude review, the same as --local.
reset; rc=$(cd "$root/work" && "$mentat" review 7 >"$STUB/out" 2>&1; echo $?)
check "no mode flag runs the Claude review and posts it (exit 0)" '[ "$rc" = 0 ] && grep -q "found nothing on $H: https://example.test/comment" "$STUB/out" && heading "no findings" none && fold_shape "REVIEW RESULT: NO FINDINGS" && [ "$(arg --model)" = opus ]'

# --request <file>: the agreed request, kept apart from the description. Read before CI;
# its text reaches Claude in its own block; the posted comment records its fingerprint.
REQ_TEXT=$'Make the README say change.\nLeave every other file alone.\nChecked by reading README.'
REQ_FP=71fca9a263e9  # shasum -a 256 of REQ_TEXT, first 12 hex characters, computed independently
mkdir -p "$root/req dir"
printf '%s\n' "$REQ_TEXT" >"$root/req dir/agreed request.md"
runq() { (cd "$root/work" && "$mentat" review --local --request "$1" "${2:-7}" >"$STUB/out" 2>&1); echo $?; }
reset; rc=$(runq "$root/req dir/agreed request.md")
check "--request: the request reaches Claude in its own labeled block, a path with spaces works" '[ "$rc" = 0 ] && sed -n "/^--- BEGIN AGREED REQUEST DATA ---\$/,/^--- END AGREED REQUEST DATA ---\$/p" "$STUB/prompt" | grep -qxF "Leave every other file alone." && grep -qx -- "--- END AGREED REQUEST DATA ---" "$STUB/prompt" && grep -q "BEGIN PULL REQUEST DATA" "$STUB/prompt"'
check "--request: the posted comment records the request fingerprint (first 12 hex of its SHA-256), in the heading and in the fold" 'grep -qx -- "- Agreed request fingerprint: $REQ_FP" "$STUB/comment" && [ "${#REQ_FP}" = 12 ] && heading "no findings" "$REQ_FP" && folded | grep -qx -- "- Agreed request fingerprint: $REQ_FP"'
reset; rc=$(run)
check "no --request: no agreed request block, and the comment says the fingerprint is none" '[ "$rc" = 0 ] && ! grep -q "AGREED REQUEST DATA" "$STUB/prompt" && grep -qx -- "- Agreed request fingerprint: none" "$STUB/comment" && heading "no findings" none && folded | grep -qx -- "- Agreed request fingerprint: none"'
reset; echo "[$(ref owner repo 3)]" >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_owner_repo_3"; rc=$(runq "$root/req dir/agreed request.md")
check "--request with a linked issue: both blocks reach Claude" '[ "$rc" = 0 ] && grep -qx -- "--- BEGIN AGREED REQUEST DATA ---" "$STUB/prompt" && grep -qx -- "--- BEGIN LINKED ISSUE DATA ---" "$STUB/prompt" && grep -q "Issue owner/repo#3: Make the README say change" "$STUB/prompt"'
printf ' \n\t\n\n' >"$root/blank.md"
printf 'x\n' >"$root/locked.md"; chmod 000 "$root/locked.md"
unread() { # $1 description, $2 file, $3 expected fragment of the reason
  rc=$(runq "$2"); frag=$3
  check "--request $1: not reviewed (exit 1) before CI, Claude does not run, nothing is posted" '[ "$rc" = 1 ] && grep -q "not reviewed: .*$frag" "$STUB/out" && [ ! -f "$STUB/prompt" ] && ! posted && ! grep -q "check-runs\|pr view" "$STUB/calls" 2>/dev/null'
}
reset; unread "with a whitespace-only file" "$root/blank.md" "is empty"
reset; unread "with a missing file" "$root/no such file.md" "could not read the agreed request file"
reset; unread "with an unreadable file" "$root/locked.md" "could not read the agreed request file"
reset; unread "with a directory" "$root" "could not read the agreed request file"
reset; unread "with an empty file name (an empty variable)" "" "request file name for #7 is empty"
chmod 600 "$root/locked.md"
# With no mode flag, --request runs the same Claude review as --local --request.
reset; rc=$(cd "$root/work" && "$mentat" review --request "$root/req dir/agreed request.md" 7 >"$STUB/out" 2>&1; echo $?)
check "--request with no mode flag reviews with Claude and records the fingerprint" '[ "$rc" = 0 ] && grep -q "found nothing on $H" "$STUB/out" && grep -qx -- "--- BEGIN AGREED REQUEST DATA ---" "$STUB/prompt" && grep -qx -- "- Agreed request fingerprint: $REQ_FP" "$STUB/comment" && heading "no findings" "$REQ_FP"'
rc=$("$mentat" review --local --request >"$STUB/out" 2>&1; echo $?)
check "--request without a file and a pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

# --require-ci: a head where no CI check ran is not a pass.
runrc() { (cd "$root/work" && "$mentat" review --local "$@" >"$STUB/out" 2>&1); echo $?; }
reset; printf -- '- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; echo '{"check_runs":[]}' >"$STUB/check_runs.json"; rc=$(runrc --require-ci 7)
check "--require-ci with no CI check on the head exits 4, says so, prints the review and posts nothing" '[ "$rc" = 4 ] && ! posted && grep -qx "No CI checks ran on $H" "$STUB/out" && [ "$(unposted)" = "$(cat "$STUB/reply")" ] && [ "$(order)" = "model ci " ]'
check "--require-ci: a review not posted for a head with no CI counts no round" 'status | grep -q "local rounds 0,"'
reset; echo '{"check_runs":[]}' >"$STUB/check_runs.json"; rc=$(runrc --require-ci --request "$root/req dir/agreed request.md" 7)
check "--require-ci before --request works the same" '[ "$rc" = 4 ] && ! posted && grep -qx "No CI checks ran on $H" "$STUB/out" && grep -q "BEGIN AGREED REQUEST DATA" "$STUB/prompt"'
reset; rc=$(runrc --request "$root/req dir/agreed request.md" --require-ci 7)
check "--require-ci after --request, with CI passed, posts as usual (exit 0)" '[ "$rc" = 0 ] && posted && grep -qx -- "- Agreed request fingerprint: $REQ_FP" "$STUB/comment"'
for args in "--require-ci --require-ci 7" "--require-ci" "--require-ci 7 8"; do
  # shellcheck disable=SC2086 # the words are the arguments
  rc=$("$mentat" review --local $args >/dev/null 2>&1; echo $?)
  check "usage error (exit 64) for: review --local $args" '[ "$rc" = 64 ]'
done

# Interrupts. mentat runs in its own process group with default INT handling (a job this
# script starts in the background ignores INT), and is signalled once the hung model has
# started or the wait for CI has begun. Within seconds nothing of the run is left: no
# process in its group, no model, no worktree.
worktrees() { git -C "$root/work" worktree list | wc -l | tr -d ' '; }
interrupt() { # $1 model or ci, $2 signal, $3 group or pid
  local i
  (
    cd "$root/work" || exit 1
    # A long pause between CI reads, which the signal must not wait out.
    [ "$1" = model ] || export MENTAT_REVIEW_INTERVAL_SECONDS=30 MENTAT_CI_TIMEOUT_SECONDS=120
    exec perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV or die' -- "$mentat" review --local 7 >"$STUB/out" 2>&1
  ) &
  ip=$! ready=no
  for i in $(seq 100); do
    if [ -f "$STUB/model_pid" ] || grep -q '^Waiting for CI' "$STUB/out" 2>/dev/null; then ready=yes; break; fi
    sleep 0.1
  done
  before=$(worktrees) took=$SECONDS
  if [ "$3" = group ]; then kill -"$2" -- "-$ip"; else kill -"$2" "$ip"; fi
  wait "$ip"
  for i in $(seq 50); do kill -0 -- "-$ip" 2>/dev/null || break; sleep 0.1; done
  took=$((SECONDS - took))
}
gone() { [ "$ready" = yes ] && [ "$before" = 2 ] && [ "$took" -lt 10 ] && ! kill -0 -- "-$ip" 2>/dev/null && { [ ! -f "$STUB/model_pid" ] || ! kill -0 "$(cat "$STUB/model_pid")" 2>/dev/null; } && [ "$(worktrees)" = 1 ] && [ -s "$STUB/tree" ] && [ ! -e "$(cat "$STUB/tree")" ]; }
reset; touch "$STUB/hang"; interrupt model INT group
check "INT to its process group while Claude runs stops Claude and removes the worktree within seconds" 'gone'
kill -9 -- "-$ip" 2>/dev/null
reset; runs in_progress null >"$STUB/check_runs.json"; interrupt ci INT group
check "INT to its process group during the wait for CI leaves no process and removes the worktree within seconds" 'gone'
kill -9 -- "-$ip" 2>/dev/null
reset; runs in_progress null >"$STUB/check_runs.json"; interrupt ci TERM pid
check "TERM to mentat alone during the wait for CI does not wait out the pause, leaves no process and removes the worktree" 'gone'
kill -9 -- "-$ip" 2>/dev/null

# At start, Grok run folders older than a day, and kept logs and held comments older than
# seven days, are deleted. Newer ones, other names, symlinks and their targets stay.
ago() { touch -h -t "$(date -v-"$1"M +%Y%m%d%H%M.%S)" "$2"; } # $1 minutes ago, $2 path
c="$XDG_CACHE_HOME/mentat" elsewhere="$root/elsewhere"
mkdir -p "$c" "$elsewhere/dir" && echo keep >"$elsewhere/dir/f" && echo keep >"$elsewhere/file"
for d in grok-review.old grok-opinion.old grok-opinion-web.old grok-review.new grok-reviewx; do mkdir "$c/$d" && echo x >"$c/$d/f"; done
ln -s "$elsewhere/dir" "$c/grok-review.link"
for f in mentat-codex-log.old mentat-grok-log.old mentat-held-comment.old mentat-codex-log.new mentat-codex-logs; do echo x >"$TMPDIR/$f"; done
ln -s "$elsewhere/file" "$TMPDIR/mentat-grok-log.link"
for p in grok-review.old grok-opinion.old grok-opinion-web.old; do ago 1445 "$c/$p"; done
ago 1435 "$c/grok-review.new"
for p in "$c/grok-reviewx" "$c/grok-review.link" "$elsewhere/dir"; do ago 2880 "$p"; done
for p in mentat-codex-log.old mentat-grok-log.old mentat-held-comment.old; do ago 10085 "$TMPDIR/$p"; done
ago 10075 "$TMPDIR/mentat-codex-log.new"
for p in "$TMPDIR/mentat-codex-logs" "$TMPDIR/mentat-grok-log.link" "$elsewhere/file"; do ago 20160 "$p"; done
reset; rc=$(run)
check "at start, deletes Grok run folders older than a day and kept logs and held comments older than seven days" '[ "$rc" = 0 ] && [ ! -e "$c/grok-review.old" ] && [ ! -e "$c/grok-opinion.old" ] && [ ! -e "$c/grok-opinion-web.old" ] && [ ! -e "$TMPDIR/mentat-codex-log.old" ] && [ ! -e "$TMPDIR/mentat-grok-log.old" ] && [ ! -e "$TMPDIR/mentat-held-comment.old" ]'
check "at start, keeps ones inside those limits, similar names, and symlinks named like them with their targets" '[ -f "$c/grok-review.new/f" ] && [ -f "$c/grok-reviewx/f" ] && [ -L "$c/grok-review.link" ] && [ "$(cat "$elsewhere/dir/f")" = keep ] && [ -f "$TMPDIR/mentat-codex-log.new" ] && [ -f "$TMPDIR/mentat-codex-logs" ] && [ -L "$TMPDIR/mentat-grok-log.link" ] && [ "$(cat "$elsewhere/file")" = keep ]'
rm -rf "$c" "$elsewhere" "$TMPDIR"/mentat-*

[ "$failures" -eq 0 ]
