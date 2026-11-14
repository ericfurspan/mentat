# shellcheck shell=bash
# The local review (`mentat review`, `--local` and `--codex`) and its default
# reviewer, a headless Claude: run_claude. Sourced by bin/mentat.

REVIEW_TIMEOUT_SECONDS="${MENTAT_REVIEW_TIMEOUT_SECONDS:-1200}"
# The reviewer runs in a fresh context that never saw the build, on a configurable model.
MENTAT_REVIEW_MODEL_DEFAULT=opus
REVIEW_MODEL="${MENTAT_REVIEW_MODEL:-$MENTAT_REVIEW_MODEL_DEFAULT}"
# Read tools only, and no shell: the runner hands the diff and the commit log over as files.
CLAUDE_REVIEW_TOOLS="Read,Grep,Glob"

# Runs Claude in directory $1 on prompt file $2 and writes its reply to $3. On any
# failure it calls $4 with the reason, which exits. $5 is the folder holding the
# diff and the log, outside $1, which Claude may also read. Sets the caller's
# claude_models to the models that ran, from Claude's own report.
# --safe-mode loads no CLAUDE.md, hooks, plugins or skills; --restricted ignores
# the settings files, the reviewed tree's included, and keeps the file tools inside
# $1 and $5, so a read anywhere else is denied and the run fails below. A denied
# tool call, an error or output that is not Claude's JSON result is not a review.
run_claude() {
  local dir="$1" prompt="$2" out="$3" fail="$4" data="$5" json log rc secs=0 pid n why
  local hint="the review model is set with MENTAT_REVIEW_MODEL (now $REVIEW_MODEL)"
  local args=(-p --safe-mode --restricted --add-dir "$data" --model "$REVIEW_MODEL" --permission-mode dontAsk
    --tools "$CLAUDE_REVIEW_TOOLS" --allowedTools "$CLAUDE_REVIEW_TOOLS" --output-format json)
  json="${out%/*}/claude.json" log="${out%/*}/claude.log"
  (cd "$dir" && exec claude "${args[@]}" <"$prompt") >"$json" 2>"$log" &
  pid=$! review_child=$!
  # $SECONDS counts whole seconds, so a limit stops Claude up to a second late, never early.
  secs=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$REVIEW_TIMEOUT_SECONDS" -eq 0 ] || [ $((SECONDS - secs)) -gt "$REVIEW_TIMEOUT_SECONDS" ]; then
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
  [ "$rc" -eq 0 ] || "$fail" "claude exited with status $rc${why:+: $why}; $hint"
  [ -s "$json" ] || "$fail" "Claude returned no output"
  n=$(jq -er 'if type == "object" then .subtype | strings else empty end' "$json" 2>/dev/null) ||
    "$fail" "Claude's output is not the JSON result it gives with --output-format json"
  [ "$n" = success ] || "$fail" "Claude's run ended with $n, not success; $hint"
  jq -e '(.result | type) == "string" and (.permission_denials | type) == "array" and (.modelUsage | type) == "object"' "$json" >/dev/null 2>&1 ||
    "$fail" "Claude's output is not the JSON result it gives with --output-format json"
  [ "$(jq -r '.is_error // false' "$json")" = false ] || "$fail" "Claude reported an error${why:+: $why}; $hint"
  n=$(jq -r '.permission_denials | length' "$json")
  [ "$n" -eq 0 ] || "$fail" "Claude was denied $n tool call(s) ($(jq -r '[.permission_denials[].tool_name | strings] | unique | join(", ")' "$json")), so the review may not have read what it needed"
  claude_models=$(jq -r '.modelUsage | keys | join(", ")' "$json")
  [ -n "$claude_models" ] || "$fail" "Claude's output does not say which model ran"
  jq -r .result "$json" >"$out" || "$fail" "could not read Claude's reply"
  [ -s "$out" ] || "$fail" "Claude returned no reply"
}

# The reviewer's own parts of the local review, for reviewer $1 (claude or codex).
# review_prep writes the prompt's opening (where to look) to stdout and any files
# the reviewer reads; review_run runs it; review_meta prints the record's lines on
# the tool and the model.
review_prep() { # $1 reviewer
  case "$1" in
    claude)
      git -C "$top" diff --no-ext-diff --no-textconv --no-color "$mb" "$head" >"$tmp/data/diff" || not_reviewed "could not diff $mb..$head"
      git -C "$top" log --no-color --format=medium "$mb..$head" >"$tmp/data/log" || not_reviewed "could not read the commits $mb..$head"
      printf 'Review pull request #%s. The working directory is a checkout of its head, commit %s, and you have no shell. ' "$pr" "$head"
      printf 'Review the change from %s to %s: the diff is in %s and its commits are in %s; read them and the files around the change with your file tools. Do not modify files.\n\n' "$mb" "$head" "$tmp/data/diff" "$tmp/data/log"
      ;;
    codex)
      printf 'Review pull request #%s. The working directory is a checkout of its head, commit %s. ' "$pr" "$head"
      printf 'Review the change from %s to %s (run: git diff %s %s). Do not modify files.\n\n' "$mb" "$head" "$mb" "$head"
      ;;
  esac
}
review_run() { # $1 reviewer
  case "$1" in
    claude) run_claude "$tmp/tree" "$tmp/prompt" "$out" not_reviewed "$tmp/data" ;;
    codex) run_codex "$tmp/tree" "$tmp/prompt" "$out" not_reviewed disabled ;;
  esac
}
review_meta() { # $1 reviewer
  case "$1" in
    claude)
      # The models that ran, from Claude's report, and the one asked for when none of them is it (a fallback).
      printf -- '- Claude Code: %s\n- Model: %s' "$(claude --version 2>/dev/null | head -n 1 | sed -n 's/^\([0-9][0-9.]*\).*/\1/p')" "$claude_models"
      case "$claude_models" in *"$REVIEW_MODEL"*) printf '\n' ;; *) printf ' (asked for %s)\n' "$REVIEW_MODEL" ;; esac
      ;;
    codex)
      printf -- '- Codex CLI: %s\n- Model: %s, reasoning effort %s\n' "$(codex --version 2>/dev/null)" "Codex default model" "$CODEX_EFFORT"
      ;;
  esac
}

