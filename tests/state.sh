#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat state`, run through bin/mentat in a real git repository and a
# linked worktree at paths with spaces, with a stub gh that answers the open pull request
# list from a file and records every call. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
# The physical path, as git prints it (macOS's temporary folder is under a symbolic link).
root=$(mktemp -d) && root=$(cd -P "$root" && pwd -P) || exit 1
holders=""
cleanup() {
  local p
  for p in $holders; do kill -KILL -- "$p" 2>/dev/null; done
  rm -rf "$root"
}
trap cleanup EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/home" "$root/plain"
failures=0
check() { if eval "$2"; then printf 'PASS: state %s\n' "$1"; else printf 'FAIL: state %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$root/home"
export GIT_CEILING_DIRECTORIES="$root"
# The maintainer's shell may set these; each case sets what it needs.
unset MENTAT_READY_LIMIT STATE_LOCKF STATE_FLOCK STATE_LOCK_SECONDS

# gh: the open pull request list, from $STUB/prs (a JSON array of {number, body}), cut to
# --limit as gh does (30 when not given), or failing as a signed-out gh does when
# $STUB/gh_fail exists. Every call is recorded.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/gh_calls"
if [ -f "$STUB/gh_fail" ]; then echo "To get started with GitHub CLI, please run:  gh auth login" >&2; exit 4; fi
limit=30
while [ $# -gt 0 ]; do
  case "$1" in --limit) limit=$2; shift ;; esac
  shift
done
jq --argjson n "$limit" '.[:$n]' "$STUB/prs"
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

# The main checkout R and a linked worktree T, which share one store.
R="$root/main checkout" T="$root/a worktree"
git init -q -b main "$R" || exit 1
git -C "$R" commit -q --allow-empty -m one || exit 1
git -C "$R" worktree add -q "$T" -b other || exit 1
S="$R/.git/mentat/state.json" L="$R/.git/mentat/state.lock"

# Runs mentat state with the arguments, in $D (by default R). Prints the exit status;
# stdout and stderr go to $root/out and $root/err.
D=$R
st() { (cd "$D" && "$mentat" state "$@" >"$root/out" 2>"$root/err"); echo $?; }
put() { mkdir -p "$(dirname "$S")" && printf '%s' "$1" >"$S"; }
fresh() { rm -f "$S" "$STUB/gh_calls" "$STUB/gh_fail"; }
sum() { cksum "$S" 2>/dev/null || echo none; }
q() { jq -r "$1" "$S"; }
out_is() { [ "$(cat "$root/out")" = "$1" ]; }

# 1. One store under the git common dir, shared by every worktree; missing reads as empty.
fresh
rc=$(st show)
check "1: a missing store reads as empty (show prints {}, exit 0)" '[ "$rc" = 0 ] && [ "$(jq -c . "$root/out")" = "{}" ] && [ ! -e "$S" ]'
rc=$(D=$T st item set WRK-1 --stage held)
check "1: a write from a linked worktree lands in <git common dir>/mentat/state.json" '[ "$rc" = 0 ] && [ "$(q ".items[\"WRK-1\"].stage")" = held ]'
rc=$(st item get WRK-1)
check "1: the main checkout reads what the worktree wrote" '[ "$rc" = 0 ] && [ "$(jq -r .stage "$root/out")" = held ]'
put '{"future":{"x":[1,2]},"items":{"WRK-1":{"stage":"held","later":"kept"}}}'
rc=$(st item set WRK-1 --pr 12)
check "1: a write keeps fields it does not know, at the top and in an item" '[ "$rc" = 0 ] && [ "$(q .future.x[1])" = 2 ] && [ "$(q ".items[\"WRK-1\"].later")" = kept ] && [ "$(q ".items[\"WRK-1\"].pr")" = 12 ]'

# 2. The lock: lockf by default, with -k and a 10-second wait, on the lock file beside the store.
cat >"$root/lockf-rec" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$STUB/lockf_args"
exec /usr/bin/lockf "$@"
STUBEOF
# flock, as util-linux gives it (-E <code> -w <seconds> <file> <command>...), run here
# through lockf, since macOS has no flock.
cat >"$root/flock-stub" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$STUB/flock_args"
code=1 wait=""
while :; do
  case "$1" in
    -E) code=$2; shift 2 ;;
    -w) wait=$2; shift 2 ;;
    *) break ;;
  esac
