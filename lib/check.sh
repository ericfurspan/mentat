# shellcheck shell=bash
# mentat check. Sourced by bin/mentat.

# Check reads GitHub and changes nothing, there or locally. It looks only for
# what Mentat itself needs, plus one repository setting, whether merged head
# branches are deleted, which it warns about and never changes. The rest of the
# repository's settings (rulesets, required approvals, merge methods) are the
# owner's and are not read. It also reads the names of the private repositories
# the signed-in account can reach, as owner, organization member or collaborator,
# to compare them with the private word list, and prints only how many are missing.
# When claude is installed, it reads the local plugin list, and prints only the scope
# and version of each copy of the Mentat plugin.
check_problems=0 check_warnings=0
c_ok() { printf 'OK: %s\n' "$1"; }
c_problem() { printf 'PROBLEM: %s\n' "$1"; check_problems=$((check_problems + 1)); }
c_warn() { printf 'WARN: %s\n' "$1"; check_warnings=$((check_warnings + 1)); }
c_finish() {
  if [ "$check_problems" -gt 0 ]; then
    printf 'Check failed: %d problem(s)\n' "$check_problems"; exit 1
  fi
  printf 'Check OK (%d warning(s))\n' "$check_warnings"; exit 0
}
# Warns with a count, never a name, for each private repository that is not a whole
# line of the word list, ignoring case. Blank lines and # lines match no repository
# name. Success with no output means no private repositories, not a failed lookup.
# A pipe, not a here-string: bash 3.2 writes a here-string to a temporary file. grep
# exits 1 when none are missing and above 1 on an error.
c_word_list_covers_repos() {
  local names missing=0 rc=0
  names=$(gh api -X GET 'user/repos?affiliation=owner,organization_member,collaborator&visibility=private&per_page=100' --paginate --jq '.[].name' 2>/dev/null) || rc=2
  if [ "$rc" = 0 ] && [ -n "$names" ]; then
    missing=$(printf '%s\n' "$names" | grep -vixF -c -f "$PRIVATE_WORDS" 2>/dev/null) || rc=$?
  fi
  if [ "$rc" -gt 1 ]; then
    c_warn "could not compare the private word list with your private repositories"
  elif [ "$missing" -gt 0 ]; then
    c_warn "$missing private repository name(s) are not whole lines of the private word list: 'The publish check' in docs/how-it-works.md gives the command that lists them"
  else
    c_ok "the private word list has every private repository this account can reach"
  fi
}
# Warns when the Mentat plugin is installed at more than one version. Says nothing with
# no claude command. The variable keeps the list off the network and out of the plugin
# cache's in-use markers: without it, claude does both. jq -e fails on empty output, and
# a scope or version that is not one plain word counts as unreadable, so a path cannot print.
c_plugin_copies() {
  local copies
  command -v claude >/dev/null 2>&1 || return 0
  if ! copies=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude plugin list --json </dev/null 2>/dev/null | jq -er '
    def word: if type == "string" and test("^[A-Za-z0-9._+-]+$") then . else error("unreadable") end;
    if type == "array" then . else error("not a list") end
    | [.[] | select(.id == "mentat@mentat") | {scope: (.scope | word), version: (.version | word)}]
    | if (map(.version) | unique | length) > 1 then map(.scope + " " + .version) | join(", ") else "" end
  ' 2>/dev/null); then
    c_warn "could not compare the installed Mentat plugin copies"
  elif [ -n "$copies" ]; then
    c_warn "the Mentat plugin is installed at different versions: $copies"
  else
    c_ok "no Mentat plugin copies at different versions"
  fi
}
check() {
  local repo tool v d list_ok=""
  [ $# -eq 0 ] || die "usage: mentat check" 64
  for tool in git gh jq; do
    if command -v "$tool" >/dev/null 2>&1; then c_ok "$tool is installed"; else c_problem "$tool is not installed"; fi
  done
  [ "$check_problems" = 0 ] || c_finish
  if command -v codex >/dev/null 2>&1; then
    v=$(codex --version 2>/dev/null | head -n 1)
    c_ok "codex is installed (${v:-version unknown})"
  else c_problem "codex is not installed: mentat review, mentat challenge and mentat weigh need it; mentat ci and mentat review --grok still run without it"; fi
  # Grok is optional: no warning when it is missing.
  if command -v grok >/dev/null 2>&1; then
    v=$(grok --version 2>/dev/null | head -n 1)
    c_ok "grok is installed (${v:-version unknown})"
  fi
  c_plugin_copies
  # The publish check still looks for the home path without the list.
  if [ -f "$PRIVATE_WORDS" ] && [ -r "$PRIVATE_WORDS" ]; then c_ok "the private word list is readable"; list_ok=1
  else c_warn "the private word list ~/.config/mentat/private-words is missing or unreadable: the publish check looks only for the home path"; fi
  # Exit status only: gh auth status can print token details.
  if gh auth status >/dev/null 2>&1; then c_ok "gh is signed in"; else c_problem "gh is not signed in (run gh auth login)"; c_finish; fi
  [ -z "$list_ok" ] || c_word_list_covers_repos
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || repo=""
  [ -n "$repo" ] || { c_problem "could not tell which GitHub repository this is; run mentat check inside a checkout of it"; c_finish; }
  if gh api -X GET "repos/$repo" --jq .full_name >/dev/null 2>&1; then c_ok "$repo is readable"
  else c_problem "could not read $repo"; c_finish; fi
  d=$(gh api -X GET "repos/$repo" --jq .delete_branch_on_merge 2>/dev/null) || d=""
  case "$d" in
    true) c_ok "merged head branches are deleted" ;;
    false) c_warn "merged head branches are kept after merge: turn on 'Automatically delete head branches' in the repository's General settings" ;;
    *) c_warn "could not read whether merged head branches are deleted" ;;
  esac
  c_finish
}
