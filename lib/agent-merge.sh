# shellcheck shell=bash
# shellcheck disable=SC2016,SC2020
# (File-wide: the patterns hold $ and backticks in single quotes on purpose.)
# The one reader of the agent-merge settings, and what a repository that turns them on
# allows. Sourced by hooks/no-merge (which decides offline, with no gh and no network) and
# by bin/mentat (`mentat agent-merge`). It only defines functions.
#
# MENTAT_AGENT_MERGE: the value on lets a session merge its own ready pull request; unset,
# empty or any other value is off. MENTAT_MERGE_WAIT_PATHS: the repository's protected
# paths, separated by commas or whitespace; an entry ending in / covers that folder, any
# other entry is one file. .github/ and .claude/ are always protected. Both are read only
# from env of .claude/settings.json as committed on origin's default branch, never from the
# process environment, user or local settings, the working tree or another branch. A
# reading that cannot be made is off for the setting and a wait for the paths: an unknown
# commit, a failed diff and an unreadable list never pass.

# am_ref <repo>: prints the local ref of origin's default branch (refs/remotes/origin/<name>),
# from the local origin/HEAD; fails when there is none or the ref does not exist.
am_ref() {
  local sym
  sym=$(git -C "$1" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || return 1
  [ -n "$sym" ] || return 1
  git -C "$1" rev-parse -q --verify "$sym^{commit}" >/dev/null 2>&1 || return 1
  printf '%s\n' "$sym"
}

# am_agent_merge <repo> <ref>: prints on or off. Anything that cannot be read is off.
am_agent_merge() {
  local v
  v=$(git -C "$1" show "$2:.claude/settings.json" 2>/dev/null | jq -r '(.env.MENTAT_AGENT_MERGE // empty) | strings' 2>/dev/null) || v=""
  if [ "$v" = on ]; then printf 'on\n'; else printf 'off\n'; fi
}

# am_wait_list <repo> <ref>: prints the protected paths, one per line: .github/ and .claude/,
# then the setting's entries. Fails when the setting cannot be read (a file that is not one
# JSON object, an env that is not an object, a list that is not a string).
am_wait_list() {
  local raw
  raw=$(git -C "$1" show "$2:.claude/settings.json" 2>/dev/null | jq -er '
    if type != "object" then error("not an object")
    elif has("env") | not then ""
    elif (.env | type) != "object" then error("env")
    elif (.env | has("MENTAT_MERGE_WAIT_PATHS")) | not then ""
    elif (.env.MENTAT_MERGE_WAIT_PATHS | type) != "string" then error("list")
    else .env.MENTAT_MERGE_WAIT_PATHS end' 2>/dev/null) || return 1
  printf '%s\n' ".github/" ".claude/"
  printf '%s\n' "$raw" | tr ',[:space:]' '\n\n' | grep -v '^$' | sed 's#^\./##' || true
}

# am_protected <repo> <ref> <commit>: sets am_hits (the protected paths the commit changes
# from the merge base of <ref> and the commit, one per line, both names of a rename) and
# returns 0, or sets am_why and returns 1 when that cannot be decided: the commit is not in
# this repository, there is no merge base, the diff fails or the wait list cannot be read.
am_protected() {
  local repo=$1 ref=$2 commit=$3 list base paths p e
  am_hits="" am_why=""
  if ! list=$(am_wait_list "$repo" "$ref"); then am_why="the wait list in .claude/settings.json could not be read"; return 1; fi
  if ! git -C "$repo" cat-file -e "$commit^{commit}" 2>/dev/null; then am_why="the commit is not in this repository"; return 1; fi
  if ! base=$(git -C "$repo" merge-base "$ref" "$commit" 2>/dev/null) || [ -z "$base" ]; then am_why="no merge base with the default branch"; return 1; fi
  paths=$(mktemp) || { am_why="no temporary file"; return 1; }
  # -z, so that git's quoting of an unusual name cannot hide a protected folder.
  if ! git -C "$repo" diff --name-only --no-renames -z "$base" "$commit" >"$paths" 2>/dev/null; then
    rm -f "$paths"; am_why="the changed files could not be read"; return 1
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    while IFS= read -r e; do
      case "$e" in
        */) if [ "${p#"$e"}" != "$p" ]; then am_hits="$am_hits$p"$'\n'; break; fi ;;
        *) if [ "$p" = "$e" ]; then am_hits="$am_hits$p"$'\n'; break; fi ;;
      esac
    done <<<"$list"
  done < <(tr '\0' '\n' <"$paths")
  rm -f "$paths"
  am_hits=${am_hits%$'\n'}
  return 0
}