done
/usr/bin/lockf -s -k ${wait:+-t "$wait"} "$@"
rc=$?
[ "$rc" != 75 ] || exit "$code"
exit "$rc"
STUBEOF
chmod +x "$root/lockf-rec" "$root/flock-stub"
fresh
rc=$(STATE_LOCKF="$root/lockf-rec" st item set WRK-2 --stage handed)
check "2: a write runs under lockf -k -t 10 on the lock file beside the store" '[ "$rc" = 0 ] && grep -qF -- "-k" "$STUB/lockf_args" && grep -qF -- "-t 10 $L " "$STUB/lockf_args" && [ "$(q ".items[\"WRK-2\"].stage")" = handed ]'
check "2: the lock file is kept after the write" '[ -f "$L" ]'
rm -f "$STUB/flock_args"
rc=$(STATE_LOCKF="$root/no-lockf" STATE_FLOCK="$root/flock-stub" st item set WRK-3 --stage held)
check "2: without lockf, flock -w 10 takes the lock" '[ "$rc" = 0 ] && grep -qF -- "-w 10 $L " "$STUB/flock_args" && grep -qF -- "-E " "$STUB/flock_args" && [ "$(q ".items[\"WRK-3\"].stage")" = held ]'

# m. The lock held by another command: the write waits, then fails naming the lock (exit 2).
# The holder is a lockf on the same file, waited for until it holds the lock.
# It runs in its own process group (its pid), so killing the group kills lockf and its command.
hold() { # $1 seconds to hold
  perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' /usr/bin/lockf -k "$L" sleep "$1" >/dev/null 2>&1 &
  holder=$! holders="$holders -$holder"
  local i=0
  while /usr/bin/lockf -s -k -t 0 "$L" true; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || return 1
    sleep 0.1
  done
}
before=$(sum)
hold 60 || exit 1
start=$(date +%s)
rc=$(STATE_LOCK_SECONDS=1 st item set WRK-4 --stage held)
took=$(($(date +%s) - start))
check "m: lock held: waits, then exit 2 naming the lock, nothing written" '[ "$rc" = 2 ] && grep -qF "$L" "$root/err" && [ "$took" -ge 1 ] && [ "$(sum)" = "$before" ]'
rc=$(STATE_LOCK_SECONDS=1 STATE_LOCKF="$root/no-lockf" STATE_FLOCK="$root/flock-stub" st item set WRK-4 --stage held)
check "m: lock held under flock: exit 2 naming the lock (not 1), nothing written" '[ "$rc" = 2 ] && grep -qF "$L" "$root/err" && [ "$(sum)" = "$before" ]'

# n. The command holding the lock is killed: the lock is free at once and the write goes on.
kill -KILL -- "-$holder"
wait "$holder" 2>/dev/null
start=$(date +%s)
rc=$(st item set WRK-4 --stage held)
took=$(($(date +%s) - start))
check "n: holder killed: the next write takes the lock at once" '[ "$rc" = 0 ] && [ "$took" -lt 5 ] && [ "$(q ".items[\"WRK-4\"].stage")" = held ]'
# And a holder that ends within the wait: the write waits for it and lands.
hold 2 || exit 1
rc=$(st item set WRK-5 --stage held)
check "n: a holder that ends within the wait: the write lands (exit 0)" '[ "$rc" = 0 ] && [ "$(q ".items[\"WRK-5\"].stage")" = held ]'

# o. Neither lockf nor flock found: fails naming both, exit 2, writes nothing.
fresh
rm -rf "$R/.git/mentat"
rc=$(STATE_LOCKF="$root/no-lockf" STATE_FLOCK="$root/no-flock" st item set WRK-6 --stage held)
check "o: neither lockf nor flock: exit 2 naming both, nothing written" '[ "$rc" = 2 ] && grep -qF lockf "$root/err" && grep -qF flock "$root/err" && [ ! -e "$S" ]'

