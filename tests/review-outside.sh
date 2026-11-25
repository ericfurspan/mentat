#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for outside reviewers as adapters, through the commands people run:
# mentat reviewers, mentat review --outside, mentat status and mentat second-opinion. They
# run a copy of Mentat whose reviewers module ships stub adapters instead of the real
# ones (core is copied unchanged): alpha, which finds something; beta, which finds
# nothing; slow, which never finishes within the time limit; and delta, whose tool is the
# command delta-cli, not its name. A real git origin, a stub gh and stub tools.
# Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

src="$(cd "$(dirname "$0")/.." && pwd)"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
export HOME="$root/home" TMPDIR="$root/tmp" XDG_CACHE_HOME="$root/cache"
mkdir -p "$STUB" "$root/tools/bin" "$HOME" "$TMPDIR"
failures=0
check() { if eval "$2"; then printf 'PASS: review-outside %s\n' "$1"; else printf 'FAIL: review-outside %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset MENTAT_REVIEWERS MENTAT_REVIEW_TIMEOUT_SECONDS MENTAT_REVIEW_ROUNDS

# The copy: core as it is, the module's code as it is, and only the stub adapters.
copy="$root/mentat"
mkdir -p "$copy/plugins/mentat-reviewers/adapters"
cp -R "$src/bin" "$src/lib" "$copy/" && cp -R "$src/plugins/mentat-reviewers/bin" "$src/plugins/mentat-reviewers/lib" "$copy/plugins/mentat-reviewers/" || exit 1
mentat="$copy/bin/mentat"
# stub_adapter <name> <display> <tool>: an adapter whose tool is the command <tool>.
stub_adapter() {
  sed -e "s/@DISPLAY@/$2/g" -e "s/@TOOL@/$3/g" >"$copy/plugins/mentat-reviewers/adapters/$1.sh" <<'EOF'
# shellcheck shell=bash
adapter_display=@DISPLAY@
adapter_available() { command -v @TOOL@ >/dev/null 2>&1 && return 0; adapter_why="@TOOL@ is not installed"; return 1; }
adapter_run() {
  { printf 'mode %s, head %s\n' "$1" "$head"; if [ "$1" = review ]; then review_body ""; else cat "$res/body"; fi; } >"$work/prompt" || adapter_fail "could not write the prompt" "" none
  (cd "$tree" && exec @TOOL@ "$1" "$work/prompt") >"$reply" 2>"$work/err" </dev/null &
  adapter_wait "$!" "the log is kept at $work/err"
  [ "$adapter_rc" -eq 0 ] || adapter_fail "@TOOL@ exited with status $adapter_rc" "its log may hold credentials; the maintainer can read it at $work/err"
}
adapter_meta() { printf -- '- Model: @TOOL@-model-1\n'; }
EOF
}
stub_adapter alpha Alpha alpha-tool
stub_adapter beta Beta beta-tool
stub_adapter slow Slow slow-tool
stub_adapter delta Delta delta-cli

# The tools: each records its run (name, mode, folder, head and hooks marker), then replies
# as $STUB/<name>.<mode> says, else its default. alpha and beta each wait, briefly, for the
# other to start, and record whether it did, so a run one after the other is told apart.
for t in alpha-tool:alpha beta-tool:beta slow-tool:slow delta-cli:delta; do
  tool=${t%%:*} n=${t#*:}
  cat >"$root/tools/bin/$tool" <<EOF
#!/usr/bin/env bash
n=$n
EOF
  cat >>"$root/tools/bin/$tool" <<'EOF'
printf '%s %s %s %s\n' "$n" "$1" "$(pwd -P)" "$(git rev-parse HEAD 2>/dev/null)" >>"$STUB/tool_calls"
cp "$2" "$STUB/$n.prompt"
touch "$STUB/$n.started"
case "$n" in alpha) other=beta ;; beta) other=alpha ;; *) other="" ;; esac
if [ -n "$other" ] && [ -f "$STUB/expect_$other" ]; then
  i=0; while [ ! -f "$STUB/$other.started" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$STUB/$other.started" ] && touch "$STUB/$n.together"
fi
[ "$n" = slow ] && { echo $$ >"$STUB/slow.pid"; exec sleep 30; }
[ -f "$STUB/$n.fails" ] && { echo "fake-token-in-log" >&2; exit 3; }
if [ -f "$STUB/$n.$1" ]; then cat "$STUB/$n.$1"; exit 0; fi
if [ "$1" = opinion ]; then printf 'Fine.\n\nSECOND OPINION VERDICT: DO IT\n'; exit 0; fi
case "$n" in
  alpha) printf '%s/README:1 says change (blocking)\n\nREVIEW RESULT: FINDINGS\n' "$(pwd -P)" ;;
  *) printf 'Nothing to flag.\n\nREVIEW RESULT: NO FINDINGS\n' ;;
