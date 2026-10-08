#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat review --local`, using a real git origin, a stub gh
# and a stub codex. Prints PASS/FAIL per case; exits 1 on any FAIL. One case also
# replays the permissions settings the review passes to Codex through the real
# `codex sandbox` (macOS only, no model call): see "Live sandbox check" below.
set -uo pipefail

# Probe mode, run by the codex stub inside the review (its working directory is the
# review worktree, which mentat removes on exit). Writes $STUB/live_results: one
# line "control|<reason>" when a control fails, otherwise a line
# "probe|<expected>|<observed>|<name>|<detail>" per probe. Never run outside the test.
live_probe() {
  local res="$STUB/live_results" cargs=() line prev="" home f out rc got detail
  : >"$res"
  control() { printf 'control|%s\n' "$1" >>"$res"; }
  # Controls first, outside the sandbox: each fixture exists and is readable here, the
  # write target is writable, the worktree is not under a path the profile denies.
  case "$(pwd -P)" in /tmp/* | /private/tmp/*) control "the review worktree $(pwd -P) is under /tmp, which the profile denies"; return 0 ;; esac
  # shellcheck disable=SC2086 # the fixture names have no spaces
  for f in README $LIVE_FIXTURES; do
    { [ -f "$f" ] && [ -r "$f" ]; } || { control "fixture $f is missing or unreadable in the review worktree"; return 0; }
  done
  { : >live-write-control && rm -f live-write-control; } 2>/dev/null || { control "the review worktree is not writable"; return 0; }
  git diff --name-only "$LIVE_BASE" "$LIVE_HEAD" 2>/dev/null | grep -qx README || { control "git diff $LIVE_BASE $LIVE_HEAD does not list README outside the sandbox"; return 0; }
  # The same script is the control (outside the sandbox) and the probe: sh expands $1.
  tcp='/bin/bash -c "exec 3<>/dev/tcp/127.0.0.1/$1"'
  sh -c "$tcp" sh "$LIVE_PORT" 2>/dev/null || { control "the local listener does not accept a connection"; return 0; }
  # The settings Codex got, minus what is not a -c setting (exec-only arguments).
  while IFS= read -r line; do
    [ "$prev" = -c ] && cargs+=(-c "$line")
    prev=$line
  done <"$STUB/args"
  home=$(mktemp -d) || { control "could not create an empty CODEX_HOME"; return 0; }
  if [ "${#cargs[@]}" -eq 0 ]; then printf 'probe|allowed|broken|settings|no -c settings were captured\n' >>"$res"; return 0; fi
  # probe <allowed|denied> <name> <sh script> [arguments]: runs the script under the
  # real `codex sandbox` with the captured settings. Exit 0 is allowed; a failure whose
  # output is the operating system refusing is denied; any other failure is broken.
  probe() {
    local want=$1 name=$2 script=$3
    shift 3
    out=$(CODEX_HOME="$home" "$LIVE_CODEX" sandbox "${cargs[@]}" -- sh -c "$script" sh "$@" 2>&1 </dev/null)
    rc=$?
    if [ "$rc" -eq 0 ]; then
      got=allowed
    else
      case "$out" in *"Operation not permitted"* | *"Permission denied"* | *"Read-only file system"*) got=denied ;; *) got=broken ;; esac
    fi
    detail=""
    [ "$got" = allowed ] || detail=$(printf '%s\n' "$out" | grep -m1 -E 'Operation not permitted|Permission denied|Read-only file system' || printf '%s\n' "$out" | head -n 1)
    printf 'probe|%s|%s|%s|exit %s: %s\n' "$want" "$got" "$name" "$rc" "$detail" >>"$res"
  }
  probe allowed "reads a tracked file" 'cat "$1" >/dev/null' README
  probe allowed "git diff <base> <head>" 'git diff --name-only "$1" "$2" | grep -qx README' "$LIVE_BASE" "$LIVE_HEAD"
  # shellcheck disable=SC2086 # the fixture names have no spaces
  for f in $LIVE_FIXTURES; do
    probe denied "reads $f" 'cat "$1" >/dev/null' "$f"
  done
  probe denied "reads a file outside the checkout" 'cat "$1" >/dev/null' "$LIVE_OUTSIDE"
  probe denied "reads a file under /tmp" 'cat "$1" >/dev/null' "$LIVE_TMPFILE"
  probe denied "writes a new file into the worktree" 'echo x >live-write-probe'
  if [ -e live-write-probe ]; then
    rm -f live-write-probe
    printf 'probe|denied|allowed|the write left a file behind|live-write-probe exists afterward\n' >>"$res"
  fi
  probe denied "connects to a local TCP listener" "$tcp" "$LIVE_PORT"
  rm -rf "$home"
}
[ "${1:-}" = --probe ] && { live_probe; exit 0; }

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
listener="" live_tmp=""
cleanup() { [ -z "$listener" ] || kill "$listener" 2>/dev/null; rm -rf "$root" "$live_tmp"; }
trap cleanup EXIT
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
    r=$5; f="$STUB/issue_${r/\//_}_$3"
    [ "$4" = --repo ] && [ -f "$f" ] || exit 1
    printf 'Issue %s#%s: %s\n\n%s' "$r" "$3" "$(head -1 "$f")" "$(tail -n +2 "$f")" ;;
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
[ ! -f "$STUB/live" ] || "$LIVE_SELF" --probe
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
run() { (cd "$root/work" && "$mentat" review --local "${1:-7}" >"$STUB/out" 2>&1); echo $?; }
posted() { [ -f "$STUB/comment" ]; }

reset; echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"failure"}]}' >"$STUB/check_runs.json"; rc=$(run)
check "failed CI is not reviewed (exit 4): Codex does not run and nothing is posted" '[ "$rc" = 4 ] && grep -q "CI did not pass on $H" "$STUB/out" && [ ! -f "$STUB/prompt" ] && ! posted'
reset; rc=$(run)
check "no findings exits 0 and posts the review" '[ "$rc" = 0 ] && grep -q "found nothing on $H: https://example.test/comment" "$STUB/out" && grep -q "^## Local Codex review of $H" "$STUB/comment"'
check "reviews the pull request head, not the dirty checkout" '[ "$(cat "$STUB/codex_head")" = "$H" ] && [ "$(cat "$STUB/codex_readme")" = change ]'
check "reviews the change from the merge base" 'grep -q "git diff $BASE $H" "$STUB/prompt" && grep -q "Change reviewed: $BASE..$H" "$STUB/comment"'
check "gives Codex the pull request description as data" 'grep -q "Requirement: README says change." "$STUB/prompt" && grep -q "BEGIN PULL REQUEST DATA" "$STUB/prompt"'
# The issues the pull request closes reach Codex as labeled data, ahead of the description.
ref() { printf '{"number":%s,"repository":{"name":"%s","owner":{"login":"%s"}}}' "$3" "$2" "$1"; }
reset; echo "[$(ref owner repo 3)]" >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_owner_repo_3"; rc=$(run)
check "gives Codex the linked issue's request as data" '[ "$rc" = 0 ] && grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt" && grep -q "Issue owner/repo#3: Make the README say change" "$STUB/prompt" && grep -q "The README must say change, nothing else." "$STUB/prompt"'
reset; echo "[$(ref other proj 9)]" >"$STUB/closes"; printf 'Fix the other thing\nIn the other repository.\n' >"$STUB/issue_other_proj_9"; printf 'Wrong issue\nSame number, wrong repository.\n' >"$STUB/issue_owner_repo_9"; rc=$(run)
check "reads a linked issue from its own repository" '[ "$rc" = 0 ] && grep -q "Issue other/proj#9: Fix the other thing" "$STUB/prompt" && ! grep -q "Wrong issue" "$STUB/prompt"'
reset; echo "[$(ref owner repo 4)]" >"$STUB/closes"; rc=$(run)
check "a linked issue that cannot be read is not reviewed" '[ "$rc" = 1 ] && grep -q "could not read issue owner/repo#4" "$STUB/out" && [ ! -f "$STUB/prompt" ]'
reset; rc=$(run)
check "no linked issue: no issue block" '[ "$rc" = 0 ] && ! grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt"'
check "turns web search off for reviews" 'grep -qx "web_search=\"disabled\"" "$STUB/args"'
# The stub is not Codex, so its environment says nothing about Codex's shell; the options do.
reset; rc=$(cd "$root/work" && "$mentat" review --local 7 >"$STUB/out" 2>&1; echo $?)
gitdir=$(git -C "$root/work" rev-parse --path-format=absolute --git-common-dir)
check "limits Codex's shell to core environment variables and no user git config" '[ "$rc" = 0 ] && grep -qx "shell_environment_policy.inherit=\"core\"" "$STUB/args" && grep -qx "shell_environment_policy.set={GIT_CONFIG_GLOBAL=\"/dev/null\"}" "$STUB/args"'
check "the profile reads the main checkout's git directory, which a worktree's .git points to" '[ "$rc" = 0 ] && case "$gitdir" in */work/.git) true ;; *) false ;; esac && grep -qF "\"$gitdir\"=\"read\"" "$STUB/args" && ! grep -q -- "--sandbox" "$STUB/args"'
check "denies credential files inside the checkout for reviews too" 'grep -qF "\"**/.env\"=\"deny\"" "$STUB/args" && grep -qx "permissions.mentat-review.filesystem.glob_scan_max_depth=8" "$STUB/args"'
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