# p. Writes at once to different fields: every one is kept.
fresh
pids=""
i=0
while [ "$i" -lt 20 ]; do
  # A long wait, so a busy machine running every test at once cannot time a writer out.
  (cd "$R" && STATE_LOCK_SECONDS=120 "$mentat" state item set "P-$i" --stage held >/dev/null 2>&1) &
  pids="$pids $!"
  i=$((i + 1))
done
for p in $pids; do wait "$p"; done
check "p: twenty writes at once: all twenty items kept" '[ "$(q ".items | length")" = 20 ]'

# q. A store that is empty, not JSON, not an object or has a field of the wrong type, or a
# command run outside a git repository: exit 2 naming the file, nothing written.
commands="show|orchestrator|orchestrator set o-2|orchestrator ended o-1|owner|owner WRK-1|session add s-1 WRK-1|session end s-1|session list|item set WRK-1 --stage held|item get WRK-1|item list|note add hold text|note list|note clear 1|can-dispatch"
printf '[]' >"$STUB/prs"
for bad in '' 'not json' '{"a":1} {"b":2}' '[1,2]' '"text"' '{"items":[]}' '{"items":{"WRK-1":{"pr":"12"}}}' '{"orchestrator":"o-1"}' '{"orchestrator":{"id":"o-1","ended":"yes"}}' '{"notes":{}}' '{"notes":[{"id":"1","kind":"hold","text":"x","cleared":false}]}' '{"sessions":{"s-1":{"ended":1}}}' '{"items":{"WRK-1":{"stage":3}}}'; do
  put "$bad"
  before=$(sum)
  bad_ones=""
  while IFS= read -r c; do
    # shellcheck disable=SC2086 # the command's words
    rc=$(st $c)
    if [ "$rc" != 2 ] || ! grep -qF "$S" "$root/err" || [ "$(sum)" != "$before" ] || [ -s "$root/out" ]; then bad_ones="$bad_ones [$c: $rc]"; fi
  done <<<"$(printf '%s\n' "$commands" | tr '|' '\n')"
  check "q: store '$bad': every command exits 2 naming the file, writes nothing" '[ -z "$bad_ones" ] || { printf "  failed:%s\n" "$bad_ones"; false; }'
done
bad_ones=""
while IFS= read -r c; do
  # shellcheck disable=SC2086 # the command's words
  rc=$( (cd "$root/plain" && "$mentat" state $c >"$root/out" 2>"$root/err"); echo $?)
  if [ "$rc" != 2 ] || [ -e "$root/plain/.git" ] || [ -n "$(ls -A "$root/plain")" ]; then bad_ones="$bad_ones [$c: $rc]"; fi
done <<<"$(printf '%s\n' "$commands" | tr '|' '\n')"
check "q: outside a git repository every command exits 2, writes nothing" '[ -z "$bad_ones" ] || { printf "  failed:%s\n" "$bad_ones"; false; }'

# 4. The orchestrator id and its mark.
fresh
rc=$(st orchestrator)
check "4: orchestrator, none recorded: exit 1" '[ "$rc" = 1 ]'
rc=$(st orchestrator set o-1)
rc2=$(st orchestrator)
check "4: orchestrator set records it with no mark" '[ "$rc" = 0 ] && [ "$rc2" = 0 ] && out_is "o-1 running"'
before=$(sum)
rc=$(st orchestrator ended o-9)
check "t: orchestrator ended with another id: exit 1, the id and its mark unchanged" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ] && grep -qF o-9 "$root/err"'
rc=$(st orchestrator ended o-1)
rc2=$(st orchestrator)
check "4: orchestrator ended with the recorded id sets the mark" '[ "$rc" = 0 ] && [ "$rc2" = 0 ] && out_is "o-1 ended"'
before=$(sum)
rc=$(st orchestrator ended o-9)
check "t: orchestrator ended with another id over a marked one: exit 1, unchanged" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ]'
rc=$(st orchestrator set o-2)
rc2=$(st orchestrator)
check "u: orchestrator set over a marked id: the new id with no mark" '[ "$rc" = 0 ] && out_is "o-2 running" && [ "$(q .orchestrator.ended)" = false ]'
rc=$(st orchestrator set o-3)
rc2=$(st orchestrator)
check "u: orchestrator set over an unmarked id: the new id with no mark" '[ "$rc" = 0 ] && out_is "o-3 running"'
fresh
before=$(sum)
rc=$(st orchestrator ended o-1)
check "t: orchestrator ended with none recorded: exit 1, nothing written" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ]'