# A local review reads the pull request's head as GitHub has it, never this
# checkout's working tree: it fetches that commit, reviews it in a temporary
# worktree, then waits for CI on that commit, and posts the result only once CI
# passed there and the head has not moved since. $1 is the reviewer: claude, the
# default, or codex (`mentat review --codex`).
review_local() {
  local reviewer="$1" pr="${2:-}" name repo info head base title body top tmp mb fetched now issues request request_fp headref baseref claude_models=""
  case "$reviewer" in
    claude) name=Claude ;;
    codex) name=Codex ;;
  esac
  case "$pr" in '' | *[!0-9]*) die "usage: mentat review [--local | --codex | --grok [--stop]] [--request <file>] [--require-ci] <pull request number>" 64 ;; esac
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
  title=$(jq -r '.title // ""' <<<"$info")
  body=$(jq -r '.body // ""' <<<"$info")
  read_issues "$pr" "$info"
  # Fetch the head and the base into refs of this run's own, named with the process id,
  # not through git's one per-checkout record of the last fetch, nor the shared
  # origin/<base> tracking ref: the review skill runs a local and a Grok review at once
  # in this checkout, and with those shared the fetches of one could overwrite or lock
  # out the other (--refmap= keeps the configured mapping from also updating origin/<base>).
  # The refs go once the merge base is known (the commits stay), and at
  # exit if the run stops before that.
  headref="refs/mentat/review-$pr-$$/head" baseref="refs/mentat/review-$pr-$$/base"
  # shellcheck disable=SC2064 # expand now, so the paths are fixed when the trap is set
  trap "git -C $(printf %q "$top") update-ref -d $(printf %q "$headref") >/dev/null 2>&1; git -C $(printf %q "$top") update-ref -d $(printf %q "$baseref") >/dev/null 2>&1" EXIT
  git -C "$top" fetch -q --no-write-fetch-head --refmap= origin "+pull/$pr/head:$headref" "+refs/heads/$base:$baseref" || not_reviewed "could not fetch pull request #$pr or $base"
  fetched=$(git -C "$top" rev-parse --verify "$headref") || not_reviewed "could not read the fetched head"
  [ "$fetched" = "$head" ] || die "the head moved from $head; run mentat review again" 3
  mb=$(git -C "$top" merge-base "$head" "$baseref") || not_reviewed "could not find where #$pr branches from $base"
  git -C "$top" update-ref -d "$headref" || not_reviewed "could not remove the ref fetched for #$pr"
  git -C "$top" update-ref -d "$baseref" || not_reviewed "could not remove the ref fetched for $base"
  tmp=$(mktemp -d) || not_reviewed "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand now, so the paths are fixed when the trap is set
  trap "git -C $(printf %q "$top") worktree remove --force $(printf %q "$tmp/tree") >/dev/null 2>&1; rm -rf $(printf %q "$tmp")" EXIT
  git -C "$top" worktree add -q --detach "$tmp/tree" "$head" || not_reviewed "could not check out $head"
  mkdir "$tmp/data" || not_reviewed "could not create a temporary directory"

  {
    review_prep "$reviewer"
    review_criteria ""
    review_requirements "$issues" "$title" "$body" "$request"
    review_result_line
  } >"$tmp/prompt" || not_reviewed "could not write the prompt"

  local out="$tmp/review.md" result url held
  review_run "$reviewer"
  localize_review_paths "$out" "$repo" "$head" "$tmp/tree" "$tmp/data" || not_reviewed "could not rewrite the paths in $name's reply"
  result=$(last_line "$out")
  case "$result" in
    "REVIEW RESULT: NO FINDINGS" | "REVIEW RESULT: FINDINGS" | "REVIEW RESULT: INCOMPLETE - "*[![:space:]]*) ;;
    *) not_reviewed "$name's reply has no final REVIEW RESULT line" ;;
  esac
  # The review ran without waiting for CI; it is posted only once CI passes on the same head.
  wait_for_ci "$repo" "$head" "$out" "$pr" "mentat review"
  now=$(gh pr view "$pr" --json headRefOid --jq .headRefOid) || not_reviewed "could not read pull request #$pr"
  [ "$now" = "$head" ] || die "the head moved from $head; run mentat review again" 3
  {
    printf '## Local %s review of %s: %s, spec fingerprint %s\n\n' "$name" "$head" "$(result_word "$result")" "$request_fp"
    printf '<details><summary>Full review</summary>\n\n'
    printf -- '- Change reviewed: %s..%s\n' "$mb" "$head"
    printf -- '- Agreed request fingerprint: %s\n' "$request_fp"
    review_meta "$reviewer"
    printf -- '- Time: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '\n---\n\n'
    cat "$out"
    printf '\n</details>\n\n%s\n' "$result"
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
