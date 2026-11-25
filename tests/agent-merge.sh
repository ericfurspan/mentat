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

[ "$failures" -eq 0 ]
