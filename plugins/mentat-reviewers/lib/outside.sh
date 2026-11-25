# shellcheck shell=bash
# shellcheck disable=SC2154 # pr, request_fp, reviewers_list and the run's variables are set by the functions called
# mentat review --outside <PR>: every listed outside reviewer reviews the pull request's
# head at once, in parallel, and one comment records the run. Sourced by this module's
# bin/mentat-review-outside. Usage and exit codes are bin/mentat's.

OUTSIDE_USAGE="usage: mentat review --outside [--request <file>] [--require-ci] <pull request number>"

# The prompt every review gets after where to look: the criteria, the requirements and
# the result line. $1 is review_criteria's (" and the diff" when the prompt carries the diff).
review_body() {
  review_criteria "$1"
  review_requirements "$issues" "$title" "$body" "$request"
  review_result_line
}

# One reviewer's run, in its own subshell (adapters_run): the adapter's review, then the
# reply checked for its final REVIEW RESULT line, which ends the reviewer's failures in a
# row, then its paths rewritten. An INCOMPLETE reply is a checked reply that did not
# finish the review.
outside_runner() {
  local final
  adapter_go review
  if ! result_line "$(last_line "$reply")"; then
    # Kept as <name>.partial: printed and read for findings, and posted in its own block
    # only when it marks one, since the reply did not end as a review does.
    localize_review_paths "$reply" "$repo" "$head" "$tree" "$data" ${adapter_roots[@]+"${adapter_roots[@]}"} &&
      cp "$reply" "$res/$name.partial"
    adapter_fail "$(adapter_noted "$adapter_display's reply has no final REVIEW RESULT line")"
  fi
  reviewer_record "$name" ok
  localize_review_paths "$reply" "$repo" "$head" "$tree" "$data" ${adapter_roots[@]+"${adapter_roots[@]}"} ||
    adapter_fail "could not rewrite the paths in $adapter_display's reply" "" none
  final=$(last_line "$reply")
  result_line "$final" || adapter_fail "$(adapter_noted "$adapter_display's reply has no final REVIEW RESULT line")" "" none
  cp "$reply" "$res/$name.reply" || adapter_fail "could not keep the reply" "" none
  if declare -F adapter_meta >/dev/null; then adapter_meta >"$res/$name.meta" 2>/dev/null; fi
  case "$final" in "REVIEW RESULT: INCOMPLETE - "*) adapter_fail "$adapter_display says the review is incomplete" "" none ;; esac
  printf '%s\n' "$final" >"$res/$name.final"
}

# The result word of reviewer $1, as the comment and the summary give it: findings, no
# findings, did not finish (<why>) or skipped (<why>).
outside_result() {
  if [ -s "$res/$1.skipped" ]; then printf 'skipped (%s)' "$(cat "$res/$1.skipped")"
  elif [ -s "$res/$1.final" ]; then result_word "$(cat "$res/$1.final")"
  else printf 'did not finish (%s)' "$(adapter_why_text "$1")"; fi
}