# j, k. owner.
fresh
rc=$(st owner)
check "j: owner, none recorded: exit 1, nothing printed" '[ "$rc" = 1 ] && [ ! -s "$root/out" ]'
st orchestrator set o-1 >/dev/null
rc=$(st owner)
check "k: owner, recorded with no mark: prints the id, exit 0" '[ "$rc" = 0 ] && out_is o-1'
st orchestrator ended o-1 >/dev/null
rc=$(st owner)
check "j: owner, recorded with the no-longer-running mark: exit 1, nothing printed" '[ "$rc" = 1 ] && [ ! -s "$root/out" ]'

# 4. Build sessions; l. owner <item>.
fresh
rc=$(st session add s-1 WRK-1 WRK-2)
check "4: session add records the session as each item's session" '[ "$rc" = 0 ] && [ "$(q ".items[\"WRK-1\"].session")" = s-1 ] && [ "$(q ".items[\"WRK-2\"].session")" = s-1 ] && [ "$(q ".sessions[\"s-1\"].ended")" = false ]'
rc=$(st owner WRK-2)
check "l: owner <item> with a session: prints it, exit 0" '[ "$rc" = 0 ] && out_is s-1'
rc=$(st owner WRK-9)
check "l: owner <item>, unknown item: exit 1" '[ "$rc" = 1 ] && [ ! -s "$root/out" ]'
st item set WRK-3 --stage held >/dev/null
rc=$(st owner WRK-3)
check "l: owner <item>, item with no session: exit 1" '[ "$rc" = 1 ] && [ ! -s "$root/out" ]'
rc=$(st session list)
check "4: session list names the session, running, with its items" '[ "$rc" = 0 ] && grep -qE "^s-1[[:space:]]+running[[:space:]]+WRK-1 WRK-2$" "$root/out"'
rc=$(st session end s-1)
rc2=$(st session list)
check "4: session end marks it ended" '[ "$rc" = 0 ] && grep -qE "^s-1[[:space:]]+ended" "$root/out"'
before=$(sum)
rc=$(st session end s-9)
check "4: session end, unknown session: exit 1, nothing changed" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ]'

# 4. Items.
fresh
hb='the maintainer'"'"'s "call"'
rc=$(st item set WRK-1 --fingerprint 0123456789ab --stage handed --session s-1 --held-by "$hb")
check "4: item set records every field" '[ "$rc" = 0 ] && [ "$(q ".items[\"WRK-1\"].fingerprint")" = 0123456789ab ] && [ "$(q ".items[\"WRK-1\"].stage")" = handed ] && [ "$(q ".items[\"WRK-1\"].session")" = s-1 ] && [ "$(q ".items[\"WRK-1\"].held_by")" = "$hb" ]'
rc=$(st item set WRK-1 --stage pr --pr 12)
check "4: item set with --pr and stage pr together" '[ "$rc" = 0 ] && [ "$(q ".items[\"WRK-1\"].stage")" = pr ] && [ "$(q ".items[\"WRK-1\"].pr")" = 12 ] && [ "$(q ".items[\"WRK-1\"].session")" = s-1 ]'
rc=$(st item set WRK-1 --stage ready)
check "4: stage ready for an item with a PR number recorded" '[ "$rc" = 0 ] && [ "$(q ".items[\"WRK-1\"].stage")" = ready ]'
for s in held handed confirmed not-taken pr ready merged closed; do st item set "S-$s" --pr 3 --stage "$s" >/dev/null; done
check "4: every stage is accepted" '[ "$(q "[.items[] | .stage] | unique | length")" = 8 ]'
rc=$(st item get WRK-1)
check "4: item get prints the item" '[ "$rc" = 0 ] && [ "$(jq -r .pr "$root/out")" = 12 ] && [ "$(jq -r .stage "$root/out")" = ready ]'
rc=$(st item get WRK-9)
check "4: item get, unknown item: exit 1" '[ "$rc" = 1 ] && [ ! -s "$root/out" ]'
rc=$(st item list --stage merged)
check "4: item list --stage lists only that stage" '[ "$rc" = 0 ] && [ "$(cat "$root/out")" = "S-merged	merged" ]'
rc=$(st item list)
check "4: item list lists every item" '[ "$rc" = 0 ] && [ "$(grep -c . "$root/out")" = 9 ]'
before=$(sum)
rc=$(st item set WRK-1 --stage shipped)
check "4: unknown stage: usage error naming it, nothing changed" '[ "$rc" = 64 ] && grep -qF shipped "$root/err" && [ "$(sum)" = "$before" ]'
for f in 0123456789a 0123456789abc 0123456789ag; do
  rc=$(st item set WRK-1 --fingerprint "$f")
  check "4: fingerprint $f, not 12 hex: usage error naming it, nothing changed" '[ "$rc" = 64 ] && grep -qF "$f" "$root/err" && [ "$(sum)" = "$before" ]'
