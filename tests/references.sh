#!/usr/bin/env bash
# Names and file references in the instruction text. Prints PASS/FAIL lines; exits 1 on any FAIL.
#
# Planning is mentat:plan, with no alias: no file but CHANGELOG.md and the decision records in
# docs/adr/ names the old planning skill or its folder, or the next-work file.
# The names are built from pieces, so this file holds none of them.
#
# A file a skill file (SKILL.md, a supporting file or CREDITS.md, module skills included), rules.md
# or AGENTS.md names in backticks exists: `name.md` or `../<skill>/name.md` relative to a skill
# file's folder, or at the repository root, such as rules.md; `name.md` in `mentat:<skill>`'s folder
# (or a module's skill) and `mentat:<skill>`'s `name.md` in that skill's folder; and a path from the
# repository root such as `skills/backlog/records.md`, except one in a CREDITS.md in parentheses
# right after a link, which cites the linked repository. File names may hold capitals and underscores,
# such as `../build/SKILL.md`; `NNNN-slug.md`, the shape of a decision record not yet written, is skipped.
# tests/references-cases.sh runs it on invented skill files.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
pass() { printf 'PASS: references %s\n' "$1"; }
fail() { printf 'FAIL: references %s\n' "$1"; failures=$((failures + 1)); }

old=propose ending=next-work
banned=$(git grep -n -I -F --untracked -e "mentat:$old" -e "skills/$old" -e "$ending.md" -- . ':!CHANGELOG.md' ':!docs/adr/')
if [ -z "$banned" ]; then
  pass "no file but CHANGELOG.md and docs/adr/ names the old planning skill, its folder or the next-work file"
else
  fail "files name the old planning skill, its folder or the next-work file:"
  printf '%s\n' "$banned"
fi

# skill_path <owner> <file>: the path of <file> in the folder of the skill <owner> (mentat:<skill> or mentat-<module>:<skill>).
skill_path() {
  case $1 in
    mentat:*) printf 'skills/%s/%s\n' "${1#mentat:}" "$2" ;;
    *) printf 'plugins/%s/skills/%s/%s\n' "${1%%:*}" "${1#*:}" "$2" ;;
  esac
}
name='[A-Za-z][A-Za-z0-9_-]*\.md'
in_folder="\`$name\` in \`mentat(-[a-z-]+)?:[a-z-]+\`'s folder"
owners_file="\`mentat(-[a-z-]+)?:[a-z-]+\`'s \`$name\`"
files=$( { printf '%s\n' rules.md AGENTS.md; git ls-files --cached --others --exclude-standard -- 'skills/*.md' 'plugins/*/skills/*.md'; } | sort -u)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case $f in
    rules.md | AGENTS.md) dir=. ;;
    *) dir=${f%/*} ;;
  esac
  refs=$(sed -E -e "s/$in_folder//g" -e "s/$owners_file//g" "$f" | grep -o -E "\`(\.\./[a-z-]+/)?$name\`" | tr -d '\`' | sort -u)
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    case $ref in
      NNNN-*) continue ;;
      ../*) ;;
      *) if [ -f "$ref" ]; then continue; fi ;;
    esac
    if [ -f "$dir/$ref" ]; then
      pass "$f names $ref, which exists"
    else
      fail "$f names $ref, but $dir/$ref is missing"
    fi
  done <<<"$refs"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    file=${ref%% *}; owner=${ref#* in }; owner=${owner%"'s folder"}
    path=$(skill_path "$owner" "$file")
    if [ -f "$path" ]; then
      pass "$f names $file in $owner's folder, which exists"
    else
      fail "$f names $file in $owner's folder, but $path is missing"
    fi
  done <<<"$(grep -o -E "$in_folder" "$f" | tr -d '\`' | sort -u)"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    owner=${ref%%"'s "*}; file=${ref#*"'s "}
    path=$(skill_path "$owner" "$file")
    if [ -f "$path" ]; then
      pass "$f names $owner's $file, which exists"
    else
      fail "$f names $owner's $file, but $path is missing"
    fi
  done <<<"$(grep -o -E "$owners_file" "$f" | tr -d '\`' | sort -u)"
  # A path from the repository root. In a CREDITS.md, one in parentheses right after a link
  # cites the linked repository, so it is left out.
  cited='s/^$//'
  case $f in
    *CREDITS.md) cited="s/\]\(https?:\/\/[^)]*\) \(\`[^\`]*\`\)//g" ;;
  esac
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ -f "$ref" ]; then
      pass "$f names $ref, which exists"
    else
      fail "$f names $ref, but it is missing"
    fi
  done <<<"$(sed -E "$cited" "$f" | grep -o -E "\`[a-z][a-z0-9._-]*(/[A-Za-z0-9._-]+)+\.md\`" | tr -d '\`' | sort -u)"
done <<<"$files"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
