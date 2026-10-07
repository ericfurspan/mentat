#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat check`, using a stub gh. Prints PASS/FAIL per case;
# exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/cwd"
failures=0
check() { if eval "$2"; then printf 'PASS: check %s\n' "$1"; else printf 'FAIL: check %s\n' "$1"; failures=$((failures + 1)); fi; }

# gh: files in $STUB switch behavior. Any call that is not a GET or a read is
# recorded in $STUB/writes and fails.
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "auth status") [ -f "$STUB/signed_out" ] && exit 1; echo "token: gho_secret"; exit 0 ;;
  "repo view") [ -f "$STUB/no_repo" ] && exit 1; echo owner/repo ;;
  "api -X")
    [ "$3" = GET ] || { echo "$*" >>"$STUB/writes"; exit 98; }
    case "$4" in
      repos/owner/repo) [ -f "$STUB/unreadable" ] && exit 1; echo owner/repo ;;
      repos/owner/repo/actions/secrets) [ -f "$STUB/secrets_unreadable" ] && exit 1; cat "$STUB/secrets" ;;
      *) exit 1 ;;
    esac ;;
  *) echo "$*" >>"$STUB/writes"; exit 99 ;;
esac
STUBEOF
# codex: prints a version unless $STUB/no_version exists.
cat >"$root/bin/codex" <<'STUBEOF'
#!/usr/bin/env bash
[ "$1" = --version ] && [ ! -f "$STUB/no_version" ] && echo "codex-cli 9.9.9"
exit 0
STUBEOF
chmod +x "$root/bin/gh" "$root/bin/codex"
export PATH="$root/bin:$PATH"

reset() { rm -f "$STUB"/*; echo 0 >"$STUB/secrets"; }
run() { (cd "$root/cwd" && "$mentat" check "$@" >"$STUB/out" 2>&1); echo $?; }
last() { tail -n 1 "$STUB/out"; }

reset; rc=$(run)
check "a ready setup is Check OK (exit 0)" '[ "$rc" = 0 ] && [ "$(last)" = "Check OK (0 warning(s))" ] && grep -q "OK: owner/repo is readable" "$STUB/out"'
check "finds the repository from the checkout" 'grep -qx "repo view --json nameWithOwner --jq .nameWithOwner" "$STUB/calls"'
check "writes nothing, there or locally" '[ ! -f "$STUB/writes" ] && [ -z "$(ls -A "$root/cwd")" ]'
check "never prints what gh auth status prints" '! grep -q gho_secret "$STUB/out"'
check "prints the installed codex version" 'grep -qx "OK: codex is installed (codex-cli 9.9.9)" "$STUB/out"'
reset; touch "$STUB/no_version"; rc=$(run)
check "a codex with no version is still OK" '[ "$rc" = 0 ] && grep -qx "OK: codex is installed (version unknown)" "$STUB/out"'

reset; rc=$(run owner/repo)
check "takes owner/repo" '[ "$rc" = 0 ] && ! grep -q "repo view" "$STUB/calls"'

reset; echo 3 >"$STUB/secrets"; rc=$(run)
check "Actions secrets are a warning, not a failure" '[ "$rc" = 0 ] && grep -q "WARN: owner/repo has 3 Actions secret(s)" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ]'
reset; touch "$STUB/secrets_unreadable"; rc=$(run)
check "unreadable secrets are a warning that says so" '[ "$rc" = 0 ] && grep -q "WARN: could not read whether" "$STUB/out"'

reset; touch "$STUB/signed_out"; rc=$(run)
check "gh signed out fails (exit 1)" '[ "$rc" = 1 ] && grep -q "PROBLEM: gh is not signed in" "$STUB/out" && [ "$(last)" = "Check failed: 1 problem(s)" ]'
reset; touch "$STUB/unreadable"; rc=$(run)
check "an unreadable repository fails" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read owner/repo" "$STUB/out"'
reset; touch "$STUB/no_repo"; rc=$(run)
check "no repository to find fails and asks for owner/repo" '[ "$rc" = 1 ] && grep -q "pass owner/repo" "$STUB/out"'

# Without codex: a PATH of the stub gh, links to git and jq, and every directory
# that has no codex in it.
mkdir "$root/nocodex"
ln -s "$root/bin/gh" "$(command -v git)" "$(command -v jq)" "$root/nocodex/"
nocodex="$root/nocodex"
oldifs=$IFS; IFS=:
for d in $PATH; do [ -x "$d/codex" ] || nocodex="$nocodex:$d"; done
IFS=$oldifs
reset; rc=$(PATH="$nocodex" run)
check "codex missing is a warning" '[ "$rc" = 0 ] && grep -q "WARN: codex is not installed" "$STUB/out"'

rc=$("$mentat" check a/b/c >/dev/null 2>&1; echo $?)
check "a malformed owner/repo is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
