#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for lib/agent-merge.sh, the one reader of the agent-merge settings, and
# for `mentat agent-merge <N>`, on temporary git repositories with an origin remote and a
# stub gh. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mentat="$root/bin/mentat"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export STUB="$tmp/stub"
mkdir -p "$STUB" "$tmp/bin"
failures=0
check() { if eval "$2"; then printf 'PASS: agent-merge %s\n' "$1"; else printf 'FAIL: agent-merge %s\n' "$1"; failures=$((failures + 1)); fi; }

export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
unset MENTAT_AGENT_MERGE MENTAT_MERGE_WAIT_PATHS

# shellcheck source=lib/agent-merge.sh
. "$root/lib/agent-merge.sh"

# mkrepo <settings JSON text or "-" for no settings file>: a bare origin and a clone of it
# with one commit on main, origin/HEAD set; sets repo (the clone) and origin.
n=0
mkrepo() {
  n=$((n + 1))
  origin="$tmp/origin$n.git"
  repo="$tmp/work$n"
  git init -q --bare "$origin"
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  git clone -q "$origin" "$repo" 2>/dev/null
  git -C "$repo" checkout -q -b main
  mkdir -p "$repo/docs" "$repo/hooks"
  printf 'a\n' >"$repo/docs/a.md"
  printf 'a\n' >"$repo/hooks/a"
  if [ "$1" != - ]; then mkdir -p "$repo/.claude"; printf '%s\n' "$1" >"$repo/.claude/settings.json"; fi
  git -C "$repo" add -A
  git -C "$repo" commit -q -m first
  git -C "$repo" push -q origin main 2>/dev/null
  git -C "$repo" remote set-head origin main
}
settings() { jq -cn --arg a "$1" --arg w "$2" '{env: ({MENTAT_AGENT_MERGE: $a} + (if $w == "-" then {} else {MENTAT_MERGE_WAIT_PATHS: $w} end))}'; }
# change <repo> <branch> <action>...: on a branch cut from origin/main, runs each action
# (add <path>, mv <from> <to>, rm <path>) and commits; prints the new commit.
change() {
  local r=$1 b=$2 a
  shift 2
  git -C "$r" checkout -q -B "$b" origin/main
  while [ $# -gt 0 ]; do
    a=$1
    case "$a" in
      add) mkdir -p "$r/$(dirname "$2")"; printf 'x\n' >"$r/$2"; git -C "$r" add -- "$2"; shift 2 ;;
      mv) mkdir -p "$r/$(dirname "$3")"; git -C "$r" mv "$2" "$3"; shift 3 ;;
      rm) git -C "$r" rm -q -- "$2"; shift 2 ;;
    esac
  done
  git -C "$r" commit -q -m change
  git -C "$r" rev-parse HEAD
}

# The setting: only the value on, only from the committed file on origin's default branch.
mkrepo "$(settings on -)"
ref=$(am_ref "$repo")
check "am_ref names origin's default branch from the local origin/HEAD" '[ "$ref" = refs/remotes/origin/main ]'
check "the value on turns it on" '[ "$(am_agent_merge "$repo" "$ref")" = on ]'
for v in off ON "on " yes 1 true ""; do
  mkrepo "$(settings "$v" -)"
  check "the value \"$v\" is off" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
done
mkrepo '{"env": {"OTHER": "on"}}'
check "no key is off" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
mkrepo '{"env": "on"}'
check "an env that is not an object is off" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
mkrepo '{"env": {"MENTAT_AGENT_MERGE": true}}'
check "a value that is not a string is off" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
mkrepo 'not json'
check "a file that is not JSON is off" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
mkrepo -
check "no settings file is off" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
mkrepo "$(settings off -)"
printf '%s\n' "$(settings on -)" >"$repo/.claude/settings.json"
mkdir -p "$repo/.claude" && printf '%s\n' "$(settings on -)" >"$repo/.claude/settings.local.json"
check "the working tree and local settings never count" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
check "the process environment never counts" '[ "$(MENTAT_AGENT_MERGE=on am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
git -C "$repo" checkout -q -b other
git -C "$repo" add -A && git -C "$repo" commit -q -m other
check "another branch never counts" '[ "$(am_agent_merge "$repo" "$(am_ref "$repo")")" = off ]'
n=$((n + 1))
git init -q "$tmp/no-origin"
check "no origin/HEAD has no ref" '! am_ref "$tmp/no-origin" >/dev/null 2>&1'
check "a folder that is not a repository has no ref" '! am_ref "$tmp" >/dev/null 2>&1'