# The hook's part. am_hook <command> runs inside hooks/no-merge's check (a subshell that
# `verdict` ends) with the hook's $input and field. It returns 0 when it decides nothing,
# and the hook goes on to its own denial; or ends the check with a pass or a deny.
# The pattern of a gh pr merge command is the hook's own, so that the two agree on what a
# merge command is (hooks/no-merge and tests/no-merge.sh keep them together).
am_flags='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]"'"'"'][^[:space:]"'"'"']*)?)*'
am_merge_pattern="(^|[^[:alnum:]_.-])gh${am_flags}[[:space:]]+pr${am_flags}[[:space:]]+merge([[:space:]]|\$)"
# The one allowed form: one optional leading PATH= assignment (unquoted, or in double quotes
# with no backtick, backslash or parenthesis), then gh pr merge <number> --merge
# --match-head-commit <40 hex characters>, and nothing else.
am_path_value='("[^"`\\()]*"|[^[:space:]"`'"'"'\\;&|<>()]+)'
am_allowed_form="^(PATH=${am_path_value}[[:blank:]]+)?gh[[:blank:]]+pr[[:blank:]]+merge[[:blank:]]+[0-9]+[[:blank:]]+--merge[[:blank:]]+--match-head-commit[[:blank:]]+[0-9a-f]{40}\$"
am_form_reason="the maintainer merges, except that this repository lets a session merge its own ready pull request with exactly: gh pr merge <number> --merge --match-head-commit <40-hex commit>, run alone (at most one leading PATH= assignment). Any other merge command is denied. If this command only mentions a merge in its text, such as a commit message or pull request body, pass that text through a file (-F or --body-file)."

