# shellcheck shell=bash
# shellcheck disable=SC2154 # module, res, name, run_pids and the run's variables are the caller's
# Outside reviewers as adapters. Each is one file, adapters/<name>.sh in this module, and
# the module ships exactly the names that have one. An adapter is loaded only in its own
# subshell, never in the command's own shell, and sets or defines:
#   adapter_display     the name people read.
#   adapter_available   an offline check that starts no reviewer and reads no network:
#                       returns 0, or sets adapter_why (public-safe words) and returns 1;
#                       adapter_kind=always also counts it as a failure in a row that is
#                       raised every time (a sign-in refusal).
#   adapter_run MODE    runs the reviewer read-only, MODE review (no web search) or opinion
#                       (web search allowed), and writes its whole reply to $reply. It
#                       waits on its tool with adapter_wait and reports a failure with
#                       adapter_fail, which exits.
#   adapter_meta        optional: prints the record's lines on the tool and the model that ran.
#   adapter_roots       optional array: more temporary folders whose paths are rewritten
#                       out of a review reply, beside the checkout and the data folder.
#   adapter_notes       optional: prints lines for mentat check, such as a setting it no
#                       longer reads.
# The run gives the adapter: name, adapter_mode, top (the repository), head (the commit
# read), tree (a checkout of head, made with the repository's hooks off), work (an empty
# folder of the adapter's own) and reply; for a review also pr, repo, mb (the merge
# base), data (the folder holding the diff and the commit log) and the prompt parts
# (review_body); for a second opinion the prompt's body in $res/body. Each run's results
# are files in $res named for the reviewer: display, why (did not finish, in public-safe
# words), local (what only the maintainer reads, such as a kept log's path), raise (the
# line that tells the maintainer now), skipped, reply, final, meta and secs.

# Whether this module ships reviewer $1. The name was checked as lowercase letters, digits
# and hyphens when the list was read, so it is never a path.
adapter_shipped() { [ -f "$module/adapters/$1.sh" ]; }