done

# v. Stage pr or ready with no PR number recorded or given: refused, nothing changed.
for s in pr ready; do
  rc=$(st item set WRK-7 --stage "$s")
  check "v: new item at stage $s with no PR number: exit 1, nothing changed" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ]'
done
st item set WRK-8 --stage handed --session s-2 >/dev/null
before=$(sum)
rc=$(st item set WRK-8 --stage pr --session s-3)
check "v: recorded item at stage pr with no PR number: exit 1, nothing changed" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ] && [ "$(q ".items[\"WRK-8\"].session")" = s-2 ]'

# 4. Notes; r, s, w.
fresh
rc=$(st note add hold "wait for the \"design\" call")
check "4: note add prints the new note's id" '[ "$rc" = 0 ] && out_is 1'
st note add question "which one?" >/dev/null
rc=$(st note add hold third)
check "4: ids go up" '[ "$rc" = 0 ] && out_is 3'
rc=$(st note clear 2)
check "4: note clear" '[ "$rc" = 0 ] && [ "$(q ".notes[1].cleared")" = true ]'
rc=$(st note list)
check "4: note list lists every note in order added, the cleared one included" '[ "$rc" = 0 ] && [ "$(cut -f1 "$root/out" | tr "\n" " ")" = "1 2 3 " ] && grep -qE "^2[[:space:]]+question[[:space:]]+cleared[[:space:]]+which one\?$" "$root/out" && grep -qF "wait for the \"design\" call" "$root/out"'
rc=$(st note list hold)
check "4: note list <kind> lists that kind only" '[ "$rc" = 0 ] && [ "$(cut -f1 "$root/out" | tr "\n" " ")" = "1 3 " ]'
before=$(sum)
rc=$(st note add tell "say this")
check "r: note add tell: usage error naming the kind, nothing written" '[ "$rc" = 64 ] && grep -qF tell "$root/err" && [ "$(sum)" = "$before" ]'
rc=$(st note add reminder "x")
check "r: note add with another unknown kind: usage error naming it, nothing written" '[ "$rc" = 64 ] && grep -qF reminder "$root/err" && [ "$(sum)" = "$before" ]'
rc=$(st note list tell)
check "4: note list with an unknown kind: usage error" '[ "$rc" = 64 ] && grep -qF tell "$root/err"'
rc=$(st note clear 9)
check "s: note clear, unknown id: exit 1, nothing changed" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ] && grep -qF 9 "$root/err"'
rc=$(st note clear 2)
check "s: note clear, already cleared: exit 1, nothing changed" '[ "$rc" = 1 ] && [ "$(sum)" = "$before" ]'
st note clear 3 >/dev/null
rc=$(st note add hold fourth)
check "w: note add after the newest note was cleared: a new id, not the cleared one" '[ "$rc" = 0 ] && out_is 4 && [ "$(q "[.notes[].id] | unique | length")" = 4 ]'

