# shellcheck shell=bash
# shellcheck disable=SC2154 # res, tool, cpid, gpid, csecs and gsecs are the caller's variables
# The plumbing mentat weigh and mentat consult share: Codex and Grok each run in a
# background subshell, in parallel, and the result is printed for the maintainer.
# Sourced by bin/mentat.

# Each tool runs in its own background subshell, so a failure (which exits) and the
# EXIT trap that cleans up its folder stay inside it. A runner leaves its result in
# files in the parent's folder, outside any folder a runner removes: the reply and
# its final line when it delivered, otherwise the reason it did not. The functions
# here read and set the caller's variables by name (res, tool, cpid, gpid, csecs,
# gsecs), as the Grok functions do. They know nothing of what the tools are asked.

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

# The parent killed: stop both runners, wait for them, then leave.
pair_cancel() {
  local p
  for p in $cpid $gpid; do kill "$p" 2>/dev/null; done
  wait
  exit 143
}

# Starts the Codex runner function $1 and the Grok runner function $2, each in its own
# subshell, and waits for both, noting how long each took. Sets the caller's cpid,
# gpid, csecs and gsecs.
pair_run() { # $1 Codex runner, $2 Grok runner
  local alive
  SECONDS=0
  # The runners are subshells that share the caller's variables; each ends with
  # `exit`, so only the runner stops.
  ( tool=codex; trap pair_stop TERM; "$1" ) &
  cpid=$!
  ( tool=grok; trap pair_stop TERM; "$2" ) &
  gpid=$!
  while :; do
    alive=no
    if kill -0 "$cpid" 2>/dev/null; then alive=yes; elif [ -z "$csecs" ]; then csecs=$SECONDS; fi
    if kill -0 "$gpid" 2>/dev/null; then alive=yes; elif [ -z "$gsecs" ]; then gsecs=$SECONDS; fi
    [ "$alive" = yes ] || break
    sleep 1
  done
  wait "$cpid"
  wait "$gpid"
}

# The printers take the caller's word for a tool that did not deliver ("not weighed",
# "not consulted").
pair_report() { # $1 tool key, $2 heading, $3 seconds, $4 word
  printf '## %s\n\n' "$2"
  if [ -s "$res/$1.final" ]; then
    cat "$res/$1.reply"
  else
    printf '%s: %s\n' "$4" "$(pair_why "$1")"
  fi
  printf '\n(%s seconds)\n\n' "$3"
}
pair_why() { # $1 tool key
  if [ -s "$res/$1.why" ]; then cat "$res/$1.why"; else printf 'it ended without a result'; fi
}
pair_line() { # $1 tool key, $2 heading, $3 seconds, $4 word
  if [ -s "$res/$1.final" ]; then
    printf -- '- %s (%s seconds): %s\n' "$2" "$3" "$(cat "$res/$1.final")"
  else
    printf -- '- %s (%s seconds): %s: %s\n' "$2" "$3" "$4" "$(pair_why "$1")"
  fi
}
