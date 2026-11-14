# shellcheck shell=bash
# mentat status. Sourced by bin/mentat.

# Status prints one line of a pull request's review state, read from the comments
# the review commands post (lib/review.sh, and plugins/mentat-reviewers/lib/codex.sh and
# grok.sh). It posts, edits and pushes nothing. Only comments by the account gh is
# signed in as count: anyone who can comment could post the same text.
# tests/run fails when a heading these match changes where it is written.

# One line per review comment by $3 on pull request $2 of repository $1, oldest
# first: "local <sha> <no-findings|findings|incomplete> <fingerprint>" for a Local
# Claude review, "codex <sha> <result> <fingerprint>" for a Local Codex review,
# "grok-done <sha> <result> <fingerprint>", "grok-started <sha>", "grok-unfinished <sha>",
# or the same three for the Grok stop review as "grok-stop-done", "grok-stop-started"
# and "grok-stop-unfinished".
status_comments() { # $1 repo, $2 pull request, $3 this account's login
  gh api --paginate "repos/$1/issues/$2/comments" | jq -rs --arg me "$3" '
    def review($who): capture("^## Local " + $who + " review of (?<sha>[0-9a-f]{40}): (?<res>no findings|findings|incomplete), spec fingerprint (?<fp>[^ ]+)$");
    .[][] | select(.user.login == $me) | .body as $b | ($b | split("\n")[0] | sub("\r$"; "")) as $h |
    if ($h | test("^## Local Claude review of ")) then
      $h | review("Claude") | "local \(.sha) \(.res | gsub(" "; "-")) \(.fp)"
    elif ($h | test("^## Local Codex review of ")) then
      $h | review("Codex") | "codex \(.sha) \(.res | gsub(" "; "-")) \(.fp)"
    elif ($h | test("^## Local Grok review of ")) then
      $h | review("Grok") | "grok-done \(.sha) \(.res | gsub(" "; "-")) \(.fp)"
    elif ($h | test("^Grok review started on [0-9a-f]{40}$")) then
      "grok-started \($h | ltrimstr("Grok review started on "))"
    elif ($h | test("^Grok review did not finish on [0-9a-f]{40}: ")) then
      "grok-unfinished \($h | capture("^Grok review did not finish on (?<sha>[0-9a-f]{40}): ").sha)"
    elif ($h | test("^## Local Grok stop review of ")) then
      $h | review("Grok stop") | "grok-stop-done \(.sha) \(.res | gsub(" "; "-")) \(.fp)"
    elif ($h | test("^Grok stop review started on [0-9a-f]{40}$")) then
      "grok-stop-started \($h | ltrimstr("Grok stop review started on "))"
    elif ($h | test("^Grok stop review did not finish on [0-9a-f]{40}: ")) then
      "grok-stop-unfinished \($h | capture("^Grok stop review did not finish on (?<sha>[0-9a-f]{40}): ").sha)"
    else empty end'
}

status() {
  local pr="" request_file="" request fp repo me head lines ci kind sha res lfp
  local rounds=0 last="" last_fp="" grok=none grok_stop_state=none codex_state=none reviewed out
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
  # Completed Local Claude reviews are the rounds, and the last one names the head
  # reviewed and its spec fingerprint. An incomplete local review is not
  # a round (skills/review), and a Codex review never is. Grok's start comment
  # and its result or did-not-finish comment are one run, and the last one says where it stands.
  # An incomplete Grok result is posted without a did-not-finish comment (plugins/mentat-reviewers/lib/grok.sh).
  # The Grok stop review is read the same way, naming its head, and its spec fingerprint when done.
  while read -r kind sha res lfp; do
    case "$kind" in
      local) [ "$res" = incomplete ] && continue; rounds=$((rounds + 1)); last=$sha last_fp=$lfp ;;
      grok-started) grok=running ;;
      grok-done) if [ "$res" = incomplete ]; then grok="did not finish"; else grok='done'; fi ;;
      grok-unfinished) grok="did not finish" ;;
      grok-stop-started) grok_stop_state="running on ${sha:0:7}" ;;
      grok-stop-done)
        if [ "$res" = incomplete ]; then grok_stop_state="did not finish on ${sha:0:7}"
        else grok_stop_state="done on ${sha:0:7} (${res//-/ }, spec fingerprint $lfp)"; fi ;;
      grok-stop-unfinished) grok_stop_state="did not finish on ${sha:0:7}" ;;
    esac
  done <<<"$lines"
  # Codex's state on the last head Claude reviewed: the latest Codex comment on that head,
  # read once that head is known, so the order of the two reviews' comments does not matter.
  if [ -n "$last" ]; then
    while read -r kind sha res lfp; do
      [ "$kind" = codex ] && [ "$sha" = "$last" ] || continue
      if [ "$res" = incomplete ]; then codex_state="did not finish on ${sha:0:7}"; continue; fi
      codex_state="done on ${sha:0:7} (${res//-/ }, spec fingerprint $lfp"
      if [ -n "$request_file" ]; then
        if [ "$lfp" = "$fp" ]; then codex_state="$codex_state, spec matches"; else codex_state="$codex_state, spec differs"; fi
      fi
      codex_state="$codex_state)"
    done <<<"$lines"
  fi
  if [ -z "$last" ]; then reviewed="no (no review yet)"
  else
    if [ "$head" = "$last" ]; then reviewed=yes; else reviewed="no (last reviewed ${last:0:7})"; fi
  fi
  lines=$(ci_lines "$repo" "$head") || die "could not read CI on $head"
  if [ -z "$lines" ]; then ci=none
  elif grep -q '^fail ' <<<"$lines"; then ci=failed
  elif grep -q '^pending ' <<<"$lines"; then ci=running
  else ci=passed; fi
  out="head ${head:0:7}, local rounds $rounds, head reviewed: $reviewed, grok: $grok, grok stop: $grok_stop_state, codex: $codex_state, ci: $ci"
  if [ -n "$request_file" ]; then
    if [ -z "$last" ]; then out="$out, spec: no review yet"
    elif [ "$last_fp" = "$fp" ]; then out="$out, spec: matches"
    else out="$out, spec: differs (last review ${last_fp:-none}, file $fp)"; fi
  fi
  printf '%s\n' "$out"
}