# mentat-reviewer-list: one line per name, "available <name>", "unavailable <name> <why>"
# or "skipped <name> <why>", from each adapter's offline check; with --notes first, also
# "note <text>" for each line a shipped adapter's adapter_notes prints.
adapter_list() {
  local n f notes=no
  [ "${1:-}" != --notes ] || { notes=yes; shift; }
  for n in "$@"; do
    if ! adapter_shipped "$n"; then printf 'skipped %s the mentat-reviewers module has no such reviewer\n' "$n"; continue; fi
    (
      adapter_why="" adapter_display=$n
      # shellcheck source=/dev/null
      . "$module/adapters/$n.sh" >/dev/null 2>&1 || { printf 'unavailable %s the mentat-reviewers module could not load it\n' "$n"; exit 0; }
      if adapter_available >/dev/null 2>&1; then printf 'available %s\n' "$n"
      else printf 'unavailable %s %s\n' "$n" "${adapter_why:-its check failed}"; fi
    )
  done
  [ "$notes" = yes ] || return 0
  for f in "$module"/adapters/*.sh; do
    [ -f "$f" ] || continue
    (
      # shellcheck source=/dev/null
      . "$f" >/dev/null 2>&1 || exit 0
      if declare -F adapter_notes >/dev/null; then adapter_notes | sed 's/^/note /'; fi
    )
  done
}

# Ends a runner: the reviewer did not finish, for reason $1, which is posted and so names
# no local path and holds no tool output. $2, optional, is what only the maintainer reads,
# such as where a kept log is. $3: empty, a failure of the reviewer's own that counts in
# its failures in a row; usage or always, the same, raised as reviewer_failed says; none,
# not counted. Only a review counts; a second opinion never does.
adapter_fail() { # $1 public reason, $2 local detail, $3 kind
  review_raise=""
  if [ "${adapter_mode:-}" = review ] && [ "${3:-}" != none ]; then
    reviewer_failed "$name" "${adapter_display:-$name}" "${3:-}"
  fi
  printf '%s\n' "$(printf '%s' "$1" | tr '\n' ' ')" >"$res/$name.why"
  [ -z "${2:-}" ] || printf '%s\n' "$(printf '%s' "$2" | tr '\n' ' ')" >"$res/$name.local"
  [ -z "$review_raise" ] || printf '%s: %s%s\n' "$review_raise" "$1" "${2:+; $2}" >"$res/$name.raise"
  exit 1
}

# Waits for the reviewer's tool, process $1, under the one time limit for every reviewer,
# REVIEW_TIMEOUT_SECONDS: past it, the tool is stopped (TERM, then KILL two seconds later)
# and the reviewer did not finish, with $2 as adapter_fail's local detail. Sets the
# caller's adapter_rc to the tool's exit status. $SECONDS counts whole seconds, so the
# limit stops a tool up to a second late, never early.
adapter_wait() { # $1 pid, $2 local detail on a timeout
  local secs=$SECONDS
  while kill -0 "$1" 2>/dev/null; do
    if [ $((SECONDS - secs)) -gt "$REVIEW_TIMEOUT_SECONDS" ]; then
      kill "$1" 2>/dev/null
      sleep 2
      kill -9 "$1" 2>/dev/null
      wait "$1" 2>/dev/null
      adapter_fail "$adapter_display did not finish within $REVIEW_TIMEOUT_SECONDS seconds" "${2:-}"
    fi
    sleep 0.1
  done
  wait "$1"
  adapter_rc=$?
}

# In a runner: loads adapter $name for mode $1 and runs it, leaving its whole reply in
# $reply. A name the module does not ship is skipped; one whose offline check fails did
# not finish.
adapter_go() { # $1 review or opinion
  adapter_mode=$1 adapter_display=$name adapter_why="" adapter_kind=none adapter_roots=()
  if ! adapter_shipped "$name"; then
    printf 'the mentat-reviewers module has no such reviewer\n' >"$res/$name.skipped"
    exit 0
  fi
  # shellcheck source=/dev/null
  . "$module/adapters/$name.sh" || adapter_fail "the mentat-reviewers module could not load it" "" none
  printf '%s\n' "$adapter_display" >"$res/$name.display"
  adapter_available || adapter_fail "${adapter_why:-its check failed}" "" "$adapter_kind"
  work="$res/$name.work" reply="$res/$name.work/reply"
  mkdir "$work" || adapter_fail "could not create a temporary folder" "" none
  adapter_run "$1"
  [ -s "$reply" ] || adapter_fail "$adapter_display returned no reply"
}

# A runner stopped by its parent stops its tool, and then exits, which runs its EXIT
# trap. (bash 3.2 has no wait -n and no $BASHPID.)
adapters_stop() {
  local p
  for p in $(jobs -p); do kill "$p" 2>/dev/null; done
  sleep 2
  for p in $(jobs -p); do kill -9 "$p" 2>/dev/null; done
  wait
  exit 143
}

# The parent stopped: stop every runner, wait for them, then leave.
adapters_cancel() {
  local p
  for p in $run_pids; do kill "$p" 2>/dev/null; done
  wait
  exit 143
}

# Runs function $1 once per name in $2..., each in its own background subshell with name
# set, in parallel, and waits for all, writing how long each took to $res/<name>.secs.
# A runner ends with exit, so only the runner stops. Sets the caller's run_pids.
adapters_run() { # $1 runner, $2... names
  local runner=$1 n i alive pids=()
  shift
  SECONDS=0
  run_pids=""
  for n in "$@"; do
    ( name=$n; trap adapters_stop TERM; "$runner" ) &
    pids+=("$!")
    run_pids="$run_pids $!"
  done
  while :; do
    alive=no i=0
    for n in "$@"; do
      if kill -0 "${pids[$i]}" 2>/dev/null; then alive=yes
      elif [ ! -e "$res/$n.secs" ]; then printf '%s\n' "$SECONDS" >"$res/$n.secs"; fi
      i=$((i + 1))
    done
    [ "$alive" = yes ] || break
    sleep 0.1
  done
  for n in ${pids[@]+"${pids[@]}"}; do wait "$n"; done
}

# The name reviewer $1 is shown by: its display name once loaded, else its name.
adapter_shown() { if [ -s "$res/$1.display" ]; then cat "$res/$1.display"; else printf '%s\n' "$1"; fi; }
# Why reviewer $1 did not finish, in public-safe words.
adapter_why_text() { if [ -s "$res/$1.why" ]; then cat "$res/$1.why"; else printf 'it ended without a result\n'; fi; }
# Prints, on stderr, what only the maintainer reads about reviewer $1's run, and the line
# that tells the maintainer now when its failure raised one.
adapter_local_lines() {
  [ ! -s "$res/$1.local" ] || printf 'mentat: %s: %s\n' "$1" "$(cat "$res/$1.local")" >&2
  [ ! -s "$res/$1.raise" ] || printf 'mentat: tell the maintainer now: %s\n' "$(cat "$res/$1.raise")" >&2
}