# The wait list: .github/ and .claude/ always, then the setting's entries.
mkrepo "$(settings on -)"
ref=$(am_ref "$repo")
check "the wait list holds .github/ and .claude/ with no second setting" '[ "$(am_wait_list "$repo" "$ref" | tr "\n" " ")" = ".github/ .claude/ " ]'
mkrepo "$(settings on 'hooks/, lib/agent-merge.sh  CHANGELOG.md
docs/x/')"
ref=$(am_ref "$repo")
check "entries are separated by commas and whitespace" '[ "$(am_wait_list "$repo" "$ref" | tr "\n" " ")" = ".github/ .claude/ hooks/ lib/agent-merge.sh CHANGELOG.md docs/x/ " ]'
mkrepo '{"env": {"MENTAT_AGENT_MERGE": "on", "MENTAT_MERGE_WAIT_PATHS": ["hooks/"]}}'
check "a list that is not a string cannot be read" '! am_wait_list "$repo" "$(am_ref "$repo")" >/dev/null 2>&1'
mkrepo 'not json'
check "a settings file that is not JSON gives no list" '! am_wait_list "$repo" "$(am_ref "$repo")" >/dev/null 2>&1'

# The protected paths a commit touches, from the merge base of origin's default branch.
mkrepo "$(settings on 'hooks/ CHANGELOG.md lib/agent-merge.sh')"
ref=$(am_ref "$repo")
touched() { am_protected "$repo" "$ref" "$1" || return 1; printf "ok:"; [ -z "$am_hits" ] || printf "%s\n" "$am_hits" | tr "\n" " "; }
c=$(change "$repo" t1 add docs/new.md)
check "a change outside the list touches nothing" '[ "$(touched "$c")" = "ok:" ]'
c=$(change "$repo" t2 add .github/workflows/x.yml)
check "a built-in folder is protected" '[ "$(touched "$c")" = "ok:.github/workflows/x.yml " ]'
c=$(change "$repo" t3 add .claude/settings.json)
check ".claude/ is protected" '[ "$(touched "$c")" = "ok:.claude/settings.json " ]'
c=$(change "$repo" t4 add hooks/new)
check "a folder entry covers files under it" '[ "$(touched "$c")" = "ok:hooks/new " ]'
c=$(change "$repo" t5 add CHANGELOG.md)
check "a file entry covers that file" '[ "$(touched "$c")" = "ok:CHANGELOG.md " ]'
c=$(change "$repo" t6 add CHANGELOG.md.bak add hooks-extra/a add lib/agent-merge.sh.x add xhooks/a)
check "a file entry is no prefix and a folder entry needs its slash" '[ "$(touched "$c")" = "ok:" ]'
c=$(change "$repo" t7 mv hooks/a docs/a2.md)
check "a rename out of a protected path counts its old name" '[ "$(touched "$c")" = "ok:hooks/a " ]'
c=$(change "$repo" t8 mv docs/a.md hooks/moved)
check "a rename into a protected path counts its new name" '[ "$(touched "$c")" = "ok:hooks/moved " ]'
c=$(change "$repo" t9 mv docs/a.md docs/b.md)
check "a rename between unprotected paths touches nothing" '[ "$(touched "$c")" = "ok:" ]'
c=$(change "$repo" t10 rm hooks/a)
check "a deleted protected file counts" '[ "$(touched "$c")" = "ok:hooks/a " ]'
c=$(change "$repo" t11 add '.github/a"b')
check "a path git would quote still counts" '[ "$(touched "$c")" = "ok:.github/a\"b " ]'
c=$(change "$repo" t12 add docs/one.md)
git -C "$repo" checkout -q -B main origin/main
mkdir -p "$repo/hooks" && printf 'm\n' >"$repo/hooks/later" && git -C "$repo" add -A && git -C "$repo" commit -q -m later && git -C "$repo" push -q origin main 2>/dev/null
git -C "$repo" fetch -q origin
check "a protected change that reached the default branch after the branch was cut is not the branch's" '[ "$(touched "$c")" = "ok:" ]'
check "an unknown commit cannot be decided" '! am_protected "$repo" "$ref" 0000000000000000000000000000000000000000 && [ -n "$am_why" ]'
check "a name that is not a commit cannot be decided" '! am_protected "$repo" "$ref" not-a-commit'
mkrepo 'not json'
git -C "$repo" checkout -q -B t13 && c=$(git -C "$repo" rev-parse HEAD)
check "an unreadable wait list cannot be decided" '! am_protected "$repo" "$(am_ref "$repo")" "$c" && [ -n "$am_why" ]'
check "a missing default branch ref cannot be decided" '! am_protected "$repo" refs/remotes/origin/nothing "$c"'

