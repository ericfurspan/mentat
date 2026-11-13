#!/usr/bin/env bash
# shellcheck disable=SC2016
# (File-wide: each check is a string evaluated after its case runs.)
# Checks the marketplace and its module plugins: each manifest parses and matches its
# marketplace entry, the marketplace lists the core plugin and the four modules, the
# modules' descriptions stay short, and this repository's committed settings turn on
# the modules it uses. Prints PASS/FAIL per case; exits 1 on any FAIL.
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

[ "$failures" -eq 0 ]
