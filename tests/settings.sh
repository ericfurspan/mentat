#!/usr/bin/env bash
# docs/settings.md and the code agree on Mentat's settings. Every MENTAT_* name the code names
# is a listed setting or an internal name below; every listed setting is read somewhere, by
# an expansion, by `printenv <name>` in a skill, or by jq as `.env.<name>` of a repository's
# settings file; an empty value counts as unset (no
# ${NAME-...} or ${NAME=...}); and each listed default is the code's. A default in code is the
# value after ":-" in its one ${NAME:-value} expansion, or, when that value is another
# variable ($VAR or ${VAR}), the literal that variable is assigned; or the backticked value a
# skill line reading it by printenv gives as "unset or empty, <words> is `<value>`". The list writes such a
# default as that value in backticks. A setting with no such default in code is listed in
# words: one read by `printenv <name>` as "The <definition> definition's own model.", the
# definition being the agents/ file its reading line names; any other as off ("Off...").
# Prints PASS/FAIL per check; exits 1 on any FAIL.
# shellcheck disable=SC2016
# (File-wide: backticks and $ in single quotes are literal on purpose.)
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
pass() { printf 'PASS: settings %s\n' "$1"; }
fail() { printf 'FAIL: settings %s\n' "$1"; failures=$((failures + 1)); }

doc=docs/settings.md

# Names the code uses that are not settings, each with why: Mentat's code sets them for
# itself, or only its tests set them.
internal="MENTAT_ROOT bin/mentat sets it for the reviewers module's entries, which find the shared code by it
MENTAT_OWN_HOOK git-hooks/own-hook.sh sets it for the hooks it runs, so a hook does not run itself again
MENTAT_GIT_HOOKS_DIR only tests set it, to point at a copy of the git hooks
MENTAT_REPO lib/shared.sh sets it for the awk program it runs
MENTAT_HEAD lib/shared.sh sets it for the awk program it runs
MENTAT_ROOTS lib/shared.sh sets it for the awk program it runs
MENTAT_REVIEW_MODEL_DEFAULT lib/review.sh assigns it, as the one place the review default is named
MENTAT_REVIEW_INTERVAL_SECONDS only tests set it, to shorten how often a review polls CI
MENTAT_CI_TIMEOUT_SECONDS only tests set it, to shorten the wait for CI
MENTAT_CI_GRACE_SECONDS only tests set it, to shorten the wait for CI to start
MENTAT_GROK_TIMEOUT_SECONDS a retired setting: the Grok adapter looks at it only so mentat check can say it is no longer read"
internal_names=$(printf '%s\n' "$internal" | cut -d' ' -f1)

# The code: scripts, hooks, skills, agents and rules, tracked or new, never tests, docs or the changelog.
code_files=$(git ls-files --cached --others --exclude-standard -- bin lib hooks git-hooks plugins skills agents rules.md | sort -u)
if [ -z "$code_files" ]; then
  fail "found no code files to scan"
  exit 1
fi
# Read once, then searched through here-strings: grep -q stopping early on a pipe would
# fail it under pipefail.
code=$(printf '%s\n' "$code_files" | tr '\n' '\0' | xargs -0 cat) || { fail "could not read the code files"; exit 1; }

if [ ! -f "$doc" ]; then
  fail "$doc must exist and list every setting"
  exit 1
fi

# The listed settings: the first cell of each table row whose key is a MENTAT_* name in backticks.
rows=$(grep -E '^\| *`MENTAT_[A-Z0-9_]+` *\|' "$doc")
listed=$(printf '%s\n' "$rows" | sed -E 's/^\| *`(MENTAT_[A-Z0-9_]+)`.*/\1/' | grep -v '^$')
if [ -z "$listed" ]; then
  fail "$doc lists no setting"
  exit 1
fi
dups=$(printf '%s\n' "$listed" | sort | uniq -d)
if [ -z "$dups" ]; then pass "$doc lists each setting once"; else fail "$doc lists more than once: $(printf '%s' "$dups" | tr '\n' ' ')"; fi

# Every MENTAT_* name the code names is a listed setting or an internal name.
named=$(grep -oE 'MENTAT_[A-Z0-9_]+' <<<"$code" | sort -u)
missing=""
while IFS= read -r n; do
  [ -n "$n" ] || continue
  grep -qxF "$n" <<<"$listed
$internal_names" || missing="$missing $n"
done <<<"$named"
if [ -z "$missing" ]; then
  pass "every MENTAT_* name in the code is a listed setting or an internal name"
else
  fail "the code names MENTAT_* names that $doc does not list and that are not internal:$missing"
fi

# No internal name is listed as a setting.
both=""
while IFS= read -r n; do
  grep -qxF "$n" <<<"$internal_names" && both="$both $n"
done <<<"$listed"
if [ -z "$both" ]; then pass "no internal name is listed as a setting"; else fail "$doc lists internal names:$both"; fi

