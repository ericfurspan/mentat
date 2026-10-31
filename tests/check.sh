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
      repos/owner/repo) [ -f "$STUB/unreadable" ] && exit 1
        case "$*" in
          *delete_branch_on_merge*)
            if [ -f "$STUB/keeps_branches" ]; then echo false
            elif [ -f "$STUB/setting_unreadable" ]; then echo unknown
            else echo true; fi ;;
          *) echo owner/repo ;;
        esac ;;
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
# grok: prints a version unless $STUB/no_grok_version exists.
cat >"$root/bin/grok" <<'STUBEOF'
#!/usr/bin/env bash
[ "$1" = --version ] && [ ! -f "$STUB/no_grok_version" ] && echo "grok 9.9.9 (stub) [stable]"
exit 0
STUBEOF
chmod +x "$root/bin/gh" "$root/bin/codex" "$root/bin/grok"
export PATH="$root/bin:$PATH"

export HOME="$root/home"
LIST="$HOME/.config/mentat/private-words"
mkdir -p "$(dirname "$LIST")"
echo stubword >"$LIST"
reset() { rm -f "$STUB"/*; }
run() { (cd "$root/cwd" && "$mentat" check >"$STUB/out" 2>&1); echo $?; }
last() { tail -n 1 "$STUB/out"; }

reset; rc=$(run)
check "a ready setup is Check OK (exit 0)" '[ "$rc" = 0 ] && [ "$(last)" = "Check OK (0 warning(s))" ] && grep -q "OK: owner/repo is readable" "$STUB/out"'
check "finds the repository from the checkout" 'grep -qx "repo view --json nameWithOwner --jq .nameWithOwner" "$STUB/calls"'
check "writes nothing, there or locally" '[ ! -f "$STUB/writes" ] && [ -z "$(ls -A "$root/cwd")" ]'
check "never prints what gh auth status prints" '! grep -q gho_secret "$STUB/out"'
check "prints the installed codex version" 'grep -qx "OK: codex is installed (codex-cli 9.9.9)" "$STUB/out"'
reset; touch "$STUB/no_version"; rc=$(run)
check "a codex with no version is still OK" '[ "$rc" = 0 ] && grep -qx "OK: codex is installed (version unknown)" "$STUB/out"'

check "prints the installed grok version" 'grep -qx "OK: grok is installed (grok 9.9.9 (stub) \[stable\])" "$STUB/out"'
reset; touch "$STUB/no_grok_version"; rc=$(run)
check "a grok with no version is still OK" '[ "$rc" = 0 ] && grep -qx "OK: grok is installed (version unknown)" "$STUB/out"'
# Grok is optional: without it, nothing is printed about it and there is no warning.
mkdir "$root/nogrok"; for t in git jq; do ln -s "$(command -v $t)" "$root/nogrok/$t"; done; ln -s "$root/bin/gh" "$root/bin/codex" "$root/nogrok/"
reset; rc=$(cd "$root/cwd" && PATH="$root/nogrok:/usr/bin:/bin" "$mentat" check >"$STUB/out" 2>&1; echo $?)
check "a missing grok prints nothing and warns of nothing" '[ "$rc" = 0 ] && ! grep -qi grok "$STUB/out" && [ "$(last)" = "Check OK (0 warning(s))" ]'
# Codex is needed for mentat review, challenge and weigh: without it, check fails.
mkdir "$root/nocodex"; for t in git jq; do ln -s "$(command -v $t)" "$root/nocodex/$t"; done; ln -s "$root/bin/gh" "$root/bin/grok" "$root/nocodex/"
reset; rc=$(cd "$root/cwd" && PATH="$root/nocodex:/usr/bin:/bin" "$mentat" check >"$STUB/out" 2>&1; echo $?)
check "a missing codex is a problem (exit 1) that says what still runs without it" '[ "$rc" = 1 ] && grep -qx "PROBLEM: codex is not installed: mentat review, mentat challenge and mentat weigh need it; mentat ci and mentat review --grok still run without it" "$STUB/out" && [ "$(last)" = "Check failed: 1 problem(s)" ]'

reset; touch "$STUB/signed_out"; rc=$(run)
check "gh signed out fails (exit 1)" '[ "$rc" = 1 ] && grep -q "PROBLEM: gh is not signed in" "$STUB/out" && [ "$(last)" = "Check failed: 1 problem(s)" ]'
reset; touch "$STUB/unreadable"; rc=$(run)
check "an unreadable repository fails" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read owner/repo" "$STUB/out"'
reset; rc=$(run)
check "deleted merged head branches are reported OK" '[ "$rc" = 0 ] && grep -qx "OK: merged head branches are deleted" "$STUB/out" && [ "$(last)" = "Check OK (0 warning(s))" ]'
reset; touch "$STUB/keeps_branches"; rc=$(run)
check "kept merged head branches warn, still exit 0, and write nothing" '[ "$rc" = 0 ] && grep -q "^WARN: merged head branches are kept after merge" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ] && [ ! -f "$STUB/writes" ]'
reset; touch "$STUB/setting_unreadable"; rc=$(run)
check "an unreadable branch setting warns, still exit 0" '[ "$rc" = 0 ] && grep -q "^WARN: could not read whether merged head branches are deleted" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ]'
reset; touch "$STUB/no_repo"; rc=$(run)
check "no repository to find fails and says to run it inside a checkout" '[ "$rc" = 1 ] && grep -q "run mentat check inside a checkout" "$STUB/out"'

reset; rc=$(run)
check "a readable private word list is OK, and its words are not printed" '[ "$rc" = 0 ] && grep -qx "OK: the private word list is readable" "$STUB/out" && ! grep -q stubword "$STUB/out"'
reset; mv "$LIST" "$LIST.away"; rc=$(run)
check "a missing private word list warns, still exit 0, and prints no home path" '[ "$rc" = 0 ] && grep -qx "WARN: the private word list ~/.config/mentat/private-words is missing or unreadable: the publish check looks only for the home path" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ] && ! grep -qF "$HOME" "$STUB/out"'
reset; mv "$LIST.away" "$LIST"; chmod 000 "$LIST"; rc=$(run); chmod 600 "$LIST"
check "an unreadable private word list warns, still exit 0" '[ "$rc" = 0 ] && grep -q "^WARN: the private word list" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ]'

rc=$("$mentat" check owner/repo >/dev/null 2>&1; echo $?)
check "an argument is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