outside_review() {
  local pr repo info head base title body top tmp mb issues request request_fp me lines n result url held now kind sha res_word clean="" any=no
  # shellcheck disable=SC2034 # run_pids is set by adapters_run and read by adapters_cancel
  local tree data res="" run_pids="" names f finished=0 unfinished=0
  review_args "" "$@"
  case "$pr" in '' | *[!0-9]*) die "$OUTSIDE_USAGE" 64 ;; esac
  review_timeout
  reviewers_gate "not run"
  names=$reviewers_list
  sweep_leftovers
  review_traps
  read_request "$pr"
  for n in git gh jq; do command -v "$n" >/dev/null 2>&1 || not_reviewed "$n is not installed"; done
  top=$(git rev-parse --show-toplevel) || not_reviewed "not inside a git repository"
  info=$(gh pr view "$pr" --json headRefOid,baseRefName,title,body,closingIssuesReferences) || not_reviewed "could not read pull request #$pr"
  head=$(jq -r '.headRefOid // empty' <<<"$info")
  base=$(jq -r '.baseRefName // empty' <<<"$info")
  { [ -n "$head" ] && [ -n "$base" ]; } || not_reviewed "could not read pull request #$pr"
  if ! repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || [ -z "$repo" ]; then
    not_reviewed "could not read the repository with gh"
  fi
  # Outside reviewers run only on a head Claude's latest review found clean.
  if ! me=$(gh api user --jq .login) || [ -z "$me" ] || ! lines=$(status_comments "$repo" "$pr" "$me"); then
    not_reviewed "could not read this account's comments on #$pr"
  fi
  while read -r kind sha res_word _; do
    [ "$kind" = local ] && [ "$sha" = "$head" ] && clean=$res_word
  done <<<"$lines"
  case "$clean" in
    no-findings) ;;
    findings) die "not run: Claude's latest review of $head found findings; outside reviewers run only on a head Claude found nothing on" 8 ;;
    incomplete) die "not run: Claude's latest review of $head is incomplete; outside reviewers run only on a head Claude found nothing on" 8 ;;
    *) die "not run: Claude has posted no review of $head; outside reviewers run only on a head Claude found nothing on" 8 ;;
  esac
  title=$(jq -r '.title // ""' <<<"$info")
  body=$(jq -r '.body // ""' <<<"$info")
  read_issues "$pr" "$info"
  review_fetch "mentat review --outside"
  tmp=$(mktemp -d) || not_reviewed "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand now, so the paths are fixed when the trap is set
  trap "git -C $(printf %q "$top") worktree remove --force $(printf %q "$tmp/tree") >/dev/null 2>&1; rm -rf $(printf %q "$tmp")" EXIT
  tree="$tmp/tree" data="$tmp/data" res="$tmp/res"
  review_checkout "$tree"
  mkdir "$data" "$res" || not_reviewed "could not create a temporary directory"
  git -C "$top" diff --no-ext-diff --no-textconv --no-color "$mb" "$head" >"$data/diff" || not_reviewed "could not diff $mb..$head"
  git -C "$top" log --no-color --format=medium "$mb..$head" >"$data/log" || not_reviewed "could not read the commits $mb..$head"
  trap adapters_cancel INT TERM HUP

  # shellcheck disable=SC2086 # names is a list of plain names
  adapters_run outside_runner $names
  trap 'review_stop 130' INT
  trap 'review_stop 143' TERM
  trap 'review_stop 129' HUP

  # Each reply is printed before the wait for CI, so findings are on hand even when
  # nothing is posted; then one summary line per reviewer.
  for n in $names; do
    for f in "$res/$n.reply" "$res/$n.partial"; do
      if [ -s "$f" ]; then printf '## %s\n\n' "$n"; cat "$f"; printf '\n'; fi
    done
    adapter_local_lines "$n"
  done
  # A reviewer that did not finish but whose kept reply, or reply with no result line,
  # marks a finding, (blocking) or (non-blocking) as the review brief asks, counts toward
  # the findings exit: those findings still need sorting.
  for n in $names; do
    result=$(outside_result "$n")
    printf '%s: %s\n' "$n" "$result"
    [ "$result" != findings ] || any=yes
    case "$result" in findings | "no findings") finished=$((finished + 1)) ;; esac
    case "$result" in "did not finish"*)
      unfinished=$((unfinished + 1))
      for f in "$res/$n.reply" "$res/$n.partial"; do
        [ -s "$f" ] && grep -q -E '\((non-)?blocking\)' "$f" && any=yes
      done ;;
    esac
  done
  wait_for_ci "$repo" "$head" "" "$pr" "mentat review --outside"
  now=$(gh pr view "$pr" --json headRefOid --jq .headRefOid) || not_reviewed "could not read pull request #$pr"
  [ "$now" = "$head" ] || die "the head moved from $head; nothing was posted; run mentat review --outside again on the next head Claude finds nothing on" 3
  {
    printf '## Outside review of %s: spec fingerprint %s, reviewers %s\n\n' "$head" "$request_fp" "$(printf '%s' "$names" | sed 's/ /, /g')"
    for n in $names; do printf -- '- %s: %s\n' "$n" "$(outside_result "$n")"; done
    printf -- '\n- Change reviewed: %s..%s\n- Time limit: %s seconds\n- Time: %s\n' "$mb" "$head" "$REVIEW_TIMEOUT_SECONDS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for n in $names; do
      if [ -s "$res/$n.reply" ]; then
        printf '\n<details><summary>%s</summary>\n\n' "$(adapter_shown "$n")"
        cat "$res/$n.meta" 2>/dev/null
        printf -- '\n---\n\n'
        cat "$res/$n.reply"
        printf '\n</details>\n'
      elif [ -s "$res/$n.partial" ] && grep -q -E '\((non-)?blocking\)' "$res/$n.partial"; then
        # Posted so a session that resumes after the post can still sort its findings;
        # its row above still says it did not finish.
        printf '\n<details><summary>%s: the reply has no final REVIEW RESULT line; its findings still need sorting</summary>\n\n' "$(adapter_shown "$n")"
        cat "$res/$n.partial"
        printf '\n</details>\n'
      fi
    done
  } >"$tmp/comment" || not_reviewed "could not write the comment"
  if held=$(held_comment "$(cat "$tmp/comment")" "$repo"); then die "not posted: $held" 9; fi
  url=$(gh pr comment "$pr" --body-file "$tmp/comment") || not_reviewed "could not post the outside review on #$pr"
  if [ "$any" = yes ]; then
    printf 'The outside review posted findings on %s: %s\n' "$head" "$url"
    exit 2
  fi
  # "Found nothing" only when every reviewer that ran finished clean; a skipped name never ran.
  if [ "$finished" = 0 ]; then
    printf 'The outside review posted on %s, but no reviewer finished: %s\n' "$head" "$url"
  elif [ "$unfinished" != 0 ]; then
    printf 'The outside review found nothing on %s, but not every reviewer finished: %s\n' "$head" "$url"
  else
    printf 'The outside review found nothing on %s: %s\n' "$head" "$url"
  fi
  exit 0
}
