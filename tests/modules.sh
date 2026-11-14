#!/usr/bin/env bash
# shellcheck disable=SC2016
# (File-wide: each check is a string evaluated after its case runs.)
# Checks the marketplace and its module plugins: each manifest parses and matches its
# marketplace entry, the marketplace lists the core plugin and the four modules, the
# modules' descriptions stay short, this repository's committed settings turn on
# the modules it uses, and bin/mentat hands the reviewers module's commands to its
# entries. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
check() { if eval "$2"; then printf 'PASS: modules %s\n' "$1"; else printf 'FAIL: modules %s\n' "$1"; failures=$((failures + 1)); fi; }

market=.claude-plugin/marketplace.json
settings=.claude/settings.json
modules="mentat-reviewers mentat-linear mentat-extras mentat-public-text"

check "$market parses" 'jq -e . "$market" >/dev/null'
mname=$(jq -r '.name // empty' "$market" 2>/dev/null)
check "the marketplace lists exactly the core plugin and the four modules" \
  '[ "$(jq -r "[.plugins[].name] | sort | join(\" \")" "$market")" = "mentat mentat-extras mentat-linear mentat-public-text mentat-reviewers" ]'
check "the core plugin is served from the repository root" \
  '[ "$(jq -r ".plugins[] | select(.name == \"mentat\") | .source" "$market")" = ./ ]'

words=0
for m in $modules; do
  manifest=plugins/$m/.claude-plugin/plugin.json
  check "$manifest parses" 'jq -e "type == \"object\"" "$manifest" >/dev/null'
  check "$manifest is named $m" '[ "$(jq -r ".name" "$manifest")" = "$m" ]'
  check "the marketplace serves $m from ./plugins/$m" \
    '[ "$(jq -r --arg m "$m" ".plugins[] | select(.name == \$m) | .source" "$market")" = "./plugins/$m" ]'
  check "the marketplace entry for $m has the manifest's description" \
    '[ -n "$(jq -r ".description // empty" "$manifest")" ] && [ "$(jq -r --arg m "$m" ".plugins[] | select(.name == \$m) | .description" "$market")" = "$(jq -r ".description" "$manifest")" ]'
  n=$(jq -r '.description // empty' "$manifest" 2>/dev/null | wc -w | tr -d ' ')
  words=$((words + n))
done
check "the four module descriptions are at most 150 words together ($words)" '[ "$words" -le 150 ]'

check "$settings parses" 'jq -e . "$settings" >/dev/null'
for m in mentat-reviewers mentat-public-text; do
  check "$settings turns on $m@$mname" '[ -n "$mname" ] && jq -e --arg k "$m@$mname" ".enabledPlugins[\$k] == true" "$settings" >/dev/null'
done
for m in mentat-linear mentat-extras; do
  check "$settings leaves $m@$mname to each user" '! jq -e --arg k "$m@$mname" ".enabledPlugins | has(\$k)" "$settings" >/dev/null'
done

# bin/mentat hands review --codex, review --grok and second-opinion to the reviewers module's
# entries, with the arguments after the mode and MENTAT_ROOT set to its own folder: the entry
# on PATH, else the copy in plugins/mentat-reviewers/bin, else it exits 64. Each stub entry
# prints its name and MENTAT_ROOT, then each argument in brackets, and exits 7. PATH holds
# only the system folders besides, so no copy a session with the module on has there runs.
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC2034 # here is read by the checks
here=$(pwd -P) sys=/usr/bin:/bin
mkdir "$tmp/stubs" || exit 1
for e in mentat-review-codex mentat-review-grok mentat-second-opinion; do
  cat >"$tmp/stubs/$e" <<'EOF'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$MENTAT_ROOT"
for a; do printf '[%s]\n' "$a"; done
exit 7
EOF
  chmod +x "$tmp/stubs/$e" || exit 1
