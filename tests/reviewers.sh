#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for whether outside reviewers are on (reviewers_state in lib/shared.sh)
# and `mentat reviewers`, using real git origins and a stub gh that records any call.
# Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/home/.claude"
failures=0
check() { if eval "$2"; then printf 'PASS: reviewers %s\n' "$1"; else printf 'FAIL: reviewers %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 HOME="$root/home"
# No run looks above the test's folder for a repository.
export GIT_CEILING_DIRECTORIES="$root"

# gh: mentat reviewers never calls it; a call is recorded.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/gh_calls"
exit 99
STUBEOF
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

ON='{"enabledPlugins":{"mentat-reviewers@mentat":true}}'
OFF='{"enabledPlugins":{"mentat-reviewers@mentat":false}}'
F=".claude/settings.json on main"

# An origin at a path with a space, whose main main_has sets, and a clone of it at
# another such path. The clone fetches only when a case says so, so its origin/main is
# usually behind.
O="$root/the origin.git" SEED="$root/seed" W="$root/work tree"
git init -q --bare -b main "$O"
git init -q -b main "$SEED"
git -C "$SEED" remote add origin "$O"
main_has() { # $1 the settings file's whole content, or @absent, @dir or @link
  (cd "$SEED" && rm -rf .claude && mkdir .claude &&
    case "$1" in
      @absent) printf '{}\n' >.claude/other.json ;;
      @dir) mkdir .claude/settings.json && printf '%s\n' "$ON" >.claude/settings.json/x ;;
      @link) printf '%s\n' "$ON" >.claude/on.json && ln -s on.json .claude/settings.json ;;
      *) printf '%s' "$1" >.claude/settings.json ;;
    esac &&
    git add -A && git commit -q --allow-empty -m settings && git push -q -f origin HEAD:main)
}
main_has "$OFF"
git clone -q "$O" "$W"

run() { (cd "${1:-$W}" && "$mentat" reviewers >"$STUB/out" 2>"$STUB/err"); echo $?; }
# Exit 0, exactly the one line $1 on stdout, nothing on stderr, no gh call, and no
# private ref left in the clone.
said() {
  [ "$rc" = 0 ] && [ "$(cat "$STUB/out")" = "$1" ] && [ "$(wc -l <"$STUB/out" | tr -d ' ')" = 1 ] && [ ! -s "$STUB/err" ] &&
    [ ! -f "$STUB/gh_calls" ] && [ -z "$(git -C "$W" for-each-ref refs/mentat)" ]
}
state() { # $1 what main's settings hold, $2 the settings (main_has), $3 the line printed
  want=$3
  main_has "$2"; rc=$(run)
  check "$1: $want" 'said "$want"'
}

state "true" "$ON" "reviewers: on"
state "true among other settings" '{"model":"opus","enabledPlugins":{"other@mentat":false,"mentat-reviewers@mentat":true}}' "reviewers: on"
state "false" "$OFF" "reviewers: off"
state "the key absent" '{"enabledPlugins":{"other@mentat":true}}' "reviewers: off"
state "enabledPlugins empty" '{"enabledPlugins":{}}' "reviewers: off"
state "enabledPlugins absent" '{"model":"opus"}' "reviewers: off"
state "no settings file" @absent "reviewers: off"
state "invalid JSON" '{"enabledPlugins":' "reviewers: unknown - $F could not be read as JSON"
state "an empty file" '' "reviewers: unknown - $F is not one JSON object"
state "two JSON values" "$ON$ON" "reviewers: unknown - $F is not one JSON object"
state "a JSON list" "[$ON]" "reviewers: unknown - $F is not one JSON object"
state "a JSON string" '"on"' "reviewers: unknown - $F is not one JSON object"
state "enabledPlugins a list" '{"enabledPlugins":["mentat-reviewers@mentat"]}' "reviewers: unknown - enabledPlugins in $F is not an object"
state "enabledPlugins null" '{"enabledPlugins":null}' "reviewers: unknown - enabledPlugins in $F is not an object"
state "null" '{"enabledPlugins":{"mentat-reviewers@mentat":null}}' "reviewers: unknown - mentat-reviewers@mentat in $F is neither true nor false"
state "the string true" '{"enabledPlugins":{"mentat-reviewers@mentat":"true"}}' "reviewers: unknown - mentat-reviewers@mentat in $F is neither true nor false"
state "a number" '{"enabledPlugins":{"mentat-reviewers@mentat":1}}' "reviewers: unknown - mentat-reviewers@mentat in $F is neither true nor false"
state "a folder named settings.json" @dir "reviewers: unknown - $F is not a regular file"
state "a symbolic link to a file that says true" @link "reviewers: unknown - $F is not a regular file"