am_hook() { # $1 command
  local cmd=$1 cwd ref sha
  # Class h: a command that matches no merge pattern is not this function's business, and
  # nothing below it (git, the settings) is touched.
  grep -Eq "$am_merge_pattern" <<<"$cmd" || return 0
  cwd=$(field '.cwd') || return 0
  [ -n "$cwd" ] || return 0
  ref=$(am_ref "$cwd") || return 0
  [ "$(am_agent_merge "$cwd" "$ref")" = on ] || return 0
  # The setting is on. Every command but the allowed form is denied, naming that form.
  case "$cmd" in
    *[\;\&\|\`\<\>]* | *'$('* | *$'\n'*) verdict deny "$am_form_reason" ;;
  esac
  [[ $cmd =~ $am_allowed_form ]] || verdict deny "$am_form_reason"
  sha=${cmd: -40}
  if ! am_protected "$cwd" "$ref" "$sha"; then
    verdict deny "this pull request waits for the maintainer to merge it: $am_why."
  fi
  if [ -n "$am_hits" ]; then
    verdict deny "this pull request waits for the maintainer to merge it: its head changes a protected path ($(printf '%s' "$am_hits" | head -n 3 | tr '\n' ' ' | sed 's/ $//; s/ /, /g'))."
  fi
  verdict pass
}

# mentat agent-merge <N>: prints one line, exit 0: "agent merge: on", "agent merge: off" or
# "agent merge: waits for the maintainer (<reasons>)". A read it cannot make exits non-zero
# with no result line, which counts as waiting. It fetches origin's default branch (a normal
# fetch, so origin/<default> moves, which is what the hook reads) and reads the settings from
# there; with the setting off it reads nothing from GitHub. It waits unless all hold: the
# setting is on; #N is open, based on the default branch and opened by the signed-in
# account; its description's Status line is exactly "**Status:** Ready"; its head's CI
# passed (no checks waits); the base branch has no merge queue rule; its head changes no
# protected path; and no Local Claude review or Outside review comment this account posted
# on #N, on any head, holds "(high risk)". It posts and merges nothing.
am_wait_line() { printf 'agent merge: waits for the maintainer (%s)\n' "$1"; }
agent_merge_command() {
  local pr top def ref repo me json state base author head first reasons="" why rc out risky queue rules
  [ $# -eq 1 ] || die "usage: mentat agent-merge <pull request number>" 64
  pr=$1
  case "$pr" in '' | *[!0-9]*) die "usage: mentat agent-merge <pull request number>" 64 ;; esac
  command -v jq >/dev/null 2>&1 || die "jq is not installed"
  top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || die "not inside a git repository"
  git -C "$top" remote get-url origin >/dev/null 2>&1 || die "the checkout has no origin remote"
  def=$(default_branch "$top")
  [ -n "$def" ] || die "origin's default branch could not be found"
  ref="refs/remotes/origin/$def"
  if ! GIT_TERMINAL_PROMPT=0 git -C "$top" fetch -q --no-tags origin "+refs/heads/$def:$ref" >/dev/null 2>&1; then
    am_wait_line "origin's default branch $def could not be fetched"
    return 0
  fi
  if [ "$(am_agent_merge "$top" "$ref")" != on ]; then
    printf 'agent merge: off\n'
    return 0
  fi
  # The hook reads the setting from the local origin/HEAD, so it must name the branch just read.
  if [ "$(am_ref "$top" 2>/dev/null)" != "$ref" ]; then
    am_wait_line "this checkout's origin/HEAD does not name $def, which the merge hook reads; run: git remote set-head origin $def"
    return 0
  fi
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) && [ -n "$repo" ] || die "could not read the repository with gh"
  me=$(gh api user --jq .login) && [ -n "$me" ] || die "could not read which GitHub account gh is signed in as"
  json=$(gh pr view "$pr" --json state,baseRefName,headRefOid,body,author) || die "could not read pull request #$pr"
  state=$(jq -r '.state | strings' <<<"$json") || die "could not read pull request #$pr"
  base=$(jq -r '.baseRefName | strings' <<<"$json") || die "could not read pull request #$pr"
  head=$(jq -r '.headRefOid | strings' <<<"$json") || die "could not read pull request #$pr"
  author=$(jq -r '.author.login | strings' <<<"$json") || die "could not read pull request #$pr"
  first=$(jq -r '.body | strings' <<<"$json" | head -n 1) || die "could not read pull request #$pr"
  [ -n "$head" ] || die "could not read the head of pull request #$pr"
  first=${first%$'\r'}
  [ "$state" = OPEN ] || reasons="$reasons; it is not open"
  [ "$base" = "$def" ] || reasons="$reasons; its base is not $def"
  [ "$author" = "$me" ] || reasons="$reasons; it was opened by another account"
  [ "$first" = '**Status:** Ready' ] || reasons="$reasons; its Status line is not exactly Ready"
  rules=$(gh api "repos/$repo/rules/branches/$def") || die "could not read the branch rules of $def"
  queue=$(jq -r 'any(.[]; .type == "merge_queue")' <<<"$rules") || die "could not read the branch rules of $def"
  [ "$queue" = false ] || reasons="$reasons; $def has a merge queue"
  if am_protected "$top" "$ref" "$head"; then
    [ -z "$am_hits" ] || reasons="$reasons; its head changes a protected path ($(printf '%s' "$am_hits" | head -n 3 | tr '\n' ' ' | sed 's/ $//; s/ /, /g'))"
  else
    reasons="$reasons; its head could not be checked for protected paths ($am_why)"
  fi
  risky=$(gh api --paginate "repos/$repo/issues/$pr/comments" | jq -rs --arg me "$me" '
    [.[][] | select(.user.login == $me)
      | select((.body | split("\n")[0] | sub("\r$"; "")) as $h | ($h | startswith("## Local Claude review of ")) or ($h | startswith("## Outside review of ")))
      | select(.body | contains("(high risk)"))] | length') || die "could not read the comments on #$pr"
  [ "$risky" = 0 ] || reasons="$reasons; a review marked a change high risk"
  if [ -z "$reasons" ]; then
    # Only a pull request nothing else holds back waits for CI, which can take a while.
    out=$(require_ci=yes wait_for_ci "$repo" "$head" "" "$pr" "mentat agent-merge" 2>/dev/null)
    rc=$?
    case "$rc" in
      0) ;;
      3) reasons="$reasons; its head moved" ;;
      4)
        case "$out" in
          *"No CI checks ran"*) why="no CI checks ran on its head" ;;
          *"conflicts with its base"*) why="CI did not run on its head, which conflicts with its base branch" ;;
          *"did not finish"*) why="CI did not finish on its head" ;;
          *) why="CI did not pass on its head" ;;
        esac
        reasons="$reasons; $why" ;;
      *) die "could not read CI on $head" ;;
    esac
  fi
  if [ -z "$reasons" ]; then
    printf 'agent merge: on\n'
  else
    am_wait_line "${reasons#; }"
  fi
}