esac
EOF
  chmod +x "$root/tools/bin/$tool"
done

# An origin with main and pull request 7, whose head changes README and carries a hooks
# folder whose post-checkout hook leaves a marker. The clone uses that folder as its
# hooks path, so a checkout that ran the head's hooks would leave the marker.
git init -q --bare -b main "$root/origin.git"
git init -q -b main "$root/seed"
(cd "$root/seed" && echo base >README && mkdir .claude && echo '{}' >.claude/settings.json &&
  git add README .claude/settings.json && git commit -qm base && git push -q "$root/origin.git" main &&
  git checkout -qb feature && echo change >README && mkdir .hooks &&
  printf '#!/bin/sh\ntouch "$STUB/hook_ran"\n' >.hooks/post-checkout && chmod +x .hooks/post-checkout &&
  git add -A && git commit -qm change && git push -q "$root/origin.git" HEAD:refs/pull/7/head && git checkout -q main)
H=$(git -C "$root/seed" rev-parse feature)
OLD=1111111111111111111111111111111111111111
git clone -q "$root/origin.git" "$root/work"
git -C "$root/work" config core.hooksPath .hooks
# settings <json>: main's .claude/settings.json on origin.
settings() {
  printf '%s\n' "$1" >"$root/seed/.claude/settings.json"
  { git -C "$root/seed" diff --quiet || git -C "$root/seed" commit -qam settings; } && git -C "$root/seed" push -q "$root/origin.git" main
}
listing() { settings "{\"enabledPlugins\":{\"mentat-reviewers@mentat\":true},\"env\":{\"MENTAT_REVIEWERS\":\"$1\"}}"; }

# gh, as in tests/review-codex.sh: the pull request, CI and comments from $STUB; pr comment
# records the body and adds it to the comments, as this account's.
cat >"$root/tools/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "pr view")
    case "$*" in *mergeable*) echo MERGEABLE; exit 0 ;; esac
    n=$(($(cat "$STUB/head_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/head_reads"
    h=$(cat "$STUB/head"); [ "$n" -gt 1 ] && [ -f "$STUB/moved_head" ] && h=$(cat "$STUB/moved_head")
    case "$*" in
      *--jq*) echo "$h" ;;
      *) jq -n --arg h "$h" '{headRefOid: $h, baseRefName: "main", title: "Change README", body: "Requirement: README says change.", closingIssuesReferences: []}' ;;
    esac ;;
  "repo view")
    case "$*" in
      *isPrivate*) if [ -f "$STUB/private" ]; then echo true; else echo false; fi ;;
      *) echo owner/repo ;;
    esac ;;
  "api --paginate")
    case "$3" in
      */check-runs) cat "$STUB/check_runs.json" ;;
      */comments) cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]' ;;
      *) exit 99 ;;
    esac ;;
  "api user") echo agent-bot ;;
  "api repos/owner/repo") echo User ;;
  "pr comment")
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$STUB/comment"; shift; done
    jq --rawfile b "$STUB/comment" '. + [{user: {login: "agent-bot"}, body: $b}]' <<<"$(cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]')" >"$STUB/ic.tmp" && mv "$STUB/ic.tmp" "$STUB/issue_comments.json"
    echo https://example.test/comment ;;
  *) exit 99 ;;
esac
STUBEOF
chmod +x "$root/tools/bin/gh"
export PATH="$root/tools/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_CI_TIMEOUT_SECONDS=2 MENTAT_CI_GRACE_SECONDS=1