# mentat agent-merge <N>, with a stub gh. The stub answers the reads the command makes from
# files in $STUB, and records every call; any call it does not know fails and is recorded in
# $STUB/unknown.
cat >"$tmp/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$*" in
  "repo view --json nameWithOwner --jq .nameWithOwner") echo owner/repo ;;
  "api user --jq .login") echo mentat-bot ;;
  "pr view 7 --json state,baseRefName,headRefOid,body,author") [ -f "$STUB/no_pr" ] && exit 1; cat "$STUB/pr" ;;
  "pr view 7 --json headRefOid --jq .headRefOid") jq -r .headRefOid "$STUB/pr" ;;
  "pr view 7 --json mergeable --jq .mergeable") cat "$STUB/mergeable" ;;
  "api --paginate repos/owner/repo/commits/"*"/check-runs") [ -f "$STUB/no_checks_read" ] && exit 1; cat "$STUB/checks" ;;
  "api repos/owner/repo/rules/branches/main") [ -f "$STUB/no_rules" ] && exit 1; cat "$STUB/rules" ;;
  "api --paginate repos/owner/repo/issues/7/comments") [ -f "$STUB/no_comments" ] && exit 1; cat "$STUB/comments" ;;
  *) echo "$*" >>"$STUB/unknown"; exit 99 ;;
esac
STUBEOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
export MENTAT_CI_GRACE_SECONDS=0 MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_CI_TIMEOUT_SECONDS=2

