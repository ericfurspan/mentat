# shellcheck shell=bash
# mentat status. Sourced by bin/mentat.

# Status prints one line of a pull request's review state, read from the comments
# the review commands post (lib/codex.sh, lib/grok.sh) and the Claude review rounds
# skills/claude-review posts. It posts, edits and pushes nothing. Only comments by the
# account gh is signed in as count: anyone who can comment could post the same text.
# tests/run fails when a heading these match changes where it is written.

# One line per review comment by $3 on pull request $2 of repository $1, oldest
# first: "codex <sha> <no-findings|findings|incomplete> <fingerprint>",
# "claude <sha> <fingerprint or none>", "grok-done <sha> <result> <fingerprint>",
# "grok-started <sha>" or "grok-unfinished <sha>". A Claude round's fingerprint is its
# last line holding only "Agreed request fingerprint: <value>", so findings that quote one do not count.
status_comments() { # $1 repo, $2 pull request, $3 this account's login
  gh api --paginate "repos/$1/issues/$2/comments" | jq -rs --arg me "$3" '
    def review($who): capture("^## Local " + $who + " review of (?<sha>[0-9a-f]{40}): (?<res>no findings|findings|incomplete), spec fingerprint (?<fp>[^ ]+)$");
    .[][] | select(.user.login == $me) | .body as $b | ($b | split("\n")[0] | sub("\r$"; "")) as $h |
    if ($h | test("^## Local Codex review of ")) then
      $h | review("Codex") | "codex \(.sha) \(.res | gsub(" "; "-")) \(.fp)"
    elif ($h | test("^## Local Grok review of ")) then
      $h | review("Grok") | "grok-done \(.sha) \(.res | gsub(" "; "-")) \(.fp)"
    elif ($h | test("^Grok review started on [0-9a-f]{40}$")) then
      "grok-started \($h | ltrimstr("Grok review started on "))"
    elif ($h | test("^Grok review did not finish on [0-9a-f]{40}: ")) then
      "grok-unfinished \($h | capture("^Grok review did not finish on (?<sha>[0-9a-f]{40}): ").sha)"
    elif ($h | test("^(#+ +)?Claude review round [0-9]+ on [0-9a-f]{7,40}\\b")) then
      "claude \($h | capture("Claude review round [0-9]+ on (?<sha>[0-9a-f]{7,40})").sha) \([$b | split("\n")[] | capture("^\\s*(?:[-*] )?`?Agreed request fingerprint: `?(?<fp>[0-9a-f]{12}|none)`?\\s*$").fp] | last // "none")"
    else empty end'
}

status() {
  local pr="" request_file="" request fp repo me head lines ci kind sha res lfp
  local codex=0 claude=0 last="" last_fp="" grok=none reviewed out
  [ $# -ge 1 ] && pr=$1
  case "$#:${2:-}" in
    1:) ;;
    3:--request) request_file=$3 ;;
    *) pr="" ;;
  esac
  case "$pr" in '' | *[!0-9]*) die "usage: mentat status <pull request number> [--request <file>]" 64 ;; esac
  if [ $# -eq 3 ]; then
    # Read and fingerprinted as mentat review --request does (read_request).
    if [ ! -f "$request_file" ] || [ ! -r "$request_file" ] || ! request=$(cat "$request_file"); then
      die "could not read the agreed request file: $request_file"
    fi
    printf '%s' "$request" | grep -q '[^[:space:]]' || die "the agreed request file is empty: $request_file"
    if ! fp=$(request_fingerprint "$request") || [ -z "$fp" ]; then die "could not fingerprint the agreed request"; fi
  fi
  if ! repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || [ -z "$repo" ]; then
    die "could not read the repository with gh"
  fi
  if ! me=$(gh api user --jq .login) || [ -z "$me" ]; then die "could not read which GitHub account gh is signed in as"; fi
  if ! head=$(gh pr view "$pr" --json headRefOid --jq .headRefOid) || [ -z "$head" ]; then die "could not read pull request #$pr"; fi
  lines=$(status_comments "$repo" "$pr" "$me") || die "could not read the comments on #$pr"
  # An incomplete Codex review is not a round (skills/review); Grok's start comment
  # and its result or did-not-finish comment are one run, and the last one says where it stands.
  # An incomplete Grok result is posted without a did-not-finish comment (lib/grok.sh).
  while read -r kind sha res lfp; do
    case "$kind" in
      codex) [ "$res" = incomplete ] && continue; codex=$((codex + 1)); last=$sha last_fp=$lfp ;;
      claude) claude=$((claude + 1)); last=$sha last_fp=$res ;;
      grok-started) grok=running ;;
      grok-done) if [ "$res" = incomplete ]; then grok="did not finish"; else grok='done'; fi ;;
      grok-unfinished) grok="did not finish" ;;
    esac
  done <<<"$lines"
  if [ -z "$last" ]; then reviewed="no (no review yet)"
  else
    case "$head" in "$last"*) reviewed=yes ;; *) reviewed="no (last reviewed ${last:0:7})" ;; esac
  fi
  lines=$(ci_lines "$repo" "$head") || die "could not read CI on $head"
  if [ -z "$lines" ]; then ci=none
  elif grep -q '^fail ' <<<"$lines"; then ci=failed
  elif grep -q '^pending ' <<<"$lines"; then ci=running
  else ci=passed; fi
  out="head ${head:0:7}, codex rounds $codex"
  [ "$claude" -eq 0 ] || out="$out, claude rounds $claude"
  out="$out, head reviewed: $reviewed, grok: $grok, ci: $ci"
  if [ -n "$request_file" ]; then
    if [ -z "$last" ]; then out="$out, spec: no review yet"
    elif [ "$last_fp" = "$fp" ]; then out="$out, spec: matches"
    else out="$out, spec: differs (last review ${last_fp:-none}, file $fp)"; fi
  fi
  printf '%s\n' "$out"
}