# main changed after the clone's last fetch, both ways: the remote's main counts, never the
# stale origin/main, and the read leaves origin/main and git's record of the last fetch alone.
tracking() { git -C "$W" rev-parse refs/remotes/origin/main; }
tracked_settings() { git -C "$W" cat-file blob refs/remotes/origin/main:.claude/settings.json; }
last_fetch() { cksum "$W/.git/FETCH_HEAD" 2>/dev/null || echo none; }
main_has "$OFF"; git -C "$W" fetch -q origin; main_has "$ON"
before=$(tracking) before_fetch=$(last_fetch); rc=$(run)
check "main turned on after the last fetch, origin/main still off: on" 'said "reviewers: on" && [ "$(tracked_settings)" = "$OFF" ]'
check "the read leaves origin/main and the last-fetch record as they were" '[ "$(tracking)" = "$before" ] && [ "$(last_fetch)" = "$before_fetch" ] && [ "$before_fetch" != none ]'
git -C "$W" fetch -q origin; main_has "$OFF"
before=$(tracking) before_fetch=$(last_fetch); rc=$(run)
check "main turned off after the last fetch, origin/main still on: off" 'said "reviewers: off" && [ "$(tracked_settings)" = "$ON" ] && [ "$(tracking)" = "$before" ] && [ "$(last_fetch)" = "$before_fetch" ]'

# Only main on origin counts: an unmerged branch, a local commit, the working tree, local
# settings and user settings never do, either way.
main_has "$OFF"
(cd "$SEED" && git checkout -q -b feature && printf '%s' "$ON" >.claude/settings.json && git commit -qam on && git push -q origin feature && git checkout -q main) || exit 1
git -C "$W" fetch -q origin && git -C "$W" checkout -q -b feature origin/feature || exit 1
rc=$(run)
check "on only in an unmerged branch, checked out here: off" 'said "reviewers: off" && [ "$(cat "$W/.claude/settings.json")" = "$ON" ]'
git -C "$W" checkout -q main && git -C "$W" reset -q --hard origin/main || exit 1
printf '%s' "$ON" >"$W/.claude/settings.json" && git -C "$W" commit -qam "local on" || exit 1
rc=$(run)
check "on only in a local commit on main, not pushed: off" 'said "reviewers: off"'
git -C "$W" reset -q --hard origin/main || exit 1
printf '%s' "$ON" >"$W/.claude/settings.json"; rc=$(run); git -C "$W" checkout -q -- .claude/settings.json
check "on only in an uncommitted edit: off" 'said "reviewers: off"'
printf '%s' "$ON" >"$W/.claude/settings.local.json"; rc=$(run); rm "$W/.claude/settings.local.json"
check "on only in .claude/settings.local.json: off" 'said "reviewers: off"'
printf '%s' "$ON" >"$HOME/.claude/settings.json"; rc=$(run); rm "$HOME/.claude/settings.json"
check "on only in ~/.claude/settings.json: off" 'said "reviewers: off"'
main_has "$ON"
printf '%s' "$OFF" >"$W/.claude/settings.json"; printf '%s' "$OFF" >"$W/.claude/settings.local.json"; printf '%s' "$OFF" >"$HOME/.claude/settings.json"
rc=$(run)
git -C "$W" checkout -q -- .claude/settings.json; rm "$W/.claude/settings.local.json" "$HOME/.claude/settings.json"
check "on in main, off in the working tree, local and user settings: on" 'said "reviewers: on"'