# show prints the whole store.
rc=$(st show)
check "4: show prints the store" '[ "$rc" = 0 ] && [ "$(jq -c . "$root/out")" = "$(jq -c . "$S")" ]'

# Usage errors exit 64 and write nothing.
before=$(sum)
bad_ones=""
for c in "" "nope" "orchestrator set" "orchestrator set a b" "orchestrator ended" "owner a b" "session add s-1" "session end" "session nope" "item" "item set" "item set WRK-1 --stage" "item set WRK-1 --pr x" "item set WRK-1 --pr 0" "item set WRK-1 --what 1" "item set -x" "item get" "item list --stage" "item list --stage shipped" "note add hold" "note clear x" "note clear" "note" "can-dispatch x" "show x"; do
  # shellcheck disable=SC2086 # the command's words
  rc=$(st $c)
  if [ "$rc" != 64 ] || [ "$(sum)" != "$before" ]; then bad_ones="$bad_ones [$c: $rc]"; fi
done
check "usage errors exit 64 and write nothing" '[ -z "$bad_ones" ] || { printf "  failed:%s\n" "$bad_ones"; false; }'

# 5. can-dispatch. prs <number>|<body> ... writes the stub's open pull request list.
prs() { jq -n '[$ARGS.positional[] | {number: (split("|")[0] | tonumber), body: (split("|")[1:] | join("|"))}]' --args "$@" >"$STUB/prs"; }
dispatch() { rc=$(st can-dispatch); }
line() { grep -qxF "$1" "$root/out"; }
READY=$'**Status:** Ready\n\nThe change.'
READY_CRLF=$'**Status:** Ready\r\n\r\nThe change.'
FAST=$'**Status:** Not reviewed: fast track agreed by the maintainer\nThe change.'
WAIVED=$'**Status:** Not reviewed: last push waived by the maintainer\nThe change.'
OTHER=$'The change.\n**Status:** Ready'

# a. Waiting >= N: 0, exit 1.
fresh
prs "1|$READY" "2|$READY_CRLF" "3|$FAST" "4|$WAIVED"
dispatch
check "a: three waiting (one CRLF, one fast track), limit 3: prints 0, exit 1" '[ "$rc" = 1 ] && line "waiting: 3 (#1 #2 #3)" && line "limit: 3" && line "can hand over: 0" && [ ! -s "$root/err" ]'
check "e: gh pr list --state open --limit 1000 is read" 'grep -qE "^pr list .*--state open --limit 1000( |$)" "$STUB/gh_calls"'

# b. Waiting + in flight < N.
fresh
prs "1|$READY" "5|$OTHER"
st item set A --stage handed >/dev/null
dispatch
check "b: one waiting, one in flight, limit 3: prints 1, exit 0" '[ "$rc" = 0 ] && line "waiting: 1 (#1)" && line "in flight: 1" && line "can hand over: 1"'

# c. Waiting < N but waiting + in flight >= N.
st item set B --stage confirmed >/dev/null
st item set C --stage pr --pr 5 >/dev/null
dispatch
check "c: one waiting, three in flight (handed, confirmed, pr open not waiting): prints 0, exit 1" '[ "$rc" = 1 ] && line "waiting: 1 (#1)" && line "in flight: 3" && line "can hand over: 0"'

# d. The limit.
fresh
prs "1|$READY"
rc=$(MENTAT_READY_LIMIT='' st can-dispatch)
check "d: MENTAT_READY_LIMIT empty: 3, nothing on stderr" '[ "$rc" = 0 ] && line "limit: 3" && line "can hand over: 2" && [ ! -s "$root/err" ]'
rc=$(st can-dispatch)
check "d: MENTAT_READY_LIMIT unset: 3, nothing on stderr" '[ "$rc" = 0 ] && line "limit: 3" && [ ! -s "$root/err" ]'
for v in abc 0 -2 1.5 " 4"; do
  rc=$(MENTAT_READY_LIMIT="$v" st can-dispatch)
  check "d: MENTAT_READY_LIMIT '$v' is invalid: 3, said once on stderr" '[ "$rc" = 0 ] && line "limit: 3" && [ "$(grep -c . "$root/err")" = 1 ] && grep -qF MENTAT_READY_LIMIT "$root/err"'