# claude_said <sha> <result>: a Local Claude review comment by this account.
claude_said() {
  jq --arg b "## Local Claude review of $1: $2, spec fingerprint ${3:-none}

REVIEW RESULT: X" '. + [{user: {login: "agent-bot"}, body: $b}]' "$STUB/issue_comments.json" >"$STUB/ic.tmp" && mv "$STUB/ic.tmp" "$STUB/issue_comments.json"
}
reset() {
  rm -f "$STUB"/* "$XDG_CACHE_HOME"/mentat/reviewer-failures-*
  echo "$H" >"$STUB/head"
  echo '[]' >"$STUB/issue_comments.json"
  echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' >"$STUB/check_runs.json"
  claude_said "$H" "no findings"
}
run() { (cd "$root/work" && "$mentat" review --outside "$@" >"$STUB/out" 2>"$STUB/err"); echo $?; }
posted() { [ -f "$STUB/comment" ]; }
heading() { [ "$(head -n 1 "$STUB/comment")" = "## Outside review of $H: spec fingerprint ${2:-none}, reviewers $1" ]; }
row() { grep -qxF -- "- $1" "$STUB/comment"; }
said() { grep -qxF -- "$1" "$STUB/out"; }
ran() { grep -c "^$1 " "$STUB/tool_calls" 2>/dev/null | tr -d ' '; }
no_tool_ran() { [ ! -f "$STUB/tool_calls" ]; }

# mentat reviewers lists each name from the module's offline check, running no tool.
listing "alpha,delta,nope"
rc=$(cd "$root/work" && PATH="$root/tools/bin:/usr/bin:/bin:$(dirname "$(command -v jq)")" "$mentat" reviewers >"$STUB/out" 2>&1; echo $?)
check "listing: each listed name and whether it is available, a missing tool named by its own command, an unshipped name skipped" '[ "$rc" = 0 ] && [ "$(cat "$STUB/out")" = "reviewers: on
alpha: available
delta: available
nope: skipped (the mentat-reviewers module has no such reviewer)" ] && no_tool_ran'
mv "$root/tools/bin/delta-cli" "$root/delta-cli.off"
rc=$(cd "$root/work" && "$mentat" reviewers >"$STUB/out" 2>&1; echo $?)
check "listing: a reviewer whose tool command is missing is not available, naming that command" 'grep -qxF "delta: not available (delta-cli is not installed)" "$STUB/out"'
mv "$root/delta-cli.off" "$root/tools/bin/delta-cli"

# Fan-out: every listed, available reviewer runs at once on the head, one comment records
# the run, and one summary line per reviewer is printed.
listing "alpha,beta"
reset; touch "$STUB/expect_alpha" "$STUB/expect_beta"; rc=$(run 7)
check "fan-out: findings from one reviewer exit 2, after one post" '[ "$rc" = 2 ] && posted && [ "$(grep -c "^pr comment" "$STUB/calls")" = 1 ]'
check "fan-out: each reviewer ran once, in review mode, on the head" '[ "$(ran alpha)" = 1 ] && [ "$(ran beta)" = 1 ] && [ "$(grep -c " review .* $H\$" "$STUB/tool_calls")" = 2 ]'
check "fan-out: the reviewers ran in parallel" '[ -f "$STUB/alpha.together" ] && [ -f "$STUB/beta.together" ]'
check "fan-out: each got the review prompt, with the request and the result line" 'grep -q "Requirement: README says change." "$STUB/alpha.prompt" && grep -q "^REVIEW RESULT: NO FINDINGS$" "$STUB/beta.prompt" && grep -q "^mode review, head $H$" "$STUB/alpha.prompt"'
check "the comment names the head, the spec fingerprint and the list, then one result line each" 'heading "alpha, beta" && row "alpha: findings" && row "beta: no findings"'
check "the comment folds each reply with the model that ran, and the reply holds no local path" 'grep -qxF "<details><summary>Alpha</summary>" "$STUB/comment" && grep -qxF -- "- Model: alpha-tool-model-1" "$STUB/comment" && grep -qF "README:1 says change (blocking)" "$STUB/comment" && ! grep -qF "$root" "$STUB/comment" && ! grep -qF "/private/var" "$STUB/comment"'
check "one summary line per reviewer, and each reply printed before them" 'said "alpha: findings" && said "beta: no findings" && grep -qxF "## alpha" "$STUB/out" && said "The outside review posted findings on $H: https://example.test/comment"'
check "the checkouts run no hook from the pull request head" '[ ! -f "$STUB/hook_ran" ]'
check "nothing is left behind: no worktree and no private ref" '[ "$(git -C "$root/work" worktree list | wc -l | tr -d " ")" = 1 ] && [ -z "$(git -C "$root/work" for-each-ref refs/mentat)" ]'
rc=$(cd "$root/work" && "$mentat" status 7 2>&1)
check "status: each listed reviewer's state on the last head Claude reviewed, from the comment" 'grep -qF "outside: posted on ${H:0:7} (alpha: findings, beta: no findings; spec fingerprint none; reviewers alpha, beta)" <<<"$rc"'
listing "beta"
reset; rc=$(run 7)
check "every reviewer finishing with nothing exits 0" '[ "$rc" = 0 ] && posted && heading beta && row "beta: no findings" && said "The outside review found nothing on $H: https://example.test/comment"'

# Did not finish: a reviewer that times out, whose tool is missing or fails, never blocks.
listing "beta,slow,delta"
mv "$root/tools/bin/delta-cli" "$root/delta-cli.off"
reset; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1 run 7)
mv "$root/delta-cli.off" "$root/tools/bin/delta-cli"
check "did not finish: the others' results stand, nothing blocks (exit 0)" '[ "$rc" = 0 ] && posted && heading "beta, slow, delta" && row "beta: no findings"'
check "did not finish: a timeout is said in public-safe words, under the one time limit" 'row "slow: did not finish (Slow did not finish within 1 seconds)" && said "slow: did not finish (Slow did not finish within 1 seconds)"'
check "did not finish: a missing tool is said, naming its command" 'row "delta: did not finish (delta-cli is not installed)" && [ "$(ran delta)" = 0 ]'
check "did not finish: the timed-out tool was stopped" 'p=$(cat "$STUB/slow.pid"); ! kill -0 "$p" 2>/dev/null'
listing "alpha,beta"
reset; touch "$STUB/beta.fails"; rc=$(run 7)
check "a failing tool did not finish; its log is named only on stderr, never posted" '[ "$rc" = 2 ] && row "beta: did not finish (beta-tool exited with status 3)" && grep -q "^mentat: beta: its log may hold credentials; the maintainer can read it at " "$STUB/err" && ! grep -q "fake-token" "$STUB/comment" "$STUB/out" "$STUB/err"'
printf 'Could not read it.\n\nREVIEW RESULT: INCOMPLETE - README could not be read\n' >"$STUB/beta.review"
rm -f "$STUB/beta.fails" "$STUB/comment"; rc=$(run 7)
check "an INCOMPLETE reply did not finish, and its reply is still printed and folded" 'row "beta: did not finish (Beta says the review is incomplete)" && grep -qxF "REVIEW RESULT: INCOMPLETE - README could not be read" "$STUB/out" && grep -qxF "<details><summary>Beta</summary>" "$STUB/comment"'
# Failures in a row, keyed by the adapter's name: the second in a row tells the maintainer now.
reset; touch "$STUB/beta.fails"; run 7 >/dev/null; rm -f "$STUB/comment"; rc=$(run 7)
check "the second failure in a row tells the maintainer now, keyed by the adapter's name" 'grep -q "^mentat: tell the maintainer now: Beta has failed 2 times in a row (owner/repo#7): beta-tool exited with status 3" "$STUB/err" && [ -f "$XDG_CACHE_HOME/mentat/reviewer-failures-beta" ]'
rm -f "$STUB/beta.fails"; rm -f "$STUB/comment"; rc=$(run 7)
check "a checked reply ends the row" '[ "$(tail -n 1 "$XDG_CACHE_HOME/mentat/reviewer-failures-beta" | cut -d" " -f2)" = ok ] && ! grep -q "tell the maintainer" "$STUB/err"'
listing "slow,delta"
mv "$root/tools/bin/delta-cli" "$root/delta-cli.off"
reset; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1 run 7)
mv "$root/delta-cli.off" "$root/tools/bin/delta-cli"
check "no reviewer finishes: still posted, one line each, exit 0" '[ "$rc" = 0 ] && posted && row "slow: did not finish (Slow did not finish within 1 seconds)" && row "delta: did not finish (delta-cli is not installed)"'

# A skipped name is named, and the rest run.
listing "beta,nope"
reset; rc=$(run 7)
check "a listed name the module does not ship is skipped and named; the rest run" '[ "$rc" = 0 ] && heading "beta, nope" && row "nope: skipped (the mentat-reviewers module has no such reviewer)" && said "nope: skipped (the mentat-reviewers module has no such reviewer)" && [ "$(ran beta)" = 1 ]'

# Nothing is posted when CI fails on the head or the head moves; findings are still printed.
listing "alpha"
reset; echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"failure"}]}' >"$STUB/check_runs.json"; rc=$(run 7)
check "CI fails on the head: nothing posted (exit 4), the findings printed" '[ "$rc" = 4 ] && ! posted && grep -qF "README:1 says change (blocking)" "$STUB/out" && said "alpha: findings"'
reset; echo "$OLD" >"$STUB/moved_head"; rc=$(run 7)
check "the head moves during the run: nothing posted (exit 3)" '[ "$rc" = 3 ] && ! posted && grep -q "the head moved from $H" "$STUB/err"'
# The publish check holds the comment: kept in a local file, the findings already printed.
reset; mkdir -p "$HOME/.config/mentat"; echo "README:1" >"$HOME/.config/mentat/private-words"; rc=$(run 7)
rm -f "$HOME/.config/mentat/private-words"
check "a held comment is not posted (exit 9), says where it is kept, and the findings are printed" '[ "$rc" = 9 ] && ! posted && grep -q "^mentat: not posted: the comment holds .*; the maintainer can read it at " "$STUB/err" && grep -qF "README:1 says change (blocking)" "$STUB/out"'

# Only after Claude's latest review of the head found nothing.
listing "alpha"
reset; echo '[]' >"$STUB/issue_comments.json"; rc=$(run 7)
check "no Claude review of the head: refused (exit 8), nothing run or posted" '[ "$rc" = 8 ] && ! posted && no_tool_ran && grep -q "Claude has posted no review of $H" "$STUB/err"'
reset; claude_said "$H" findings; rc=$(run 7)
check "Claude's latest review of the head has findings: refused (exit 8)" '[ "$rc" = 8 ] && ! posted && no_tool_ran'
reset; claude_said "$OLD" "no findings"; echo '[]' >"$STUB/issue_comments.json"; claude_said "$OLD" "no findings"; rc=$(run 7)
check "a clean review of another head does not count (exit 8)" '[ "$rc" = 8 ] && no_tool_ran'

# A changed spec and a changed list on one head: each run posts its own comment, and the
# latest is the one status reads.
listing "beta"
reset; printf 'Spec one.\n' >"$root/spec.md"; rc=$(run --request "$root/spec.md" 7)
fp1=$("$mentat" fingerprint "$root/spec.md")
printf 'Spec two.\n' >"$root/spec.md"; fp2=$("$mentat" fingerprint "$root/spec.md")
rm -f "$STUB/comment"; rc=$(run --request "$root/spec.md" 7)
check "a changed spec on one head: a new comment with the new fingerprint" '[ "$rc" = 0 ] && heading beta "$fp2" && [ "$fp1" != "$fp2" ]'
listing "alpha,beta"
rm -f "$STUB/comment"; rc=$(run --request "$root/spec.md" 7)
check "a changed list on one head: a new comment with the new list" '[ "$rc" = 2 ] && heading "alpha, beta" "$fp2"'
out=$(cd "$root/work" && "$mentat" status 7 --request "$root/spec.md" 2>&1)
check "status reads the latest outside comment on the head, with its spec and list" 'grep -qF "outside: posted on ${H:0:7} (alpha: findings, beta: no findings; spec fingerprint $fp2, spec matches; reviewers alpha, beta)" <<<"$out"'

# Module on with no list, off, unknown: nothing runs or posts (exit 6).
settings '{"enabledPlugins":{"mentat-reviewers@mentat":true}}'
reset; rc=$(run 7)
check "the module on with no list: none runs, nothing posted (exit 6), saying none listed" '[ "$rc" = 6 ] && ! posted && no_tool_ran && grep -q "none listed" "$STUB/err"'
rc=$(cd "$root/work" && "$mentat" reviewers 2>&1)
check "mentat reviewers says on, none listed" '[ "$rc" = "reviewers: on, none listed" ]'
settings '{"enabledPlugins":{"mentat-reviewers@mentat":false},"env":{"MENTAT_REVIEWERS":"alpha"}}'
reset; rc=$(run 7)
check "the module off: nothing runs or posts (exit 6)" '[ "$rc" = 6 ] && ! posted && no_tool_ran'
settings '{"enabledPlugins":{"mentat-reviewers@mentat":true},"env":{"MENTAT_REVIEWERS":"Alpha"}}'
reset; rc=$(run 7)
check "a malformed list: unknown, naming why; nothing runs or posts (exit 6)" '[ "$rc" = 6 ] && ! posted && no_tool_ran && grep -q "MENTAT_REVIEWERS in .claude/settings.json on main holds a name" "$STUB/err"'
listing "alpha"
reset; rc=$(MENTAT_REVIEWERS=beta run 7)
check "the process environment's MENTAT_REVIEWERS is not read" '[ "$(ran alpha)" = 1 ] && [ "$(ran beta)" = 0 ]'
reset; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=0 run 7)
check "a time limit of 0 is a usage error (exit 64); nothing runs" '[ "$rc" = 64 ] && no_tool_ran && grep -qF "MENTAT_REVIEW_TIMEOUT_SECONDS must be a whole number of 1 or more" "$STUB/err"'
reset; rc=$(run x)
check "a bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ] && grep -qF "usage: mentat review --outside [--request <file>] [--require-ci] <pull request number>" "$STUB/err"'

# Second opinion: every listed, available reviewer, in parallel; 0 with a verdict, 1 with
# none, 6 with none listed and nothing sent.
printf 'An idea.\n' >"$root/idea.md"
opinion() { (cd "$root/work" && git checkout -q main && git pull -q origin main && "$mentat" second-opinion "$root/idea.md" >"$STUB/out" 2>"$STUB/err"); echo $?; }
listing "alpha,beta,nope"
reset; touch "$STUB/expect_alpha" "$STUB/expect_beta"; rc=$(opinion)
check "second opinion: each listed reviewer gives a verdict, in parallel, in opinion mode (exit 0)" '[ "$rc" = 0 ] && grep -qF -- "- Alpha (" "$STUB/out" && grep -q "^- Beta (.*): SECOND OPINION VERDICT: DO IT$" "$STUB/out" && [ -f "$STUB/alpha.together" ] && [ "$(grep -c " opinion " "$STUB/tool_calls")" = 2 ] && grep -q "An idea." "$STUB/alpha.prompt"'
check "second opinion: an unshipped name is skipped and named; nothing posted; no head hook ran" 'grep -q "^- nope (.*): no second opinion (skipped: the mentat-reviewers module has no such reviewer)$" "$STUB/out" && ! grep -q "^pr comment" "$STUB/calls" 2>/dev/null && [ ! -f "$STUB/hook_ran" ]'
listing "slow"
reset; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1 opinion)
check "second opinion: none delivered (exit 1)" '[ "$rc" = 1 ] && grep -q "^- Slow (.*): no second opinion (Slow did not finish within 1 seconds)$" "$STUB/out"'
settings '{"enabledPlugins":{"mentat-reviewers@mentat":true}}'
reset; rc=$(opinion)
check "second opinion: none listed, nothing sent (exit 6)" '[ "$rc" = 6 ] && no_tool_ran && grep -q "none listed" "$STUB/err"'

[ "$failures" -eq 0 ]