while IFS= read -r n; do
  # Read somewhere: an expansion, printenv by name, or jq reading a settings file's env.
  if grep -qE "\\\$\\{?$n([^A-Z0-9_]|\$)|printenv $n([^A-Z0-9_]|\$)|\\.env\\.$n([^A-Z0-9_]|\$)" <<<"$code"; then
    pass "$n is read in the code"
  else
    fail "$n is listed in $doc but read nowhere in the code"
  fi
  # An empty value counts as unset.
  if grep -qE "\\\$\\{${n}[-=]" <<<"$code"; then
    fail "$n is read with \${$n-...} or \${$n=...}, so a set but empty value does not count as unset"
  fi
  # The default in code: the value of its ${NAME:-value} expansions, and of each line reading
  # it by printenv that says "unset or empty, <words> is `<value>`".
  defaults=$( {
    grep -oE "\\\$\\{$n:-[^}]*\\}" <<<"$code" | sed -E "s/^\\\$\\{$n:-//; s/\\}\$//"
    grep -E "printenv $n([^A-Z0-9_]|\$)" <<<"$code" | grep -oE 'unset or empty, [^.`]* is `[^`]+`' | sed -E 's/.*`([^`]+)`$/\1/'
  } | grep -v '^$')
  count=$(printf '%s' "$defaults" | grep -c '^' | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    fail "$n's default is named $count times in the code; name it once"
    continue
  fi
  code_default=$defaults
  case "$code_default" in
    '$'*)
      var=$(printf '%s' "$code_default" | tr -d '${}')
      code_default=$(sed -nE "s/^[[:space:]]*$var=//p" <<<"$code" | head -n 1 | sed -E "s/^[\"']//; s/[\"']\$//")
      if [ -z "$code_default" ]; then
        fail "$n's default is $var, which the code assigns no literal"
        continue
      fi
      ;;
  esac
  row=$(printf '%s\n' "$rows" | grep -E "^\| *\`$n\` *\|" | head -n 1)
  doc_default=$(printf '%s\n' "$row" | awk -F'|' '{ gsub(/^ +| +$/, "", $4); print $4 }')
  doc_empty=$(printf '%s\n' "$row" | awk -F'|' '{ gsub(/^ +| +$/, "", $5); print $5 }')
  if [ -z "$doc_empty" ]; then
    fail "$n's row in $doc says nothing about an empty value"
  fi
  if [ -n "$code_default" ]; then
    if [ "$doc_default" = "\`$code_default\`" ]; then
      pass "$n's listed default is the code's ($code_default)"
    else
      fail "$n's listed default is \"$doc_default\", but the code's is \`$code_default\`"
    fi
  elif printenv_lines=$(grep -E "printenv $n([^A-Z0-9_]|\$)" <<<"$code"); then
    # Read by printenv in a skill to set a subagent's model: the default is the definition's
    # own model, the definition being the one agents/ file the reading line names as mentat:<name>.
    agents=""
    while IFS= read -r a; do
      [ -n "$a" ] && [ -f "agents/$a.md" ] && agents="$agents $a"
    done < <(grep -oE 'mentat:[a-z-]+' <<<"$printenv_lines" | sed 's/^mentat://' | sort -u)
    agents=${agents# }
    case "$agents" in
      '' | *' '*)
        fail "$n is read by printenv on lines naming no one agent definition (found: ${agents:-none})"
        continue
        ;;
    esac
    expected="The $(printf '%s' "$agents" | tr '-' ' ') definition's own model."
    if [ "$doc_default" = "$expected" ]; then
      pass "$n's listed default is the $agents definition's own model"
    else
      fail "$n's listed default is \"$doc_default\", but unset it runs the $agents definition's own model: \"$expected\""
    fi
  else
    # Read in shell code with no default: unset or empty is off.
    case "$doc_default" in
      Off | Off[.:]*) pass "$n has no default in the code, and $doc lists it as off" ;;
      *) fail "$n has no default in the code, so unset it is off, but $doc lists \"$doc_default\"" ;;
    esac
  fi
done <<<"$listed"

# A setting the general rule names as refusing an empty value says so in its row.
refusing=$(grep -oE 'except (`MENTAT_[A-Z0-9_]+`(, | and )?)+, which refuses it' "$doc" | grep -oE 'MENTAT_[A-Z0-9_]+')
[ -n "$refusing" ] || fail "$doc names no setting as refusing an empty value"
for n in $refusing; do
  doc_empty=$(printf '%s\n' "$rows" | grep -E "^\| *\`$n\` *\|" | head -n 1 | awk -F'|' '{ gsub(/^ +| +$/, "", $5); print $5 }')
  case "$doc_empty" in
    Refused*) pass "$n refuses an empty value, and its row says so" ;;
    *) fail "$n refuses an empty value, but its row's empty value is \"$doc_empty\"" ;;
  esac
done

[ "$failures" -eq 0 ] || exit 1
