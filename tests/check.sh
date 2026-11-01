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
      # The account's private repository names: $STUB/repos, by default one on the list,
      # and those reached only as a collaborator, $STUB/repos_collaborator. Any other
      # affiliation fails. A failed lookup also prints a name, which must never reach the output.
      'user/repos?affiliation=owner,organization_member,collaborator&visibility=private&per_page=100')
        if [ -f "$STUB/repos_fail" ]; then echo stubleakedrepo; echo stubleakedrepo >&2; exit 1; fi
        # The list was readable a moment ago, so the comparison itself fails.
        if [ -f "$STUB/list_unreadable_after_lookup" ]; then chmod 000 "$HOME/.config/mentat/private-words"; fi
        if [ -f "$STUB/repos" ]; then cat "$STUB/repos"; else echo stubword; fi
        if [ -f "$STUB/repos_collaborator" ]; then cat "$STUB/repos_collaborator"; fi ;;
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
check "a missing private word list skips the comparison" '! grep -q "user/repos" "$STUB/calls"'
reset; mv "$LIST.away" "$LIST"; chmod 000 "$LIST"; rc=$(run); chmod 600 "$LIST"
check "an unreadable private word list warns, still exit 0" '[ "$rc" = 0 ] && grep -q "^WARN: the private word list" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ]'
check "an unreadable private word list skips the comparison" '! grep -q "user/repos" "$STUB/calls"'

# The word list against the account's private repositories. Every case but the failed
# lookup's has names on the stub, and none may be printed.
ALL_MATCH="OK: the private word list has every private repository this account can reach"
no_name() { ! grep -qi -e stubword -e stubkept -e stubmissing -e stubleakedrepo -e stubother "$STUB/out"; }
reset; rc=$(run)
check "none missing is OK with no warning" '[ "$rc" = 0 ] && grep -qxF "$ALL_MATCH" "$STUB/out" && [ "$(last)" = "Check OK (0 warning(s))" ] && no_name'
check "asks once for private repositories as owner, organization member or collaborator" '[ "$(grep -cxF "api -X GET user/repos?affiliation=owner,organization_member,collaborator&visibility=private&per_page=100 --paginate --jq .[].name" "$STUB/calls")" = 1 ]'

reset; echo stubmissing-collaborator >"$STUB/repos_collaborator"; rc=$(run)
check "a repository reached only as a collaborator counts as missing when it is not on the list" '[ "$rc" = 0 ] && grep -q "^WARN: 1 private repository name(s)" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ] && no_name'

reset; printf 'stubword\nstubmissing-one\nstubmissing-two\n' >"$STUB/repos"
before=$(cd "$root" && find home cwd -type f -exec cksum {} + && find home cwd | sort); rc=$(run)
after=$(cd "$root" && find home cwd -type f -exec cksum {} + && find home cwd | sort)
check "some missing warns with the count, still exit 0" '[ "$rc" = 0 ] && grep -q "^WARN: 2 private repository name(s) are not whole lines of the private word list" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ] && ! grep -qxF "$ALL_MATCH" "$STUB/out"'
check "some missing prints no name" 'no_name'
check "some missing writes nothing, there or locally" '[ ! -f "$STUB/writes" ] && [ "$before" = "$after" ]'

reset; echo STUBWORD >"$STUB/repos"; rc=$(run)
check "a differently cased repository name is on the list" '[ "$rc" = 0 ] && grep -qxF "$ALL_MATCH" "$STUB/out" && [ "$(last)" = "Check OK (0 warning(s))" ] && no_name'
reset; echo stubword >"$STUB/repos"; cp "$LIST" "$LIST.keep"; echo STUBWORD >"$LIST"; rc=$(run); mv "$LIST.keep" "$LIST"
check "a differently cased list line covers the repository" '[ "$rc" = 0 ] && grep -qxF "$ALL_MATCH" "$STUB/out" && no_name'

reset; touch "$STUB/repos"; rc=$(run)
check "no private repositories is OK with no warning" '[ "$rc" = 0 ] && grep -qxF "$ALL_MATCH" "$STUB/out" && [ "$(last)" = "Check OK (0 warning(s))" ]'

reset; touch "$STUB/repos_fail"; rc=$(run)
check "a failed lookup warns it could not compare, still exit 0" '[ "$rc" = 0 ] && grep -q "^WARN: could not compare the private word list" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ] && ! grep -qxF "$ALL_MATCH" "$STUB/out"'
check "a failed lookup prints no name" 'no_name'

reset; touch "$STUB/list_unreadable_after_lookup"; rc=$(run); chmod 600 "$LIST"
check "a failing comparison warns it could not compare, prints no OK line, no name and no path, still exit 0" '[ "$rc" = 0 ] && grep -qx "OK: the private word list is readable" "$STUB/out" && grep -q "^WARN: could not compare the private word list" "$STUB/out" && [ "$(last)" = "Check OK (1 warning(s))" ] && ! grep -qxF "$ALL_MATCH" "$STUB/out" && no_name && ! grep -qF "$HOME" "$STUB/out"'
# Bash 3.2 writes a here-string to a temporary file, and check changes nothing locally.
check "lib/check.sh uses no here-string" '! grep -qF "<<<" "$(dirname "$mentat")/../lib/check.sh"'

reset; echo stubkept-whole >"$STUB/repos"; cp "$LIST" "$LIST.keep"; echo stubkept >"$LIST"; rc=$(run); mv "$LIST.keep" "$LIST"
check "a list line that is only part of a repository name does not cover it" '[ "$rc" = 0 ] && grep -q "^WARN: 1 private repository name(s)" "$STUB/out" && no_name'

reset; printf 'stubother\nstubkept\n' >"$STUB/repos"; cp "$LIST" "$LIST.keep"; printf '\n#stubother\n  \n# a comment\nstubkept\n' >"$LIST"; rc=$(run); mv "$LIST.keep" "$LIST"
check "blank and # list lines cover nothing" '[ "$rc" = 0 ] && grep -q "^WARN: 1 private repository name(s)" "$STUB/out" && no_name'
reset; echo stubother >"$STUB/repos"; cp "$LIST" "$LIST.keep"; : >"$LIST"; rc=$(run); mv "$LIST.keep" "$LIST"
check "an empty list misses every repository" '[ "$rc" = 0 ] && grep -q "^WARN: 1 private repository name(s)" "$STUB/out" && no_name'

reset; touch "$STUB/signed_out"; rc=$(run)
check "signed out, the comparison does not run" '[ "$rc" = 1 ] && ! grep -q "user/repos" "$STUB/calls"'

# The command the docs give lists the missing names, by the same lookup.
doc_command=$(grep '^gh api -X GET ' "$(dirname "$mentat")/../docs/how-it-works.md")
reset; printf 'stubword\nSTUBWORD\nstubmissing-one\n' >"$STUB/repos"; doc_out=$(bash -c "$doc_command" 2>&1)
check "the docs' command lists only the missing names" '[ "$doc_out" = stubmissing-one ]'

rc=$("$mentat" check owner/repo >/dev/null 2>&1; echo $?)
check "an argument is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
