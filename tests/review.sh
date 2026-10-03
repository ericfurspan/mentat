#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs, so single-
# quoted variables and assignments read only inside those strings are intended.)
# Behavior tests for `mentat review`, using stub gh and codex commands and a
# local origin repository. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: review %s\n' "$1"; else printf 'FAIL: review %s\n' "$1"; failures=$((failures + 1)); fi; }

cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo '{"nameWithOwner":"owner/repo"}' ;;
  "pr view")
    n=$(($(cat "$STUB/pr_calls" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/pr_calls"
    if [ "$n" -gt 1 ] && [ -f "$STUB/head_after" ]; then
      jq --arg h "$(cat "$STUB/head_after")" '.headRefOid = $h' "$STUB/pr.json"
    else cat "$STUB/pr.json"; fi ;;
  "issue view") echo '{"title":"Issue title","body":"Issue requirement"}' ;;
  "pr comment") while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$STUB/posted.md"; shift; done
    echo "https://example.test/comment" ;;
  *) exit 99 ;;
esac
EOF
cat >"$root/bin/codex" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = --version ]; then echo "codex-cli 0.0-stub"; exit 0; fi
printf '%s\n' "$@" >"$STUB/args"
out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
cat >"$STUB/prompt"
[ -f "$STUB/codex_ignore_term" ] && trap '' TERM
[ -f "$STUB/codex_sleep" ] && sleep "$(cat "$STUB/codex_sleep")"
[ -f "$STUB/codex_out" ] && cp "$STUB/codex_out" "$out"
exit "$(cat "$STUB/codex_exit" 2>/dev/null || echo 0)"
EOF
chmod +x "$root/bin/gh" "$root/bin/codex"
export PATH="$root/bin:$PATH"

# A local origin with base branch trunk (not main, so machine-wide git hooks guarding main never apply) and a pull request head at refs/pull/7/head.
git init -q --bare "$root/owner/repo.git"
git init -q -b trunk "$root/work" && cd "$root/work" || exit 1
git config user.email t@example.test && git config user.name test
git commit -q --allow-empty -m base
git remote add origin "$root/owner/repo.git" && git push -q origin trunk
base_sha=$(git rev-parse HEAD)
echo change >file && git add file && git commit -q -m change
head_sha=$(git rev-parse HEAD)
git push -q origin "HEAD:refs/pull/7/head" && git checkout -q --detach

pr_json() { printf '{"headRefOid":"%s","baseRefName":"trunk","baseRefOid":"%s","title":"Add file","body":"PR requirement","isCrossRepository":%s,"closingIssuesReferences":[{"url":"https://example.test/issues/1"}]}\n' "$head_sha" "$base_sha" "$1" >"$STUB/pr.json"; }
reset() { rm -f "$STUB"/*; pr_json false; printf 'One finding.\n\nREVIEW STATUS: COMPLETE\n' >"$STUB/codex_out"; }
run() { "$mentat" review 7 >/dev/null 2>&1; echo $?; }

reset; rc=$(run)
check "posts a complete review (exit 0)" '[ "$rc" = 0 ] && [ -f "$STUB/posted.md" ]'
check "header names head, base and merge-base" 'grep -q "Head: $head_sha" "$STUB/posted.md" && grep -q "Base: trunk @ $base_sha" "$STUB/posted.md" && grep -q "Merge-base: $base_sha" "$STUB/posted.md"'
check "posts Codex's message unedited" 'tail -n 3 "$STUB/posted.md" | diff - "$STUB/codex_out" >/dev/null'
check "runs plain codex exec, not review mode" '[ "$(head -n 1 "$STUB/args")" = exec ] && ! grep -qx review "$STUB/args"'
check "pins model, effort and read-only sandbox" 'grep -qx "model=\"gpt-6.1-sol\"" "$STUB/args" && grep -qx "model_reasoning_effort=\"high\"" "$STUB/args" && grep -A1 -x -- "--sandbox" "$STUB/args" | grep -qx read-only'
check "prompt names the commits and requirements" 'grep -q "git diff $base_sha $head_sha" "$STUB/prompt" && grep -q "PR requirement" "$STUB/prompt" && grep -q "Issue requirement" "$STUB/prompt"'
check "removes its worktree" '[ "$(git worktree list | wc -l)" -eq 1 ]'

reset; echo 1 >"$STUB/codex_exit"; rc=$(run)
check "codex failure is not reviewed (exit 1)" '[ "$rc" = 1 ] && [ ! -f "$STUB/posted.md" ]'
reset; rm "$STUB/codex_out"; rc=$(run)
check "no final message is not reviewed" '[ "$rc" = 1 ] && [ ! -f "$STUB/posted.md" ]'
reset; printf 'Looks fine.\n' >"$STUB/codex_out"; rc=$(run)
check "missing status line is not reviewed" '[ "$rc" = 1 ] && [ ! -f "$STUB/posted.md" ]'
reset; printf 'REVIEW STATUS: INCOMPLETE - could not inspect\n' >"$STUB/codex_out"; rc=$(run)
check "INCOMPLETE is not reviewed" '[ "$rc" = 1 ] && [ ! -f "$STUB/posted.md" ]'
reset; echo 3 >"$STUB/codex_sleep"; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1 run)
check "timeout is not reviewed" '[ "$rc" = 1 ] && [ ! -f "$STUB/posted.md" ]'
reset; echo 30 >"$STUB/codex_sleep"; touch "$STUB/codex_ignore_term"; start=$(date +%s); rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1 run)
check "timeout ends a reviewer that ignores SIGTERM" '[ "$rc" = 1 ] && [ $(($(date +%s) - start)) -lt 15 ]'
# A narrowed fetch mapping and a stale origin/trunk must not change the base.
git update-ref refs/remotes/origin/trunk "$head_sha"
git config remote.origin.fetch '+refs/heads/none:refs/remotes/origin/none'
reset; rc=$(run)
check "uses the fetched base, not a stale origin/<base>" '[ "$rc" = 0 ] && grep -q "Base: trunk @ $base_sha" "$STUB/posted.md"'
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
# A mirror at the same owner/repo path elsewhere, with a different base, is refused.
git clone -q --bare "$root/owner/repo.git" "$root/elsewhere/owner/repo.git"
git -C "$root/work" commit -q --allow-empty -m other && git push -q "$root/elsewhere/owner/repo.git" HEAD:trunk
git remote set-url origin "$root/elsewhere/owner/repo.git"
reset; rc=$(run)
check "refuses a base that is not GitHub's" '[ "$rc" = 1 ] && [ ! -f "$STUB/args" ] && [ ! -f "$STUB/posted.md" ]'
git remote set-url origin "$root/owner/repo.git"
reset; pr_json true; rc=$(run)
check "fork pull request is refused" '[ "$rc" = 1 ] && [ ! -f "$STUB/args" ] && [ ! -f "$STUB/posted.md" ]'
reset; echo 0000000000000000000000000000000000000000 >"$STUB/head_after"; rc=$(run)
check "moved head posts with a note (exit 3)" '[ "$rc" = 3 ] && grep -q "head moved" "$STUB/posted.md"'
rc=$("$mentat" review abc >/dev/null 2>&1; echo $?)
check "bad pull request number is a usage error (exit 2)" '[ "$rc" = 2 ]'

[ "$failures" -eq 0 ]
