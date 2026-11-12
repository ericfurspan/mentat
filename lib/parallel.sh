# shellcheck shell=bash
# shellcheck disable=SC2154 # res, tool and run_pids are the caller's variables
# The plumbing both modes of mentat second-opinion share: each review tool (Codex,
# Grok) runs in a background subshell, in parallel, and the result is printed
# for the maintainer. Sourced by bin/mentat.

# Each tool runs in its own background subshell, so a failure (which exits) and the
# EXIT trap that cleans up its folder stay inside it. A runner leaves its result in
# files in the parent's folder, outside any folder a runner removes: the reply and
# its final line when it delivered, otherwise the reason it did not; the parent
# notes how long each took. The functions here read and set the caller's variables
# by name (res, tool, run_pids), as the Grok functions do. They know nothing of what
# the tools are asked.

# Ends a runner and records why its tool did not deliver. Reads the caller's res and tool.
pair_fail() {
  printf '%s\n' "$(printf '%s' "$1" | tr '\n' ' ')" >"$res/$tool.why"
  exit 1
}

# Ends the Grok runner like pair_fail, after keeping Grok's raw log. This runs before
# the exit, because the EXIT trap removes the run folder. The log may hold a
# credential: only its path is printed.
pair_grok_fail() {
  local kept
  grok_keep_log
  pair_fail "$1${kept:+; its log may hold credentials, so it is not printed. The maintainer can read it at $kept}"
}

# Keeps a reply whose final line passes the checker function $2 (named by the caller;
# $3 names the line in the failure) as this tool's result.
pair_keep() { # $1 reply file, $2 checker, $3 name of the final line
  local final
  final=$(last_line "$1")
  "$2" "$final" || pair_fail "the reply has no final $3 line"
  cp "$1" "$res/$tool.reply" || pair_fail "could not keep the reply"
  printf '%s\n' "$final" >"$res/$tool.final" || pair_fail "could not keep the final line"
}

# A runner killed by its parent stops its model process, and then exits, which runs
# its EXIT trap. (bash 3.2 has no wait -n and no $BASHPID.)
pair_stop() {
  local p
  for p in $(jobs -p); do kill "$p" 2>/dev/null; done
  sleep 2
  for p in $(jobs -p); do kill -9 "$p" 2>/dev/null; done
  wait
  exit 143
}

# The parent killed: stop every runner, wait for them, then leave.
pair_cancel() {
  local p
  for p in $run_pids; do kill "$p" 2>/dev/null; done
  wait
  exit 143
}

# Starts each tool's runner, named <$1>_<tool> (opinion_codex, opinion_web_grok), each in
# its own subshell, and waits for all, writing how long each took to $res/<tool>.secs.
# Sets the caller's run_pids.
pair_run() { # $1 runner prefix, $2... tools
  local prefix=$1 t i alive pids=()
  shift
  SECONDS=0
  run_pids=""
  # The runners are subshells that share the caller's variables; each ends with
  # `exit`, so only the runner stops.
  for t in "$@"; do
    ( tool=$t; trap pair_stop TERM; "${prefix}_$t" ) &
    pids+=("$!")
    run_pids="$run_pids $!"
  done
  while :; do
    alive=no i=0
    for t in "$@"; do
      if kill -0 "${pids[$i]}" 2>/dev/null; then alive=yes
      elif [ ! -e "$res/$t.secs" ]; then printf '%s\n' "$SECONDS" >"$res/$t.secs"; fi
      i=$((i + 1))
    done
    [ "$alive" = yes ] || break
    sleep 0.1
  done
  for t in "${pids[@]}"; do wait "$t"; done
}

# The printers say "no second opinion" and why for a tool that did not deliver.
pair_name() { # $1 tool key
  case "$1" in codex) printf Codex ;; grok) printf Grok ;; esac
}
pair_report() { # $1 tool key
  printf '## %s\n\n' "$(pair_name "$1")"
  if [ -s "$res/$1.final" ]; then
    cat "$res/$1.reply"
  else
    printf 'no second opinion (%s)\n' "$(pair_why "$1")"
  fi
  printf '\n(%s seconds)\n\n' "$(cat "$res/$1.secs" 2>/dev/null)"
}
pair_why() { # $1 tool key
  if [ -s "$res/$1.why" ]; then cat "$res/$1.why"; else printf 'it ended without a result'; fi
}
pair_line() { # $1 tool key
  if [ -s "$res/$1.final" ]; then
    printf -- '- %s (%s seconds): %s\n' "$(pair_name "$1")" "$(cat "$res/$1.secs" 2>/dev/null)" "$(cat "$res/$1.final")"
  else
    printf -- '- %s (%s seconds): no second opinion (%s)\n' "$(pair_name "$1")" "$(cat "$res/$1.secs" 2>/dev/null)" "$(pair_why "$1")"
  fi
}