done
handed() { # $1 entry, $2 MENTAT_ROOT it must get, $3... the arguments it must get
  local want="$1 $2" a
  shift 2
  for a; do want="$want
[$a]"; done
  [ "$rc" = 7 ] && [ "$out" = "$want" ]
}
out=$(MENTAT_ROOT=/elsewhere PATH="$tmp/stubs:$sys" bin/mentat second-opinion --web "a b" "" 2>&1); rc=$?
check "second-opinion goes to mentat-second-opinion on PATH, with its arguments, MENTAT_ROOT set to this folder and its exit status" 'handed mentat-second-opinion "$here" --web "a b" ""'
out=$(PATH="$tmp/stubs:$sys" bin/mentat review --codex --request "a b" 7 2>&1); rc=$?
check "review --codex goes to mentat-review-codex on PATH, with the arguments after --codex" 'handed mentat-review-codex "$here" --request "a b" 7'
out=$(PATH="$tmp/stubs:$sys" bin/mentat review --grok --stop 7 2>&1); rc=$?
check "review --grok goes to mentat-review-grok on PATH, with the arguments after --grok" 'handed mentat-review-grok "$here" --stop 7'

# With none on PATH: a copy of core whose module folder holds the stubs.
mkdir -p "$tmp/core/plugins/mentat-reviewers" && cp -R bin lib "$tmp/core/" && cp -R "$tmp/stubs" "$tmp/core/plugins/mentat-reviewers/bin" || exit 1
core=$(cd -P "$tmp/core" && pwd) || exit 1
out=$(PATH="$sys" "$core/bin/mentat" second-opinion "a b" 2>&1); rc=$?
check "with none on PATH, second-opinion goes to the module's copy in the checkout" 'handed mentat-second-opinion "$core" "a b"'
out=$(PATH="$sys" "$core/bin/mentat" review --codex 7 2>&1); rc=$?
check "with none on PATH, review --codex goes to the module's copy in the checkout" 'handed mentat-review-codex "$core" 7'
out=$(PATH="$sys" "$core/bin/mentat" review --grok 7 2>&1); rc=$?
check "with none on PATH, review --grok goes to the module's copy in the checkout" 'handed mentat-review-grok "$core" 7'
# This checkout's own entries, through the fallback: each reads its arguments (a usage error).
out=$(PATH="$sys" bin/mentat second-opinion 2>&1); rc=$?
check "with none on PATH, this checkout's mentat-second-opinion runs" '[ "$rc" = 64 ] && [ "$out" = "mentat: usage: mentat second-opinion [--web] <file> | mentat second-opinion --link <item id> <idea file>" ]'
for args in "--codex --stop 7" "--grok --stop --stop 7"; do
  # shellcheck disable=SC2086 # the words are the arguments
  out=$(PATH="$sys" bin/mentat review $args 2>&1); rc=$?
  check "with none on PATH, this checkout's entry reads review $args" '[ "$rc" = 64 ] && [ "$out" = "mentat: usage: mentat review [--local | --codex | --grok [--stop]] [--request <file>] [--require-ci] <pull request number>" ]'
done

# With neither: a copy of core without the module.
mkdir "$tmp/bare" && cp -R bin lib "$tmp/bare/" || exit 1
for args in "second-opinion a" "review --codex 7" "review --grok 7"; do
  # shellcheck disable=SC2086 # the words are the arguments
  out=$(PATH="$sys" "$tmp/bare/bin/mentat" $args 2>&1); rc=$?
  check "with no entry on PATH or in the checkout, $args exits 64 naming the module and no vendor tool" '[ "$rc" = 64 ] && [ "$out" = "mentat: this command needs the mentat-reviewers module, which was not found: turn it on and run again" ] && ! grep -qi -e codex -e grok <<<"$out"'
done

# An entry run alone, without MENTAT_ROOT, says what it needs.
for e in mentat-review-codex mentat-review-grok mentat-second-opinion; do
  out=$(env -u MENTAT_ROOT "plugins/mentat-reviewers/bin/$e" 7 2>&1); rc=$?
  check "$e without MENTAT_ROOT exits 64 and says it needs it" '[ "$rc" = 64 ] && grep -q "^$e: needs MENTAT_ROOT" <<<"$out"'
done

[ "$failures" -eq 0 ]
