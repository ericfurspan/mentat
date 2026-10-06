#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat review --local`, using a real git origin, a stub gh
# and a stub codex. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: review --local %s\n' "$1"; else printf 'FAIL: review --local %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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
# pr comment records the body, or fails when comment_fails exists.
cat >"$root/bin/gh" <<'STUBEOF'
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
  "repo view") echo owner/repo ;;
  "issue view")
    [ -f "$STUB/issue_$3" ] || exit 1
    printf 'Issue #%s: %s\n\n%s' "$3" "$(head -1 "$STUB/issue_$3")" "$(tail -n +2 "$STUB/issue_$3")" ;;
  "api --paginate")
    case "$3" in
      */check-runs) cat "$STUB/check_runs.json" ;;
      */status) echo '{"statuses":[]}' ;;
      *) exit 99 ;;
    esac ;;
  "pr comment")
    [ -f "$STUB/comment_fails" ] && exit 1
    while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$STUB/comment"; shift; done
    echo https://example.test/comment ;;
  *) exit 99 ;;
esac
STUBEOF
# codex: records where it ran and what it read, then replies with $STUB/reply.
cat >"$root/bin/codex" <<'STUBEOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo codex-stub; exit 0; }
printf '%s\n' "$@" >"$STUB/args"
cat >"$STUB/prompt"
git rev-parse HEAD >"$STUB/codex_head"; cat README >"$STUB/codex_readme"
while [ $# -gt 0 ]; do [ "$1" = -o ] && cp "$STUB/reply" "$2"; shift; done
STUBEOF
chmod +x "$root/bin/gh" "$root/bin/codex"
export PATH="$root/bin:$PATH"

reset() {
  rm -f "$STUB"/*
  echo "$H" >"$STUB/head"
  printf 'Nothing to flag.\n\nREVIEW RESULT: NO FINDINGS\n' >"$STUB/reply"
  echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' >"$STUB/check_runs.json"
}
run() { (cd "$root/work" && "$mentat" review --local 7 >"$STUB/out" 2>&1); echo $?; }
posted() { [ -f "$STUB/comment" ]; }

reset; echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"failure"}]}' >"$STUB/check_runs.json"; rc=$(run)
check "failed CI is not reviewed (exit 4): Codex does not run and nothing is posted" '[ "$rc" = 4 ] && grep -q "CI did not pass on $H" "$STUB/out" && [ ! -f "$STUB/prompt" ] && ! posted'
reset; rc=$(run)
check "no findings exits 0 and posts the review" '[ "$rc" = 0 ] && grep -q "found nothing on $H: https://example.test/comment" "$STUB/out" && grep -q "^## Local Codex review of $H" "$STUB/comment"'
check "reviews the pull request head, not the dirty checkout" '[ "$(cat "$STUB/codex_head")" = "$H" ] && [ "$(cat "$STUB/codex_readme")" = change ]'
check "reviews the change from the merge base" 'grep -q "git diff $BASE $H" "$STUB/prompt" && grep -q "Change reviewed: $BASE..$H" "$STUB/comment"'
check "gives Codex the pull request description as data" 'grep -q "Requirement: README says change." "$STUB/prompt" && grep -q "BEGIN PULL REQUEST DATA" "$STUB/prompt"'
# The issues the pull request closes reach Codex as labeled data, ahead of the description.
reset; echo '[{"number":3}]' >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_3"; rc=$(run)
check "gives Codex the linked issue's request as data" '[ "$rc" = 0 ] && grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt" && grep -q "Issue #3: Make the README say change" "$STUB/prompt" && grep -q "The README must say change, nothing else." "$STUB/prompt"'
reset; echo '[{"number":4}]' >"$STUB/closes"; rc=$(run)
check "a linked issue that cannot be read is not reviewed" '[ "$rc" = 1 ] && grep -q "could not read issue #4" "$STUB/out" && [ ! -f "$STUB/prompt" ]'
reset; rc=$(run)
check "no linked issue: no issue block" '[ "$rc" = 0 ] && ! grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt"'
check "turns web search off for reviews" 'grep -qx "web_search=\"disabled\"" "$STUB/args"'
# The stub is not Codex, so its environment says nothing about Codex's shell; the options do.
reset; rc=$(cd "$root/work" && "$mentat" review --local 7 >"$STUB/out" 2>&1; echo $?)
gitdir=$(git -C "$root/work" rev-parse --path-format=absolute --git-common-dir)
check "limits Codex's shell to core environment variables and no user git config" '[ "$rc" = 0 ] && grep -qx "shell_environment_policy.inherit=\"core\"" "$STUB/args" && grep -qx "shell_environment_policy.set={GIT_CONFIG_GLOBAL=\"/dev/null\"}" "$STUB/args"'
check "the profile reads the main checkout's git directory, which a worktree's .git points to" '[ "$rc" = 0 ] && case "$gitdir" in */work/.git) true ;; *) false ;; esac && grep -qF "\"$gitdir\"=\"read\"" "$STUB/args" && ! grep -q -- "--sandbox" "$STUB/args"'
check "removes its worktree" '[ "$(git -C "$root/work" worktree list | wc -l | tr -d " ")" = 1 ]'

reset; printf -- '- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS\n' >"$STUB/reply"; rc=$(run)
check "findings exit 2 and are posted" '[ "$rc" = 2 ] && grep -q "posted findings on $H" "$STUB/out" && grep -q "P1 README:1" "$STUB/comment"'

reset; printf 'Looks fine to me.\n' >"$STUB/reply"; rc=$(run)
check "a reply without a result line is not reviewed and not posted" '[ "$rc" = 1 ] && grep -q "no final REVIEW RESULT line" "$STUB/out" && ! posted'

reset; echo 3333333333333333333333333333333333333333 >"$STUB/moved_head"; rc=$(run)
check "a head that moves during the review is not posted (exit 3)" '[ "$rc" = 3 ] && ! posted'

reset; echo 4444444444444444444444444444444444444444 >"$STUB/head"; rc=$(run)
check "a head GitHub reports that the fetch does not match is exit 3" '[ "$rc" = 3 ] && [ ! -f "$STUB/prompt" ]'

reset; touch "$STUB/comment_fails"; rc=$(run)
check "a failed post is not reviewed" '[ "$rc" = 1 ] && grep -q "could not post the review" "$STUB/out"'

rc=$("$mentat" review --local abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
