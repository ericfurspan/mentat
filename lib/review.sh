# shellcheck shell=bash
# The local review (`mentat review`) and its reviewer, a headless Claude: run_claude.
# Sourced by bin/mentat and by the reviewers module's entries, which share the time
# limit, the fetch and the checkout.

# The one time limit for every reviewer, Claude and each outside reviewer alike.
REVIEW_TIMEOUT_SECONDS="${MENTAT_REVIEW_TIMEOUT_SECONDS:-1800}"
# Unlike other settings, set but empty is not unset here: review_timeout refuses it.
[ "${MENTAT_REVIEW_TIMEOUT_SECONDS+set}" != set ] || [ -n "$MENTAT_REVIEW_TIMEOUT_SECONDS" ] || REVIEW_TIMEOUT_SECONDS=""
# Every command that runs a reviewer calls this first: anything but a whole number of 1
# or more (leading zeros allowed and dropped) is a usage error.
review_timeout() {
  case "$REVIEW_TIMEOUT_SECONDS" in '' | *[!0-9]*) die "MENTAT_REVIEW_TIMEOUT_SECONDS must be a whole number of 1 or more, not \"$REVIEW_TIMEOUT_SECONDS\"" 64 ;; esac
  [ $((10#$REVIEW_TIMEOUT_SECONDS)) -ge 1 ] || die "MENTAT_REVIEW_TIMEOUT_SECONDS must be a whole number of 1 or more, not \"$REVIEW_TIMEOUT_SECONDS\"" 64
  REVIEW_TIMEOUT_SECONDS=$((10#$REVIEW_TIMEOUT_SECONDS))
}
# The reviewer runs in a fresh context that never saw the build, on a configurable model.
# The review default, the one place in code its value is named; docs/settings.md lists it,
# and tests/settings.sh keeps the two in step.
MENTAT_REVIEW_MODEL_DEFAULT=opus
REVIEW_MODEL="${MENTAT_REVIEW_MODEL:-$MENTAT_REVIEW_MODEL_DEFAULT}"
# Set and not empty, a pull request's first local Claude round runs on this model instead.
FIRST_REVIEW_MODEL="${MENTAT_FIRST_REVIEW_MODEL:-}"
# Read tools only, and no shell: the runner hands the diff and the commit log over as files.
CLAUDE_REVIEW_TOOLS="Read,Grep,Glob"
# Effort is pinned; the record names it as the level asked for.
CLAUDE_REVIEW_EFFORT=high

# Sets the caller's limit to the local review rounds a pull request may use:
# MENTAT_REVIEW_ROUNDS (its default: docs/settings.md); a whole number of 1 or more, leading zeros
# allowed and dropped (08 is 8); anything else is a usage error. Read only by
# the Claude review (bin/mentat) and mentat status, not when this file is sourced, so
# the module's entries never read it.
round_limit() {
  local value=${MENTAT_REVIEW_ROUNDS:-5}
  case "$value" in *[!0-9]*) die "MENTAT_REVIEW_ROUNDS must be a whole number of 1 or more, not \"$value\"" 64 ;; esac
  limit=$((10#$value))
  [ "$limit" -ge 1 ] || die "MENTAT_REVIEW_ROUNDS must be a whole number of 1 or more, not \"$value\"" 64
}

# Runs Claude in directory $1 on prompt file $2 and writes its reply to $3. On any
# failure it calls $4 with the reason, which exits. $5 is the folder holding the
# diff and the log, outside $1, which Claude may also read. $6 is the model and $7
# what a failure says about it, such as the setting that chose it. With $8, a run in
# which no model ran at all, by Claude's own report (an empty modelUsage, as for a
# model the account cannot use), is said, with $8, and returns 1 instead; output
# with no such report, and the time limit, still fail. Sets the caller's
# claude_models to the models that ran, from Claude's own report.
# --safe-mode loads no CLAUDE.md, hooks, skills or installed plugins, but still lists
# a plugin folder named in CLAUDE_CODE_PLUGIN_DIRS (Claude Code 2.1.322), so claude
# runs without that variable. --restricted ignores the settings files, the reviewed
# tree's included, and keeps the file tools inside $1 and $5, so a read anywhere else
# is denied and the run fails below; a read through a symbolic link out of $1 is
# denied too (Claude Code 2.1.322). A denied tool call, an error or output that is
# not Claude's JSON result is not a review.
run_claude() {
  local dir="$1" prompt="$2" out="$3" fail="$4" data="$5" model="$6" hint="$7" retry="${8:-}" json log rc secs=0 pid n why
  local args=(-p --safe-mode --restricted --add-dir "$data" --model "$model" --effort "$CLAUDE_REVIEW_EFFORT" --permission-mode dontAsk
    --tools "$CLAUDE_REVIEW_TOOLS" --allowedTools "$CLAUDE_REVIEW_TOOLS" --output-format json)
  json="${out%/*}/claude.json" log="${out%/*}/claude.log"
  (cd "$dir" && unset CLAUDE_CODE_PLUGIN_DIRS && exec claude "${args[@]}" <"$prompt") >"$json" 2>"$log" &
  pid=$! review_child=$!
  # $SECONDS counts whole seconds, so a limit stops Claude up to a second late, never early.
  secs=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - secs)) -gt "$REVIEW_TIMEOUT_SECONDS" ]; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null
      "$fail" "Claude did not finish within $REVIEW_TIMEOUT_SECONDS seconds"
    fi
    sleep 0.1
  done
  wait "$pid"
  rc=$?
  # shellcheck disable=SC2034 # read by review_stop in lib/shared.sh
  review_child=""
  # Claude's own error text, first line only, or else how its run ended, when its output says.
  # A run that did not end in success, such as error_max_turns, has no result text.
  why=$(jq -r 'if type != "object" then empty
    elif (.result | type) == "string" then .result | split("\n")[0] | .[0:200]
    elif (.subtype | type) == "string" then "the run ended with " + .subtype else empty end' "$json" 2>/dev/null)
  if [ -n "$retry" ] && jq -e 'type == "object" and (.modelUsage | type) == "object" and (.modelUsage | length) == 0' "$json" >/dev/null 2>&1; then
    printf 'mentat: Claude reports that no model ran%s; %s; %s\n' "${why:+: $why}" "$hint" "$retry" >&2
    return 1
  fi
  # A second argument to "$fail" is the same reason without Claude's own text, for the line
  # that tells the maintainer now (not_reviewed, lib/shared.sh).
  [ "$rc" -eq 0 ] || "$fail" "claude exited with status $rc${why:+: $why}; $hint" "claude exited with status $rc; $hint"
  [ -s "$json" ] || "$fail" "Claude returned no output"
  n=$(jq -er 'if type == "object" then .subtype | strings else empty end' "$json" 2>/dev/null) ||
    "$fail" "Claude's output is not the JSON result it gives with --output-format json"
  [ "$n" = success ] || "$fail" "Claude's run ended with $n, not success; $hint" "Claude's run did not end in success; $hint"
  jq -e '(.result | type) == "string" and (.permission_denials | type) == "array" and (.modelUsage | type) == "object"' "$json" >/dev/null 2>&1 ||
    "$fail" "Claude's output is not the JSON result it gives with --output-format json"
  [ "$(jq -r '.is_error // false' "$json")" = false ] || "$fail" "Claude reported an error${why:+: $why}; $hint" "Claude reported an error; $hint"
  n=$(jq -r '.permission_denials | length' "$json")
  [ "$n" -eq 0 ] || "$fail" "Claude was denied $n tool call(s) ($(jq -r '[.permission_denials[].tool_name | strings] | unique | join(", ")' "$json")), so the review may not have read what it needed" \
    "Claude was denied $n tool call(s), so the review may not have read what it needed"
  claude_models=$(jq -r '.modelUsage | keys | join(", ")' "$json")
  [ -n "$claude_models" ] || "$fail" "Claude's output does not say which model ran"
  jq -r .result "$json" >"$out" || "$fail" "could not read Claude's reply"
  [ -s "$out" ] || "$fail" "Claude returned no reply"
}

# The reviewer's own parts of the local review, as functions named for reviewer r:
# review_name_r sets the caller's name, which the heading shows; review_prep_r writes
# the prompt's opening (where to look) to stdout and any files the reviewer reads;
# review_run_r runs it; review_meta_r prints the record's lines on the tool and the
# model; review_check_r, where defined, runs once the repository is known; review_note_r, where
# defined, prints what ends the reason when the reply has no final result line. Claude's are here; another reviewer's come with the module that runs it.
review_name_claude() { name=Claude; }
review_prep_claude() {
  git -C "$top" diff --no-ext-diff --no-textconv --no-color "$mb" "$head" >"$tmp/data/diff" || not_reviewed "could not diff $mb..$head"
  git -C "$top" log --no-color --format=medium "$mb..$head" >"$tmp/data/log" || not_reviewed "could not read the commits $mb..$head"
  printf 'Review pull request #%s. The working directory is a checkout of its head, commit %s, and you have no shell. ' "$pr" "$head"
  printf 'Review the change from %s to %s: the diff is in %s and its commits are in %s; read them and the files around the change with your file tools. Do not modify files. ' "$mb" "$head" "$tmp/data/diff" "$tmp/data/log"
  printf 'Your file tools can read only this checkout and the folder holding the diff and the commit log, and a read anywhere else is refused and fails the whole review, so attempt none; state what you cannot check from those two places as a limitation of a complete review, not as a reason for INCOMPLETE, which stays for a material file in this checkout, or the diff, that cannot be read, and not as a guessed finding.\n\n'
}
# The round limit, which review_local runs once the repository is known, before
# anything is fetched or run: sets the caller's rounds to the pull request's local
# rounds, counted as mentat status counts them (lib/status.sh), and refuses (exit 7,
# nothing posted) when they reach limit, which bin/mentat set with round_limit.
review_check_claude() {
  # shellcheck disable=SC2034 # status_rounds sets last and last_fp too; local keeps them here
  local me lines last last_fp
  if ! me=$(gh api user --jq .login) || [ -z "$me" ] || ! lines=$(status_comments "$repo" "$pr" "$me"); then
    not_reviewed "could not read this account's comments on #$pr, which the round limit (MENTAT_REVIEW_ROUNDS) needs"
  fi
  status_rounds "$lines"
  [ "$rounds" -lt "$limit" ] || die "#$pr has used its $rounds of $limit local review rounds; MENTAT_REVIEW_ROUNDS sets the limit" 7
}
# Sets the caller's claude_model, the model to review on, and claude_key, the setting
# that chose it: FIRST_REVIEW_MODEL when it is set and the pull request has no local
# round yet (rounds, from review_check_claude), else REVIEW_MODEL. A run that posted
# no round leaves the next one the first.
review_model_claude() {
  claude_model=$REVIEW_MODEL claude_key=MENTAT_REVIEW_MODEL
  [ -n "$FIRST_REVIEW_MODEL" ] && [ "$rounds" -eq 0 ] || return 0
  claude_model=$FIRST_REVIEW_MODEL claude_key=MENTAT_FIRST_REVIEW_MODEL
}
# A first round in which no model ran at all, by Claude's own report, runs once more on the
# review default, MENTAT_REVIEW_MODEL_DEFAULT, whatever MENTAT_REVIEW_MODEL names, unless the
# default is the model it asked for. claude_model and claude_key keep the model asked for, so
# the record names it beside the model that ran (review_meta_claude). A first round that is
# not run again says why.
review_run_claude() {
  local hint fallback first_note
  review_model_claude
  hint="the review model is set with $claude_key (now $claude_model)"
  if [ "$claude_key" != MENTAT_FIRST_REVIEW_MODEL ]; then
    run_claude "$tmp/tree" "$tmp/prompt" "$out" review_tool_failed "$tmp/data" "$claude_model" "$hint"
    return
  fi
  fallback="the review default ($MENTAT_REVIEW_MODEL_DEFAULT)"
  if [ "$claude_model" = "$MENTAT_REVIEW_MODEL_DEFAULT" ]; then
    first_note="not run again on $fallback, which is the same model"
    run_claude "$tmp/tree" "$tmp/prompt" "$out" first_round_not_reviewed "$tmp/data" "$claude_model" "$hint"
    return
  fi
  first_note="a first round runs again, on $fallback, only when Claude reports that no model ran"
  run_claude "$tmp/tree" "$tmp/prompt" "$out" first_round_not_reviewed "$tmp/data" "$claude_model" "$hint" \
    "reviewing once on $fallback" && return 0
  run_claude "$tmp/tree" "$tmp/prompt" "$out" review_tool_failed "$tmp/data" "$MENTAT_REVIEW_MODEL_DEFAULT" \
    "this run was on $fallback, as no model ran on $claude_key (now $claude_model)"
}
# A first round's failure, with review_run_claude's note on why it is not run again. A
# first run that is run again (no model ran) returns before this, so only the run that
# ends the round is recorded.
first_round_not_reviewed() { review_tool_failed "$1; $first_note" "${2:-$1}; $first_note"; }
# A failure of the reviewer tool itself in review_local (reviewer, from its caller): recorded
# as one of the reviewer's failures in a row (lib/shared.sh), then not reviewed. $2, when
# given, is the reason without the reviewer's own text, for the line that tells the
# maintainer now.
review_tool_failed() {
  reviewer_failed "$reviewer" "$name"
  not_reviewed "$1" "${2:-$1}"
}
review_meta_claude() {
  # The models that ran, from Claude's report; the one asked for when none of them is it (a
  # fallback); and the first-round setting when it chose the model.
  local asked=$claude_model first=""
  if [ "$claude_key" = MENTAT_FIRST_REVIEW_MODEL ]; then asked="$claude_key=$claude_model" first="first round, "; fi
  printf -- '- Round limit: %s\n' "$limit"
  printf -- '- Claude Code: %s\n- Model: %s' "$(claude --version 2>/dev/null | head -n 1 | sed -n 's/^\([0-9][0-9.]*\).*/\1/p')" "$claude_models"
  case "$claude_models" in
    *"$claude_model"*) [ -z "$first" ] || printf ' (%s%s)' "$first" "$asked" ;;
    *) printf ' (%sasked for %s)' "$first" "$asked" ;;
  esac
  printf '\n- Effort asked for: %s\n' "$CLAUDE_REVIEW_EFFORT"
}

# Fetches the pull request's head and its base into refs of this run's own, named with the
# process id, not through git's one per-checkout record of the last fetch, nor the shared
# origin/<base> tracking ref: the review skill may run more than one review of a pull
# request at once in this checkout, and with those shared the fetches of one could
# overwrite or lock out the other (--refmap= keeps the configured mapping from also
# updating origin/<base>). The refs go once the merge base is known (the commits stay),
# and at exit if the run stops before that. Reads the caller's top, pr, head and base and
# sets its mb; exits 3, saying to run $1 again, when the head moved.
review_fetch() { # $1 the command to run again
  local fetched headref="refs/mentat/review-$pr-$$/head" baseref="refs/mentat/review-$pr-$$/base"
  # shellcheck disable=SC2064 # expand now, so the paths are fixed when the trap is set
  trap "git -C $(printf %q "$top") update-ref -d $(printf %q "$headref") >/dev/null 2>&1; git -C $(printf %q "$top") update-ref -d $(printf %q "$baseref") >/dev/null 2>&1" EXIT
  git -C "$top" fetch -q --no-write-fetch-head --refmap= origin "+pull/$pr/head:$headref" "+refs/heads/$base:$baseref" || not_reviewed "could not fetch pull request #$pr or $base"
  fetched=$(git -C "$top" rev-parse --verify "$headref") || not_reviewed "could not read the fetched head"
  [ "$fetched" = "$head" ] || die "the head moved from $head; run $1 again" 3
  mb=$(git -C "$top" merge-base "$head" "$baseref") || not_reviewed "could not find where #$pr branches from $base"
  git -C "$top" update-ref -d "$headref" || not_reviewed "could not remove the ref fetched for #$pr"
  git -C "$top" update-ref -d "$baseref" || not_reviewed "could not remove the ref fetched for $base"
}
# Checks out commit $2 (the caller's head when not given) of the repository at the
# caller's top as a detached worktree at $1, with core.hooksPath=/dev/null, so a pull
# request's own hooks never run on the reviewer's machine.
review_checkout() { # $1 folder, $2 commit
  git -C "$top" -c core.hooksPath=/dev/null worktree add -q --detach "$1" "${2:-$head}" || not_reviewed "could not check out ${2:-$head}"
}

# A local review reads the pull request's head as GitHub has it, never this
# checkout's working tree: it fetches that commit, reviews it in a temporary
# worktree, then waits for CI on that commit, and posts the result only once CI
# passed there and the head has not moved since. $1 is the reviewer, claude, whose
# functions are above.
review_local() {
  local reviewer="$1" pr="${2:-}" name repo info head base title body top tmp mb now issues request request_fp claude_models="" claude_model="" claude_key="" rounds=""
  "review_name_$reviewer"
  case "$pr" in '' | *[!0-9]*) die "$REVIEW_USAGE" 64 ;; esac
  sweep_leftovers
  review_traps
  read_request "$pr"
  local tool
  for tool in git "$reviewer"; do
    command -v "$tool" >/dev/null 2>&1 || not_reviewed "$tool is not installed"
  done
  top=$(git rev-parse --show-toplevel) || not_reviewed "not inside a git repository"
  info=$(gh pr view "$pr" --json headRefOid,baseRefName,title,body,closingIssuesReferences) || not_reviewed "could not read pull request #$pr"
  head=$(jq -r '.headRefOid // empty' <<<"$info")
  base=$(jq -r '.baseRefName // empty' <<<"$info")
  { [ -n "$head" ] && [ -n "$base" ]; } || not_reviewed "could not read pull request #$pr"
  if ! repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || [ -z "$repo" ]; then
    not_reviewed "could not read the repository with gh"
  fi
  if declare -F "review_check_$reviewer" >/dev/null; then "review_check_$reviewer"; fi
  title=$(jq -r '.title // ""' <<<"$info")
  body=$(jq -r '.body // ""' <<<"$info")
  read_issues "$pr" "$info"
  review_fetch "mentat review"
  tmp=$(mktemp -d) || not_reviewed "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand now, so the paths are fixed when the trap is set
  trap "git -C $(printf %q "$top") worktree remove --force $(printf %q "$tmp/tree") >/dev/null 2>&1; rm -rf $(printf %q "$tmp")" EXIT
  review_checkout "$tmp/tree"
  mkdir "$tmp/data" || not_reviewed "could not create a temporary directory"

  {
    "review_prep_$reviewer"
    review_criteria ""
    review_requirements "$issues" "$title" "$body" "$request"
    review_result_line
  } >"$tmp/prompt" || not_reviewed "could not write the prompt"

  local out="$tmp/review.md" result url held note=""
  "review_run_$reviewer"
  if declare -F "review_note_$reviewer" >/dev/null; then note=$("review_note_$reviewer"); fi
  result_line "$(last_line "$out")" || review_tool_failed "$name's reply has no final REVIEW RESULT line$note"
  # A checked reply, as the reviewer returned it, ends the reviewer's failures in a row,
  # whether or not it is posted; a failure from here on is not the reviewer's.
  reviewer_record "$reviewer" ok
  localize_review_paths "$out" "$repo" "$head" "$tmp/tree" "$tmp/data" || not_reviewed "could not rewrite the paths in $name's reply"
  result=$(last_line "$out")
  result_line "$result" || not_reviewed "$name's reply has no final REVIEW RESULT line"
  # The review ran without waiting for CI; it is posted only once CI passes on the same head.
  wait_for_ci "$repo" "$head" "$out" "$pr" "mentat review"
  now=$(gh pr view "$pr" --json headRefOid --jq .headRefOid) || not_reviewed "could not read pull request #$pr"
  [ "$now" = "$head" ] || die "the head moved from $head; run mentat review again" 3
  {
    printf '## Local %s review of %s: %s, spec fingerprint %s\n\n' "$name" "$head" "$(result_word "$result")" "$request_fp"
    printf '<details><summary>Full review</summary>\n\n'
    printf -- '- Change reviewed: %s..%s\n' "$mb" "$head"
    printf -- '- Agreed request fingerprint: %s\n' "$request_fp"
    "review_meta_$reviewer"
    printf -- '- Time: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '\n---\n\n'
    cat "$out"
    printf '\n</details>\n'
  } >"$tmp/comment" || not_reviewed "could not write the comment"
  if held=$(held_comment "$(cat "$tmp/comment")" "$repo"); then not_reviewed "$held"; fi
  url=$(gh pr comment "$pr" --body-file "$tmp/comment") || not_reviewed "could not post the review on #$pr"
  # An incomplete review is posted, so its reason is on the pull request, and is not a review.
  case "$result" in "REVIEW RESULT: INCOMPLETE - "*) not_reviewed "$name says the review is incomplete: ${result#"REVIEW RESULT: INCOMPLETE - "}" ;; esac
  if [ "$result" = "REVIEW RESULT: NO FINDINGS" ]; then
    printf 'The local %s review found nothing on %s: %s\n' "$name" "$head" "$url"
    exit 0
  fi
  printf 'The local %s review posted findings on %s: %s\n' "$name" "$head" "$url"
  exit 2
}