# reset <head>: a ready, open pull request #7 by the signed-in account, based on main, whose
# head passed its one check, in a repository with no merge queue and no comments.
reset() {
  rm -f "$STUB"/*
  jq -n --arg h "$1" '{state: "OPEN", baseRefName: "main", headRefOid: $h, author: {login: "mentat-bot"}, body: "**Status:** Ready\n\n## Summary\n\nA change.\n"}' >"$STUB/pr"
  echo MERGEABLE >"$STUB/mergeable"
  checks success
  echo '[]' >"$STUB/rules"
  echo '[]' >"$STUB/comments"
}
pr_set() { jq "$@" "$STUB/pr" >"$STUB/p.tmp" && mv "$STUB/p.tmp" "$STUB/pr"; }
# checks <conclusion>...: the head's check runs; "running" is one still in progress.
checks() {
  local runs="[]"
  for c in "$@"; do
    if [ "$c" = running ]; then
      runs=$(jq '. + [{name: "tests", status: "in_progress", conclusion: null, completed_at: null}]' <<<"$runs")
    else
      runs=$(jq --arg c "$c" '. + [{name: "tests", status: "completed", conclusion: $c, completed_at: "2026-01-01T00:00:00Z"}]' <<<"$runs")
    fi
  done
  jq -n --argjson r "$runs" '{check_runs: $r}' >"$STUB/checks"
}
# comment <login> <body>: adds an issue comment.
comment() { jq --arg u "$1" --arg b "$2" '. + [{user: {login: $u}, body: $b}]' "$STUB/comments" >"$STUB/c.tmp" && mv "$STUB/c.tmp" "$STUB/comments"; }
# run_am [<N>]: runs mentat agent-merge in $repo; sets out (stdout), err and rc.
run_am() {
  out=$(cd "$repo" && "$mentat" agent-merge "${1:-7}" 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
}
one_line() { [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]; }
waits() { [ "$rc" = 0 ] && one_line && case "$out" in "agent merge: waits for the maintainer ("*"$1"*")") true ;; *) false ;; esac; }
ok_commit() { c=$(change "$repo" feature add docs/new.md); }

mkrepo "$(settings on 'hooks/ CHANGELOG.md')"
ok_commit
reset "$c"
run_am
check "everything holds: prints on" '[ "$rc" = 0 ] && [ "$out" = "agent merge: on" ]'
check "it reads the repository, the account, the pull request, the CI checks, the rules and the comments" '[ -z "$(cat "$STUB/unknown" 2>/dev/null)" ] && grep -q "^api user" "$STUB/calls" && grep -q "^pr view 7" "$STUB/calls" && grep -q "check-runs" "$STUB/calls" && grep -q "rules/branches/main" "$STUB/calls" && grep -q "issues/7/comments" "$STUB/calls"'
check "it posts nothing and merges nothing (no call but a read)" '! grep -E "^(pr (merge|comment|edit)|api -X)" "$STUB/calls"'

# The setting.
for v in off yes ""; do
  mkrepo "$(settings "$v" -)"; ok_commit; reset "$c"
  run_am
  check "the value \"$v\" prints off and reads no pull request" '[ "$rc" = 0 ] && [ "$out" = "agent merge: off" ] && [ ! -f "$STUB/calls" ]'
done
mkrepo -; ok_commit; reset "$c"; run_am
check "no settings file prints off" '[ "$rc" = 0 ] && [ "$out" = "agent merge: off" ]'
mkrepo "$(settings off -)"; printf '%s\n' "$(settings on -)" >"$repo/.claude/settings.json"; ok_commit; reset "$c"; run_am
check "settings only in the working tree print off" '[ "$out" = "agent merge: off" ]'
mkrepo "$(settings off -)"; ok_commit; reset "$c"
second="$tmp/second$n"
git clone -q "$origin" "$second" 2>/dev/null
printf '%s\n' "$(settings on -)" >"$second/.claude/settings.json"
git -C "$second" commit -q -am on && git -C "$second" push -q origin HEAD:main 2>/dev/null
before=$(git -C "$repo" rev-parse origin/main)
run_am
check "it fetches origin's default branch, so a setting changed there counts" '[ "$out" = "agent merge: on" ] && [ "$(git -C "$repo" rev-parse origin/main)" != "$before" ]'
mkrepo "$(settings on -)"; ok_commit; reset "$c"
git -C "$repo" remote set-url origin "$tmp/no-such-origin.git"
run_am
check "a failed fetch waits" 'waits "could not be fetched"'
mkrepo "$(settings on -)"; ok_commit; reset "$c"
git -C "$repo" remote set-head origin -d >/dev/null
run_am
check "no local origin/HEAD waits, since the hook reads it" 'waits "origin/HEAD"'

# #N: open, based on the default branch, by the signed-in account, Status exactly Ready.
fresh() { mkrepo "$(settings on 'hooks/ CHANGELOG.md')"; ok_commit; reset "$c"; }
fresh; pr_set '.state = "MERGED"'; run_am
check "a merged pull request waits" 'waits "not open"'
fresh; pr_set '.state = "CLOSED"'; run_am
check "a closed pull request waits" 'waits "not open"'
fresh; pr_set '.baseRefName = "release"'; run_am
check "another base branch waits" 'waits "base"'
fresh; pr_set '.author.login = "someone-else"'; run_am
check "another author waits" 'waits "opened by another account"'
for s in '**Status:** Ready for review' '**Status:** Ready ' '**Status:** In review' '**Status:** Blocked: a reason' '**Status:** Not reviewed: fast track agreed by the maintainer' '**Status:** ready' 'Status: Ready' ''; do
  fresh; pr_set --arg b "$s"$'\n\n## Summary\n' '.body = $b'; run_am
  check "the Status line \"$s\" waits" 'waits "Status line"'
done
fresh; pr_set '.body = "## Summary\n\n**Status:** Ready\n"'; run_am
check "a Status line that is not the first line waits" 'waits "Status line"'

# CI on the head.
fresh; checks failure; run_am
check "a failing check waits" 'waits "CI did not pass"'
fresh; checks success failure; run_am
check "one failing check among passing ones waits" 'waits "CI did not pass"'
fresh; checks running; run_am
check "a check still running waits" 'waits "CI"'
fresh; echo '{"check_runs": []}' >"$STUB/checks"; run_am
check "no checks ran waits" 'waits "no CI checks ran"'
fresh; echo '{"check_runs": []}' >"$STUB/checks"; echo CONFLICTING >"$STUB/mergeable"; run_am
check "no checks on a conflicting pull request waits" 'waits "CI"'
fresh; checks success skipped neutral; run_am
check "skipped and neutral checks do not stop a pass" '[ "$out" = "agent merge: on" ]'
fresh; : >"$STUB/no_checks_read"; run_am
check "a CI read that fails exits non-zero and prints no pass" '[ "$rc" != 0 ] && [ "$out" != "agent merge: on" ]'

# The merge queue.
fresh; echo '[{"type": "merge_queue", "parameters": {}}]' >"$STUB/rules"; run_am
check "a merge queue rule waits" 'waits "merge queue"'
fresh; echo '[{"type": "pull_request"}, {"type": "required_status_checks"}]' >"$STUB/rules"; run_am
check "other rules do not wait" '[ "$out" = "agent merge: on" ]'
fresh; : >"$STUB/no_rules"; run_am
check "a rules read that fails exits non-zero" '[ "$rc" != 0 ] && ! printf "%s" "$out" | grep -q "agent merge: on"'

# Protected paths of the head.
fresh; c2=$(change "$repo" prot add hooks/new); pr_set --arg h "$c2" '.headRefOid = $h'; run_am
check "a head that changes a listed folder waits, naming the path" 'waits "protected path (hooks/new"'
fresh; c2=$(change "$repo" prot add .github/workflows/x.yml); pr_set --arg h "$c2" '.headRefOid = $h'; run_am
check "a head that changes .github/ waits" 'waits "protected path (.github/workflows/x.yml"'
fresh; c2=$(change "$repo" prot mv docs/a.md hooks/moved); pr_set --arg h "$c2" '.headRefOid = $h'; run_am
check "a head that renames a file into a listed folder waits" 'waits "protected path (hooks/moved"'
fresh; pr_set '.headRefOid = "0000000000000000000000000000000000000000"'; run_am
check "a head that is not in this checkout waits" 'waits "protected paths"'
git -C "$repo" checkout -q main
mkrepo '{"env": {"MENTAT_AGENT_MERGE": "on", "MENTAT_MERGE_WAIT_PATHS": [1]}}'; ok_commit; reset "$c"; run_am
check "a wait list that cannot be read waits" 'waits "protected paths"'

# A review comment this account posted, on any head, that holds (high risk).
heading="## Local Claude review of 1111111111111111111111111111111111111111: findings, spec fingerprint none"
fresh; comment mentat-bot "$heading

- (blocking, high risk) hooks/x:1 a change that loosens a check (high risk)"; run_am
check "a Local Claude review holding (high risk), on another head, waits" 'waits "high risk"'
fresh; comment mentat-bot "## Outside review of 1111111111111111111111111111111111111111: spec fingerprint none, reviewers codex

- codex: findings

(high risk) a leaked key"; run_am
check "an Outside review holding (high risk) waits" 'waits "high risk"'
fresh; comment mentat-bot "$heading

- (blocking) a plain finding
- (non-blocking) a note"; run_am
check "a review without the mark does not wait" '[ "$out" = "agent merge: on" ]'
fresh; comment someone-else "$heading

(high risk)"; run_am
check "a comment by another account is not read" '[ "$out" = "agent merge: on" ]'
fresh; comment mentat-bot "Thanks, answered (high risk) as agreed."; run_am
check "a comment that is not a review is not read" '[ "$out" = "agent merge: on" ]'
fresh; comment mentat-bot "Re: $heading (high risk)"; run_am
check "a heading that is not the first line is not read" '[ "$out" = "agent merge: on" ]'
fresh; : >"$STUB/no_comments"; run_am
check "a comments read that fails exits non-zero" '[ "$rc" != 0 ] && ! printf "%s" "$out" | grep -q "agent merge: on"'

# Reasons are listed together, each condition on its own, and output is one line.
fresh; pr_set '.author.login = "someone-else" | .body = "**Status:** Blocked: x\n"'; echo '[{"type": "merge_queue"}]' >"$STUB/rules"; run_am
check "several reasons are listed in one line" 'waits "opened by another account" && waits "Status line" && waits "merge queue"'
fresh; pr_set '.state = "MERGED"'; run_am
check "an unmet condition skips the CI wait" '! grep -q "check-runs" "$STUB/calls"'
fresh; : >"$STUB/no_pr"; run_am
check "an unreadable pull request exits non-zero with no result line" '[ "$rc" != 0 ] && [ -z "$out" ]'

# Usage.
fresh
out=$(cd "$repo" && "$mentat" agent-merge 2>/dev/null); rc=$?
check "no number exits 64" '[ "$rc" = 64 ]'
out=$(cd "$repo" && "$mentat" agent-merge abc 2>/dev/null); rc=$?
check "a number that is not one exits 64" '[ "$rc" = 64 ]'
out=$(cd "$repo" && "$mentat" agent-merge 7 8 2>/dev/null); rc=$?
check "two arguments exit 64" '[ "$rc" = 64 ]'
out=$(cd "$tmp" && "$mentat" agent-merge 7 2>/dev/null); rc=$?
check "outside a repository it exits non-zero" '[ "$rc" != 0 ] && [ -z "$out" ]'
u=$("$mentat" 2>&1); check "the usage text names it" 'case "$u" in *"mentat agent-merge <pull request number>"*) true ;; *) false ;; esac'

# The review criteria every reviewer gets (the local review and each outside reviewer).
# shellcheck source=lib/shared.sh
crit=$(. "$root/lib/shared.sh" && review_criteria "")
# shellcheck source=lib/shared.sh
crit_diff=$(. "$root/lib/shared.sh" && review_criteria " and the diff")
check "the review criteria ask for the (high risk) mark besides blocking and non-blocking" 'grep -qF "(high risk)" <<<"$crit" && grep -q "(blocking) or (non-blocking)" <<<"$crit"'
check "the criteria name what makes a change high risk" 'grep -qF "weaken a safety net or a test" <<<"$crit" && grep -qF "expose a credential" <<<"$crit" && grep -qF "lose data" <<<"$crit" && grep -qF "be hard to undo" <<<"$crit"'
check "the criteria always mark a change that removes or loosens a check of the test command high risk" 'grep -q "[Aa]lways mark (high risk) a change that removes or loosens a check of the repository.s test command" <<<"$crit" && grep -qF "such as tests/run here" <<<"$crit"'
check "the criteria say such a pull request waits for the maintainer" 'grep -qF "waits for the maintainer" <<<"$crit"'
check "the criteria are the same text for the diff-carrying reviewers" 'grep -qF "(high risk)" <<<"$crit_diff" && grep -qF "removes or loosens a check" <<<"$crit_diff"'

[ "$failures" -eq 0 ]