# Live sandbox check. Replays the -c settings the review passed to the stub through the
# real `codex sandbox` (no model call) and runs shell probes against the review
# worktree. It does not prove that `codex exec --ignore-user-config --strict-config`
# behaves the same, and it says nothing about Linux or model-backed behavior.
# A control that fails (the outer sandbox of an agent session may block one) is SKIP,
# and FAIL in CI. A probe that is broken (the launcher failed) always fails.
live="review --local live sandbox"
live_skip() {
  if [ "${CI:-}" = "true" ]; then
    printf 'FAIL: %s: %s (required in CI)\n' "$live" "$1"
    failures=$((failures + 1))
  else
    printf 'SKIP: %s: %s\n' "$live" "$1"
  fi
}
live_run() {
  local d self real_codex="" outside port="" i probes=0 bad=0 kind want got name detail
  # The real Codex: on PATH, outside the stub directory.
  local IFS=:
  # shellcheck disable=SC2086 # split PATH on colons
  for d in $PATH; do
    [ "$d" != "$root/bin" ] && [ -x "$d/codex" ] && { real_codex="$d/codex"; break; }
  done
  IFS=$' \t\n'
  [ -n "$real_codex" ] || { live_skip "codex is not installed"; return 0; }
  # Controls that need no worktree.
  case "$(cd -P "$root" && pwd -P)" in
    /tmp/* | /private/tmp/*) live_skip "the test's temporary directory is under /tmp, which the profile denies"; return 0 ;;
  esac
  outside="$(cd -P "$(dirname "$mentat")/.." && pwd -P)/tests/run"
  case "$outside" in
    /opt/homebrew/* | /usr/local/* | /tmp/* | /private/tmp/* | "$root"/*) live_skip "$outside is under a path the profile allows or denies for another reason"; return 0 ;;
  esac
  [ -r "$outside" ] || { live_skip "$outside is not readable"; return 0; }
  live_tmp=$(mktemp /tmp/mentat-live.XXXXXX 2>/dev/null) || { live_skip "could not create a file under /tmp"; return 0; }
  echo fake >"$live_tmp" || { live_skip "could not write $live_tmp"; return 0; }
  [ -r "$live_tmp" ] || { live_skip "$live_tmp is not readable"; return 0; }
  command -v perl >/dev/null 2>&1 || { live_skip "perl is not installed, so there is no local listener"; return 0; }
  perl -MIO::Socket::INET -e '$| = 1; my $s = IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1", LocalPort => 0, ReuseAddr => 1) or exit 1; print $s->sockport, "\n"; while (my $c = $s->accept) { close $c }' >"$root/port" 2>/dev/null &
  listener=$!
  disown "$listener" 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do
    port=$(cat "$root/port" 2>/dev/null)
    [ -z "$port" ] || break
    sleep 0.5
  done
  case "$port" in '' | *[!0-9]*) live_skip "no local listener could start"; return 0 ;; esac

  # A pull request head with one fake fixture per credential rule, nested ones too.
  LIVE_FIXTURES=".env
.env.local
nested/deep/cert.pem
server.key
store.p12
store.pfx
id_rsa
id_ecdsa
keys/id_ed25519_work
nested/.netrc
.npmrc
.pypirc"
  (cd "$root/seed" && git checkout -q main && git checkout -qb live &&
    echo live >README &&
    while IFS= read -r f; do mkdir -p "$(dirname "$f")" && echo fake >"$f"; done <<<"$LIVE_FIXTURES" &&
    git add -A && git commit -qm fixtures && git push -q "$root/origin.git" HEAD:refs/pull/9/head) || { live_skip "could not build the pull request head"; return 0; }
  self=$(cd "$(dirname "$0")" && pwd) || { live_skip "could not find this script's directory"; return 0; }
  export LIVE_FIXTURES LIVE_CODEX="$real_codex" LIVE_PORT="$port" LIVE_TMPFILE="$live_tmp" LIVE_OUTSIDE="$outside" LIVE_BASE="$BASE" LIVE_SELF="$self/${0##*/}"
  LIVE_HEAD=$(git -C "$root/seed" rev-parse HEAD) && export LIVE_HEAD

  reset; echo "$LIVE_HEAD" >"$STUB/head"; : >"$STUB/live"
  rc=$(run 9)
  if [ "$rc" != 0 ] || [ ! -s "$STUB/live_results" ]; then
    printf 'FAIL: %s: the review did not run the probes (exit %s)\n' "$live" "$rc"
    failures=$((failures + 1))
    return 0
  fi
  if grep -q '^control|' "$STUB/live_results"; then
    live_skip "$(sed -n 's/^control|//p' "$STUB/live_results" | head -n 1)"
    return 0
  fi
  while IFS='|' read -r kind want got name detail; do
    [ "$kind" = probe ] || continue
    probes=$((probes + 1))
    if [ "$want" = "$got" ]; then
      printf 'PASS: %s: %s: %s (%s)\n' "$live" "$want" "$name" "$detail"
    else
      printf 'FAIL: %s: expected %s, observed %s: %s (%s)\n' "$live" "$want" "$got" "$name" "$detail"
      bad=$((bad + 1))
    fi
  done <"$STUB/live_results"
  failures=$((failures + bad))
  if [ "$bad" -eq 0 ] && [ "$probes" -gt 0 ]; then
    printf 'PASS: %s: %s probes matched with %s and Claude Code %s\n' "$live" "$probes" "$("$real_codex" --version 2>/dev/null | head -n 1)" "$(claude --version 2>/dev/null | awk '{print $1}')"
  elif [ "$probes" -eq 0 ]; then
    printf 'FAIL: %s: no probes ran\n' "$live"
    failures=$((failures + 1))
  fi
}
if [ "$(uname)" != Darwin ]; then
  printf 'SKIP: %s: %s sandboxing differs from macOS, where Mentat runs\n' "$live" "$(uname)"
else
  live_run
fi

[ "$failures" -eq 0 ]
