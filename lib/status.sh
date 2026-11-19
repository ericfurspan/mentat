# shellcheck shell=bash
# mentat status. Sourced by bin/mentat.

# Status prints one line of a pull request's review state, read from the comments
# the review commands post (lib/review.sh, and plugins/mentat-reviewers/lib/codex.sh and
# grok.sh), the owner's review and whether the description has the section for calls
# made without the maintainer. It posts, edits and pushes nothing. Only comments by the
# account gh is signed in as count: anyone who can comment could post the same text.
# tests/run fails when a comment heading these match changes where it is written.

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

# The local rounds in status_comments lines $1: completed Local Claude reviews. An
# incomplete local review is not a round (skills/review), and a Codex review never is.
# Sets the caller's rounds (the count), last (the head the last one reviewed) and
# last_fp (its spec fingerprint). Also read by mentat review.
status_rounds() {
  local kind sha res lfp
  rounds=0 last="" last_fp=""
  while read -r kind sha res lfp; do
    [ "$kind" = local ] && [ "$res" != incomplete ] || continue
    rounds=$((rounds + 1)) last=$sha last_fp=$lfp
  done <<<"$1"
}

# The review of the owner of repository $1 on its pull request $2, whose head is $3,
# the first that holds: "no single owner" (an organization owns the repository),
# "author" (the owner opened it), "approved on head" (the owner's latest submitted
# review is APPROVED on $3, as skills/review/ready-gate.md reads it), "requested" (the
# owner is among the requested reviewers), else "not requested". Each read is made only
# when the answer needs it; one that fails gives "unknown (<why>)" and stops nothing.
status_owner_review() {
  local owner=${1%%/*} kind state requested
  kind=$(gh api "repos/$1" --jq .owner.type) || kind=""
  case "$kind" in
    Organization) echo "no single owner"; return ;;
    User) ;;
    *) echo "unknown (could not read the repository owner)"; return ;;
  esac
  if ! state=$(gh pr view "$2" --json author,reviews | jq -r --arg o "$owner" --arg h "$3" '
    ([.reviews[] | select(.author.login == $o and .state != "PENDING")] | sort_by(.submittedAt) | last) as $r
    | if .author.login == $o then "author"
      elif $r != null and $r.state == "APPROVED" and $r.commit.oid == $h then "approved on head"
      else "" end'); then
    echo "unknown (could not read the reviews)"; return
  fi
  if [ -n "$state" ]; then echo "$state"; return; fi
  if ! requested=$(gh pr view "$2" --json reviewRequests | jq -r --arg o "$owner" 'any(.reviewRequests[]; .login == $o)'); then
    echo "unknown (could not read the requested reviewers)"; return
  fi
  if [ "$requested" = true ]; then echo requested; else echo "not requested"; fi
}

# Whether the description of pull request $1 has the "Calls made without the maintainer"
# section (skills/pr/SKILL.md): "present" when some line of it, CR stripped, is a Markdown
# ATX heading with that text at any level, wherever a template puts it, else "missing". A
# read that fails gives "unknown (<why>)" and stops nothing. No test pins that heading's
# text in the skill: a change to it there also changes it here.
status_calls_section() {
  local body cr=$'\r'
  if ! body=$(gh pr view "$1" --json body --jq .body); then
    echo "unknown (could not read the description)"; return
  fi
  body=${body//$cr/}
  # Drop fenced code blocks: a fence opens on a line of three or more backticks or tildes,
  # indented up to three spaces, and closes on a later line starting with at least as many
  # of the same character; an unclosed fence runs to the end.
  body=$(awk '
    function run(s, c,   n) { n = 0; while (substr(s, n + 1, 1) == c) n++; return n }
    {
      s = $0; i = 0
      while (i < 3 && substr(s, 1, 1) == " ") { s = substr(s, 2); i++ }
      c = substr(s, 1, 1)
      if (fc == "") {
        if ((c == "`" || c == "~") && run(s, c) >= 3) { fc = c; fn = run(s, c); next }
        print
      } else if (c == fc && run(s, c) >= fn) fc = ""
    }' <<<"$body")
  if grep -Eq '^#{1,6} +Calls made without the maintainer( +#+)? *$' <<<"$body"; then echo present; else echo missing; fi
}

status() {
  local pr="" request_file="" request fp repo me head lines ci kind sha res lfp
  local limit rounds last last_fp grok=none grok_stop_state=none codex_state=none reviewed out
  [ $# -ge 1 ] && pr=$1
  case "$#:${2:-}" in
    1:) ;;
    3:--request) request_file=$3 ;;
    *) pr="" ;;
  esac
  case "$pr" in '' | *[!0-9]*) die "usage: mentat status <pull request number> [--request <file>]" 64 ;; esac
  round_limit
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
  status_rounds "$lines"
  # Grok's start comment and its result or did-not-finish comment are one run, and the last one says where it stands.
  # An incomplete Grok result is posted without a did-not-finish comment (plugins/mentat-reviewers/lib/grok.sh).
  # The Grok stop review is read the same way, naming its head, and its spec fingerprint when done.
  while read -r kind sha res lfp; do
    case "$kind" in
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
  out="head ${head:0:7}, local rounds $rounds of $limit, head reviewed: $reviewed, grok: $grok, grok stop: $grok_stop_state, codex: $codex_state, ci: $ci"
  if [ -n "$request_file" ]; then
    if [ -z "$last" ]; then out="$out, spec: no review yet"
    elif [ "$last_fp" = "$fp" ]; then out="$out, spec: matches"
    else out="$out, spec: differs (last review ${last_fp:-none}, file $fp)"; fi
  fi
  out="$out, owner review: $(status_owner_review "$repo" "$pr" "$head")"
  out="$out, calls section: $(status_calls_section "$pr")"
  printf '%s\n' "$out"
}