done
rc=$(MENTAT_READY_LIMIT=5 st can-dispatch)
check "d: MENTAT_READY_LIMIT 5: limit 5" '[ "$rc" = 0 ] && line "limit: 5" && line "can hand over: 4" && [ ! -s "$root/err" ]'
rc=$(MENTAT_READY_LIMIT=08 st can-dispatch)
check "d: MENTAT_READY_LIMIT 08: limit 8" '[ "$rc" = 0 ] && line "limit: 8" && [ ! -s "$root/err" ]'
rc=$(MENTAT_READY_LIMIT=1 st can-dispatch)
check "a: one waiting, limit 1: prints 0, exit 1" '[ "$rc" = 1 ] && line "can hand over: 0"'

# e. More open pull requests than gh's default page of 30: all are read.
fresh
set --
i=1
while [ "$i" -le 40 ]; do set -- "$@" "$i|$READY"; i=$((i + 1)); done
prs "$@"
set --
rc=$(MENTAT_READY_LIMIT=45 st can-dispatch)
check "e: forty waiting pull requests: all forty counted" '[ "$rc" = 0 ] && grep -qE "^waiting: 40 " "$root/out" && line "can hand over: 5"'

# f. gh failing or signed out: exit 2, no count.
fresh
prs "1|$READY"
touch "$STUB/gh_fail"
dispatch
check "f: gh signed out: exit 2, no count printed" '[ "$rc" = 2 ] && [ ! -s "$root/out" ] && [ -s "$root/err" ]'
rm -f "$STUB/gh_fail"
printf 'not json' >"$STUB/prs"
dispatch
check "f: gh answering something that is not a list: exit 2, no count printed" '[ "$rc" = 2 ] && [ ! -s "$root/out" ]'

# g. A pull request waiting by its Status line and also at stage ready or pr: counted once.
fresh
prs "7|$READY" "8|$OTHER"
st item set G1 --stage ready --pr 7 >/dev/null
st item set G2 --stage pr --pr 7 >/dev/null
dispatch
check "g: waiting by Status line and at stage ready and pr: counted once, as waiting" '[ "$rc" = 0 ] && line "waiting: 1 (#7)" && line "in flight: 0" && line "can hand over: 2"'
st item set G3 --stage ready --pr 8 >/dev/null
dispatch
check "5: an open pull request at stage ready waits whatever its Status line" '[ "$rc" = 0 ] && line "waiting: 2 (#7 #8)" && line "in flight: 0" && line "can hand over: 1"'

# h. An item at stage pr whose pull request is merged or closed: neither.
fresh
prs "1|$OTHER"
st item set H1 --stage pr --pr 99 >/dev/null
st item set H2 --stage ready --pr 98 >/dev/null
dispatch
check "h: stage pr or ready with the pull request not open: neither waiting nor in flight" '[ "$rc" = 0 ] && line "waiting: 0" && line "in flight: 0" && line "can hand over: 3"'

# i. Empty description, another first line, or a waived last push: not waiting.
fresh
prs "1|" "2|$OTHER" "3|$WAIVED"
jq '.[0].body = null' "$STUB/prs" >"$STUB/prs.tmp" && mv "$STUB/prs.tmp" "$STUB/prs"
prs_null=$(jq -c '.[0].body' "$STUB/prs")
st item set I1 --stage pr --pr 3 >/dev/null
dispatch
check "i: null body, other first line, waived last push: none waiting; the pr-stage one is in flight" '[ "$rc" = 0 ] && [ "$prs_null" = null ] && line "waiting: 0" && line "in flight: 1" && line "can hand over: 2"'
prs "1|" "2|$OTHER" "3|$WAIVED"
dispatch
check "i: empty body: not waiting" '[ "$rc" = 0 ] && line "waiting: 0"'

[ "$failures" -eq 0 ] || exit 1