# From a subdirectory, the top level's repository is read.
mkdir -p "$W/sub dir/deeper"
rc=$(run "$W/sub dir/deeper")
check "from a subdirectory: on, as at the top level" 'said "reviewers: on"'

# The default branch is the one origin's HEAD names, not main, and not the clone's own
# record of it (origin/HEAD, still main).
main_has "$ON"; git -C "$SEED" push -q origin HEAD:trunk || exit 1
main_has "$OFF"; git -C "$O" symbolic-ref HEAD refs/heads/trunk
rc=$(run)
check "origin's HEAD names trunk, on, while main is off: on" 'said "reviewers: on" && [ "$(git -C "$W" symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/main ]'
main_has '{'; git -C "$SEED" push -q -f origin HEAD:trunk || exit 1; main_has "$ON"
rc=$(run)
check "trunk invalid while main is on: unknown, naming trunk" 'said "reviewers: unknown - .claude/settings.json on trunk could not be read as JSON"'
git -C "$O" symbolic-ref HEAD refs/heads/main
rc=$(run)
check "origin's HEAD back on main: on" 'said "reviewers: on"'

# Where no default branch can be found or read: unknown.
main_has "$ON"; git -C "$W" fetch -q origin
git -C "$W" remote set-url origin "$root/gone.git"; rc=$(run); git -C "$W" remote set-url origin "$O"
check "an unreachable origin, while the local origin/main says on: unknown" 'said "reviewers: unknown - origin'"'"'s default branch main could not be fetched" && [ "$(tracked_settings)" = "$ON" ]'
git -C "$O" update-ref --no-deref HEAD "$(git -C "$O" rev-parse main)" && git -C "$W" remote set-head origin -d || exit 1
rc=$(run)
check "origin's HEAD names no branch and the clone has no origin/HEAD: unknown" 'said "reviewers: unknown - origin'"'"'s default branch could not be found"'
git -C "$O" symbolic-ref HEAD refs/heads/main && git -C "$W" remote set-head origin main >/dev/null || exit 1
rc=$(run)
check "with origin/HEAD back, on again" 'said "reviewers: on"'
git init -q -b main "$root/no remote" && (cd "$root/no remote" && mkdir .claude && printf '%s' "$ON" >.claude/settings.json && git add -A && git commit -qm on) || exit 1
rc=$(run "$root/no remote")
check "a repository with no origin remote, its own file on: unknown" 'said "reviewers: unknown - the checkout has no origin remote"'
mkdir "$root/plain"
rc=$(run "$root/plain")
check "outside a git repository: unknown" 'said "reviewers: unknown - not inside a git repository"'
# Without jq, nothing can be read: the tools mentat reviewers needs, but jq.
mkdir "$root/nojq"
for t in bash env dirname readlink git sed head cat; do ln -s "$(command -v "$t")" "$root/nojq/$t"; done
rc=$(cd "$W" && PATH="$root/nojq" "$mentat" reviewers >"$STUB/out" 2>"$STUB/err"; echo $?)
check "without jq: unknown" 'said "reviewers: unknown - jq is not installed"'

# Usage: no arguments.
rc=$(cd "$W" && "$mentat" reviewers on >"$STUB/out" 2>"$STUB/err"; echo $?)
check "an argument is a usage error (exit 64), with nothing on stdout" '[ "$rc" = 64 ] && [ "$(cat "$STUB/err")" = "mentat: usage: mentat reviewers" ] && [ ! -s "$STUB/out" ]'
rc=$("$mentat" nonsense >/dev/null 2>"$STUB/err"; echo $?)
check "mentat's usage names mentat reviewers" '[ "$rc" = 64 ] && grep -qF "| mentat reviewers |" "$STUB/err"'

[ "$failures" -eq 0 ]
