# shellcheck shell=bash
# mentat check. Sourced by bin/mentat.

# Check reads GitHub and changes nothing there. Locally it changes nothing but this: to
# read whether outside reviewers are on here (reviewers_state in lib/shared.sh), it fetches
# origin's default branch into a temporary ref of its own, deleted after; fetched objects
# and an empty ref folder may stay. It looks only for
# what Mentat itself needs, plus, only when ~/.config/mentat/warn-kept-branches
# exists, one repository setting, whether merged head branches are deleted, which
# it warns about and never changes. The rest of the repository's settings (rulesets, required approvals, merge methods) are the
# owner's and are not read. When the private word list is readable, it also reads the
# names of the private repositories the signed-in account can reach, as owner,
# organization member or collaborator, to compare them with the list, and prints only
# how many are missing. With no list, it says nothing about it.
# When claude is installed, it reads its version and the local plugin list, and prints
# only the Claude Code version, the scope and version of each copy of the Mentat plugin,
# and the names of the Mentat modules installed.
# It warns when agents' git does not use the git hook templates (lib/templates.sh), and
# when it does, a missing or changed installed copy, or a missing gitleaks or jq, is a
# problem.
KEPT_BRANCHES_FILE="$HOME/.config/mentat/warn-kept-branches"
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
# line of the word list with a leading exact: removed, ignoring case. Blank lines and
# # lines match no repository name. Success with no output means no private
# repositories, not a failed lookup. A pipe, not a here-string: bash 3.2 writes a
# here-string to a temporary file. grep exits 1 when none are missing and above 1 on
# an error.
c_word_list_covers_repos() {
  local names list missing=0 rc=0
  names=$(gh api -X GET 'user/repos?affiliation=owner,organization_member,collaborator&visibility=private&per_page=100' --paginate --jq '.[].name' 2>/dev/null) || rc=2
  if [ "$rc" = 0 ] && [ -n "$names" ]; then
    list=$(sed 's/^exact://' "$PRIVATE_WORDS" 2>/dev/null) || rc=2
  fi
  if [ "$rc" = 0 ] && [ -n "$names" ]; then
    missing=$(printf '%s\n' "$names" | grep -vixF -c -e "$list" 2>/dev/null) || rc=$?
  fi
  if [ "$rc" -gt 1 ]; then
    c_warn "could not compare the private word list with your private repositories"
  elif [ "$missing" -gt 0 ]; then
    c_warn "$missing private repository name(s) are not whole lines of the private word list; to list them, run: gh api -X GET 'user/repos?affiliation=owner,organization_member,collaborator&visibility=private&per_page=100' --paginate --jq '.[].name' | grep -vixF -f <(sed 's/^exact://' ~/.config/mentat/private-words)"
  else
    c_ok "the private word list has every private repository this account can reach"
  fi
}
# Warns when the Mentat plugin is installed at more than one version. Says nothing with
# no claude command. The variable keeps the list off the network and out of the plugin
# cache's in-use markers: without it, claude does both. jq -e fails on empty output, and
# a scope or version that is not one plain word counts as unreadable, so a path cannot print.
# A list it could read is kept in plugin_list for c_modules.
plugin_list=""
c_plugin_copies() {
  local copies list
  command -v claude >/dev/null 2>&1 || return 0
  if ! list=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude plugin list --json </dev/null 2>/dev/null) ||
    ! copies=$(printf '%s' "$list" | jq -er '
    def word: if type == "string" and test("^[A-Za-z0-9._+-]+$") then . else error("unreadable") end;
    if type == "array" then . else error("not a list") end
    | [.[] | select(.id == "mentat@mentat") | {scope: (.scope | word), version: (.version | word)}]
    | if (map(.version) | unique | length) > 1 then map(.scope + " " + .version) | join(", ") else "" end
  ' 2>/dev/null); then
    c_warn "could not compare the installed Mentat plugin copies"
  else
    plugin_list=$list
    if [ -n "$copies" ]; then
      c_warn "the Mentat plugin is installed at different versions: $copies"
    else
      c_ok "no Mentat plugin copies at different versions"
    fi
  fi
}
# Names the optional Mentat modules installed at any scope, from the list c_plugin_copies
# read. Says nothing when it read none.
c_modules() {
  local on
  [ -n "$plugin_list" ] || return 0
  on=$(printf '%s' "$plugin_list" | jq -r '[.[] | .id | strings
    | select(test("^mentat-(reviewers|linear|extras|public-text)@mentat$")) | sub("@mentat$"; "")]
    | unique | join(", ")' 2>/dev/null) || return 0
  if [ -n "$on" ]; then
    c_ok "Mentat modules installed: $on"
  else
    c_ok "no Mentat modules installed (optional: mentat-reviewers, mentat-linear, mentat-extras, mentat-public-text)"
  fi
}
# The git hook templates (lib/templates.sh): a warning when agents' git does not use
# them; when it does, one problem per problem with the installed copy.
c_templates() {
  local dir problems p IFS=$'\n'
  if ! dir=$(templates_dir); then
    c_warn "the git hook templates are not in use for agents: no core.hooksPath entry in GIT_CONFIG_* names them"
    return 0
  fi
  # shellcheck disable=SC2154 # root, Mentat's folder, is set by bin/mentat.
  if problems=$(templates_problems "$root" "$dir"); then
    c_ok "the git hook templates in $dir are installed and current"
    return 0
  fi
  set -f
  for p in $problems; do c_problem "$p"; done
  set +f
}
# Claude Code 2.1.295 or later: it honors the merge hook's onFailure block, where an older
# one lets the hook's failure through, and it applies --tools and --restricted to every
# built-in tool, which the review's reviewer relies on with --safe-mode (2.1.169 and later).
# Says nothing with no claude command. Prints only the version's leading numbers, never
# the rest of what claude prints.
c_claude_version() {
  local v a b c
  command -v claude >/dev/null 2>&1 || return 0
  v=$(CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude --version </dev/null 2>/dev/null | head -n 1 |
    sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\([^0-9.].*\)\{0,1\}$/\1/p')
  if [ -z "$v" ]; then
    c_problem "could not read the Claude Code version: the merge hook and the locked-down mentat review need Claude Code 2.1.295 or later"
    return 0
  fi
  a=${v%%.*} c=${v##*.}
  b=${v#*.} b=${b%.*}
  if [ "$a" -gt 2 ] || { [ "$a" -eq 2 ] && { [ "$b" -gt 1 ] || { [ "$b" -eq 1 ] && [ "$c" -ge 295 ]; }; }; }; then
    c_ok "Claude Code $v is installed (2.1.295 or later, which the merge hook and the locked-down mentat review need)"
  else
    c_problem "Claude Code $v is older than 2.1.295, so the merge hook does not block a call when it fails and the tool limits of mentat review may not hold: update Claude Code"
  fi
}
# Whether outside reviewers are on here (reviewers_state in lib/shared.sh), then whether
# codex and grok are installed: a missing one is a warning only when they are on.
# shellcheck disable=SC2154 # reviewers, reviewers_why and reviewers_def are set by reviewers_here
c_reviewers() {
  local pair tool name
  reviewers_here
  case "$reviewers" in
    on) c_ok "outside reviewers are on here (mentat-reviewers is on in .claude/settings.json on $reviewers_def)" ;;
    off) c_ok "outside reviewers are off here (mentat-reviewers is not on in .claude/settings.json on $reviewers_def)" ;;
    *) c_warn "outside reviewers are unknown here: $reviewers_why; Codex and Grok will not run" ;;
  esac
  for pair in codex:Codex grok:Grok; do
    tool=${pair%%:*} name=${pair#*:}
    if command -v "$tool" >/dev/null 2>&1; then c_ok "$tool is installed"
    elif [ "$reviewers" = on ]; then c_warn "$tool is not installed: $name reviews will not run here"
    else c_ok "$tool is not installed"; fi
  done
}
# The review tool: Claude Code, which mentat review needs.
c_review_tools() {
  command -v claude >/dev/null 2>&1 || c_problem "claude is not installed: mentat review needs Claude Code"
}
check() {
  local repo tool v d list_ok=""
  [ $# -eq 0 ] || die "usage: mentat check" 64
  for tool in git gh jq; do
    if command -v "$tool" >/dev/null 2>&1; then c_ok "$tool is installed"; else c_problem "$tool is not installed"; fi
  done
  [ "$check_problems" = 0 ] || c_finish
  c_review_tools
  # Only the git hook templates need gitleaks: with them in use, c_templates reports a missing one as a problem.
  if command -v gitleaks >/dev/null 2>&1; then
    v=$(gitleaks version 2>/dev/null | head -n 1)
    c_ok "gitleaks is installed (${v:-version unknown})"
  fi
  c_templates
  c_claude_version
  c_plugin_copies
  c_modules
  c_reviewers
  # The publish check still looks for the home path without the list. No list is not a warning.
  if [ ! -e "$PRIVATE_WORDS" ]; then :
  elif [ -f "$PRIVATE_WORDS" ] && [ -r "$PRIVATE_WORDS" ]; then c_ok "the private word list is readable"; list_ok=1
  else c_warn "the private word list ~/.config/mentat/private-words is unreadable: the publish check looks only for the home path"; fi
  # Exit status only: gh auth status can print token details.
  if gh auth status >/dev/null 2>&1; then c_ok "gh is signed in"; else c_problem "gh is not signed in (run gh auth login)"; c_finish; fi
  [ -z "$list_ok" ] || c_word_list_covers_repos
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || repo=""
  [ -n "$repo" ] || { c_problem "could not tell which GitHub repository this is; run mentat check inside a checkout of it"; c_finish; }
  if gh api -X GET "repos/$repo" --jq .full_name >/dev/null 2>&1; then c_ok "$repo is readable"
  else c_problem "could not read $repo"; c_finish; fi
  [ -e "$KEPT_BRANCHES_FILE" ] || c_finish
  d=$(gh api -X GET "repos/$repo" --jq .delete_branch_on_merge 2>/dev/null) || d=""
  case "$d" in
    true) c_ok "merged head branches are deleted" ;;
    false) c_warn "merged head branches are kept after merge: turn on 'Automatically delete head branches' in the repository's General settings" ;;
    *) c_warn "could not read whether merged head branches are deleted" ;;
  esac
  c_finish
}
