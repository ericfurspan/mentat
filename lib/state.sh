# shellcheck shell=bash
# mentat state: the orchestrator's handover state, one JSON store at
# <git common dir>/mentat/state.json shared by every worktree. Sourced by bin/mentat, and by
# the child that writes the store under the lock.
# shellcheck disable=SC2154,SC2016
# (File-wide: root is set by bin/mentat or by the locked child; the $ in single-quoted jq
# programs and in the locked child's script is theirs, not the shell's.)

state_usage="usage: mentat state show | mentat state orchestrator [set <id> | ended <id>] | mentat state owner [<item>] | mentat state session add <id> <item>... | mentat state session end <id> | mentat state session list | mentat state item set <id> [--fingerprint F] [--stage S] [--session ID] [--pr N] [--held-by TEXT] | mentat state item get <id> | mentat state item list [--stage S] | mentat state note add <hold|question> <text> | mentat state note list [<hold|question>] | mentat state note clear <id> | mentat state can-dispatch"
state_stages="held handed confirmed not-taken pr ready merged closed"

# Test-only overrides, which only tests set: STATE_LOCKF and STATE_FLOCK, the lockf and
# flock to use (a path that is not an executable counts as not found), and
# STATE_LOCK_SECONDS, how long a write waits for the lock (10 otherwise).

# A known store: one JSON object whose known fields have their types. Prints the object.
state_valid='def t($k; $ty): (has($k) | not) or (.[$k] | type == $ty);
def o: type == "object";
if length == 1 and (.[0] | o
  and ((has("orchestrator") | not) or (.orchestrator | o and t("id"; "string") and t("ended"; "boolean")))
  and ((has("sessions") | not) or (.sessions | o and all(.[]; o and t("ended"; "boolean"))))
  and ((has("items") | not) or (.items | o and all(.[]; o and t("fingerprint"; "string") and t("stage"; "string") and t("session"; "string") and t("pr"; "number") and t("held_by"; "string"))))
  and ((has("notes") | not) or (.notes | type == "array" and all(.[]; o and t("id"; "number") and t("kind"; "string") and t("text"; "string") and t("cleared"; "boolean")))))
then .[0] else false end'

state_usage_die() { die "${1:-$state_usage}" 64; }

# An id, item or session name: not empty and not an option.
state_name_ok() { case "${1:-}" in '' | -*) return 1 ;; esac; }
state_stage_ok() { case " $state_stages " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac; }
state_kind_ok() { [ "${1:-}" = hold ] || [ "${1:-}" = question ]; }

# Sets state_dir, state_file and state_lock from the current repository; exit 2 outside one.
state_locate() {
  local common
  if ! common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || [ -z "$common" ]; then
    die "not inside a git repository; nothing read or written" 2
  fi
  state_dir="$common/mentat"
  state_file="$state_dir/state.json"
  state_lock="$state_dir/state.lock"
}

# Reads state_file into state_json (compact); a missing file is {}. Exit 2 naming the file
# when it cannot be read or is not a valid store.
state_load() {
  if [ ! -e "$state_file" ]; then
    state_json='{}'
    return 0
  fi
  if ! state_json=$(jq -cse "$state_valid" "$state_file" 2>/dev/null) || [ -z "$state_json" ]; then
    die "the state store could not be read or is not valid (empty, not JSON, not one JSON object, or a field of the wrong type); nothing changed: $state_file" 2
  fi
}

# Runs jq on state_json with the given arguments: state_jq prints its output, state_q sets
# state_r to it. Exit 2 when jq fails.
state_jq() { jq "$@" <<<"$state_json" || die "could not read the state store: $state_file" 2; }
state_q() { state_r=$(jq "$@" <<<"$state_json") || die "could not read the state store: $state_file" 2; }

# Runs the write $1 with its arguments $2... under the lock on state_lock, in a child that
# reads the store, applies the write and renames a temporary file over the store. The
# child's own exits (0, 1, 2, 64) pass through; the lock not free is exit 2 naming it.
state_write() {
  local seconds lockf flock rc
  state_locate
  seconds=${STATE_LOCK_SECONDS:-10}
  lockf=${STATE_LOCKF:-/usr/bin/lockf}
  flock=${STATE_FLOCK:-$(command -v flock 2>/dev/null)}
  set -- "$BASH" -c 'set -uo pipefail
root=$1
. "$root/lib/shared.sh" && . "$root/lib/state.sh" || exit 2
shift
state_locked "$@"' mentat-state "$root" "$state_file" "$@"
  # 75 is EX_TEMPFAIL, lockf's exit when the lock is not free in time; flock is told the same.
  if [ -x "$lockf" ]; then
    set -- "$lockf" -s -k -t "$seconds" "$state_lock" "$@"
  elif [ -n "$flock" ] && [ -x "$flock" ]; then
    set -- "$flock" -E 75 -w "$seconds" "$state_lock" "$@"
  else
    die "cannot lock the state store: neither lockf ($lockf) nor flock was found; nothing written" 2
  fi
  mkdir -p "$state_dir" || die "could not make the state store's folder: $state_dir" 2
  "$@"
  rc=$?
  case "$rc" in
    0 | 1 | 2 | 64) exit "$rc" ;;
    75) die "the state store's lock was not free within $seconds seconds; nothing written: $state_lock" 2 ;;
    *) die "could not take the state store's lock or write the store (exit $rc); nothing written: $state_lock" 2 ;;
  esac
}

# In the locked child: $1 the store, $2 the write, $3... its arguments. Reads the store,
# applies the write (which may refuse, exit 1) and renames a temporary file over the store.
state_locked() {
  local tmp
  state_file=$1
  state_out=""
  shift
  state_load
  "state_op_$1" "${@:2}"
  tmp=$(mktemp "$state_file.XXXXXX") || die "could not write the state store: $state_file" 2
  if ! printf '%s\n' "$state_json" >"$tmp" || ! mv -f "$tmp" "$state_file"; then
    rm -f "$tmp"
    die "could not write the state store: $state_file" 2
  fi
  [ -z "$state_out" ] || printf '%s\n' "$state_out"
}

state_op_orchestrator_set() {
  state_q -c --arg id "$1" '.orchestrator = {id: $id, ended: false}'
  state_json=$state_r
  state_out="recorded orchestrator $1"
}

state_op_orchestrator_ended() {
  state_q -r '.orchestrator.id // ""'
  [ -n "$state_r" ] || die "no orchestrator is recorded, so $1 was not marked ended; nothing changed" 1
  [ "$state_r" = "$1" ] || die "the recorded orchestrator is $state_r, not $1; nothing changed" 1
  state_q -c '.orchestrator.ended = true'
  state_json=$state_r
  state_out="marked orchestrator $1 no longer running"
}

# Merges object $2 (JSON) into item $1, made when new. item set and session add both use it.
state_item_merge() {
  state_q -c --arg id "$1" --argjson set "$2" '.items = (.items // {}) | .items[$id] = ((.items[$id] // {}) + $set)'
  state_json=$state_r
}

# $1 the item, then pairs of field and value; pr is a number.
state_op_item_set() {
  local id=$1 set stage
  shift
  set=$(jq -cn '[$ARGS.positional | range(0; length; 2) as $i | {key: .[$i], value: (if .[$i] == "pr" then (.[$i + 1] | tonumber) else .[$i + 1] end)}] | from_entries' --args "$@") ||
    die "could not read the item's fields" 2
  stage=$(jq -r '.stage // ""' <<<"$set") || die "could not read the item's fields" 2
  if [ "$stage" = pr ] || [ "$stage" = ready ]; then
    state_q -r --arg id "$id" --argjson set "$set" '($set | has("pr")) or ((.items // {})[$id].pr != null)'
    [ "$state_r" = true ] || die "item $id has no PR number, so it cannot be at stage $stage (give --pr); nothing changed" 1
  fi
  state_item_merge "$id" "$set"
  state_out="recorded item $id"
}

state_op_session_add() {
  local id=$1 set item
  shift
  state_q -c --arg id "$id" '.sessions = (.sessions // {}) | .sessions[$id] = ((.sessions[$id] // {}) + {ended: false})'
  state_json=$state_r
  set=$(jq -cn --arg id "$id" '{session: $id}') || die "could not read the session" 2
  for item in "$@"; do state_item_merge "$item" "$set"; done
  state_out="recorded session $id for $*"
}

state_op_session_end() {
  state_q -r --arg id "$1" '.sessions // {} | has($id)'
  [ "$state_r" = true ] || die "no session $1 is recorded; nothing changed" 1
  state_q -c --arg id "$1" '.sessions[$id].ended = true'
  state_json=$state_r
  state_out="marked session $1 ended"
}

state_op_note_add() {
  state_q -c --arg kind "$1" --arg text "$2" '.notes = (.notes // []) | .notes += [{id: (([.notes[].id] | max // 0) + 1), kind: $kind, text: $text, cleared: false}]'
  state_json=$state_r
  state_q -r '.notes[-1].id'
  state_out=$state_r
}

state_op_note_clear() {
  state_q -r --argjson id "$1" '[.notes // [] | .[] | select(.id == $id) | .cleared] | if length == 0 then "none" else (.[0] | tostring) end'
  [ "$state_r" != none ] || die "no note $1 is recorded; nothing changed" 1
  [ "$state_r" = false ] || die "note $1 is already cleared; nothing changed" 1
  state_q -c --argjson id "$1" '.notes |= map(if .id == $id then .cleared = true else . end)'
  state_json=$state_r
  state_out="cleared note $1"
}

# Reads the store for a read-only command.
state_read() {
  state_locate
  state_load
}

# mentat state can-dispatch: waiting pull requests, the limit and how many items may be
# handed over. 0 when at least 1, 1 when none, 2 when it cannot answer.
state_can_dispatch() {
  local limit default=3 prs counts waiting flight list free digits
  state_read
  limit=${MENTAT_READY_LIMIT:-}
  if [ -z "$limit" ]; then
    limit=$default
  else
    digits=$(printf '%s' "$limit" | sed 's/^0*//')
    case "$limit" in
      *[!0-9]*) digits="" ;;
    esac
    if [ -z "$digits" ]; then
      printf 'mentat: MENTAT_READY_LIMIT is not a whole number of 1 or more (%s); using %s\n' "$limit" "$default" >&2
      limit=$default
    elif [ ${#digits} -gt 9 ]; then
      limit=999999999
    else
      limit=$digits
    fi
  fi
  if ! prs=$(gh pr list --state open --limit 1000 --json number,body 2>/dev/null); then
    die "could not read the open pull requests (gh failed or is not signed in); no count" 2
  fi
  if ! counts=$(jq -r --argjson s "$state_json" '
    def first_line: (.body // "") | (split("\n")[0] // "") | gsub("\r"; "");
    if type != "array" then error("not a list") else . end
    | [.[] | .number] as $open
    | ($s.items // {} | [.[]]) as $items
    | ([.[] | select(first_line == "**Status:** Ready" or first_line == "**Status:** Not reviewed: fast track agreed by the maintainer") | .number]
      + [$items[] | select(.stage == "ready" and has("pr")) | .pr as $p | select($open | any(.[]; . == $p)) | $p] | unique) as $waiting
    | ([$items[] | select(.stage == "handed" or .stage == "confirmed"
        or (.stage == "pr" and has("pr") and (.pr as $p | ($open | any(.[]; . == $p)) and ($waiting | any(.[]; . == $p) | not))))] | length) as $flight
    | "\($waiting | length)\t\($flight)\t\($waiting | map("#\(.)") | join(" "))"' <<<"$prs" 2>/dev/null) || [ -z "$counts" ]; then
    die "could not read the open pull requests (gh's answer was not a list of pull requests); no count" 2
  fi
  IFS=$'\t' read -r waiting flight list <<<"$counts"
  free=$((limit - waiting - flight))
  [ "$free" -ge 0 ] || free=0
  printf 'waiting: %s%s\n' "$waiting" "${list:+ ($list)}"
  printf 'in flight: %s\n' "$flight"
  printf 'limit: %s\n' "$limit"
  printf 'can hand over: %s\n' "$free"
  [ "$free" -ge 1 ]
}

# mentat state item set <id> [options]: checks the options, then writes them as pairs.
state_item_set() {
  local id=${1:-} pairs=()
  state_name_ok "$id" || state_usage_die
  shift
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || state_usage_die
    case "$1" in
      --fingerprint)
        case "$2" in ????????????) ;; *) state_usage_die "the fingerprint is not 12 hex characters: $2" ;; esac
        case "$2" in *[!0-9a-f]*) state_usage_die "the fingerprint is not 12 hex characters: $2" ;; esac
        pairs+=(fingerprint "$2") ;;
      --stage) state_stage_ok "$2" || state_usage_die "unknown stage: $2 (one of: $state_stages)"; pairs+=(stage "$2") ;;
      --session) state_name_ok "$2" || state_usage_die; pairs+=(session "$2") ;;
      --pr)
        case "$2" in '' | *[!0-9]* | 0*) state_usage_die "the PR number is not a whole number of 1 or more: $2" ;; esac
        [ ${#2} -le 15 ] || state_usage_die "the PR number is too long: $2"
        pairs+=(pr "$2") ;;
      --held-by) pairs+=(held_by "$2") ;;
      *) state_usage_die ;;
    esac
    shift 2
  done
  state_write item_set "$id" ${pairs[@]+"${pairs[@]}"}
}

state_command() {
  local sub=${1:-} v
  [ $# -eq 0 ] || shift
  case "$sub" in
    show)
      [ $# -eq 0 ] || state_usage_die
      state_read
      state_jq .
      ;;
    orchestrator)
      case "${1:-}" in
        '')
          [ $# -eq 0 ] || state_usage_die
          state_read
          state_q -r 'if (.orchestrator.id // "") == "" then "" else "\(.orchestrator.id) \(if .orchestrator.ended then "ended" else "running" end)" end'
          [ -n "$state_r" ] || die "no orchestrator is recorded" 1
          printf '%s\n' "$state_r"
          ;;
        set | ended)
          { [ $# -eq 2 ] && state_name_ok "$2"; } || state_usage_die
          state_write "orchestrator_$1" "$2"
          ;;
        *) state_usage_die ;;
      esac
      ;;
    owner)
      [ $# -le 1 ] || state_usage_die
      if [ $# -eq 1 ]; then
        state_name_ok "$1" || state_usage_die
        state_read
        state_q -r --arg id "$1" '(.items // {})[$id].session // ""'
        [ -n "$state_r" ] || die "item $1 has no recorded build session" 1
      else
        state_read
        state_q -r 'if .orchestrator.ended then "" else .orchestrator.id // "" end'
        [ -n "$state_r" ] || die "no running orchestrator is recorded" 1
      fi
      printf '%s\n' "$state_r"
      ;;
    session)
      case "${1:-}" in
        add)
          [ $# -ge 3 ] || state_usage_die
          for v in "${@:2}"; do state_name_ok "$v" || state_usage_die; done
          state_write session_add "${@:2}"
          ;;
        end)
          { [ $# -eq 2 ] && state_name_ok "$2"; } || state_usage_die
          state_write session_end "$2"
          ;;
        list)
          [ $# -eq 1 ] || state_usage_die
          state_read
          state_jq -r '(.items // {}) as $items | (.sessions // {}) | to_entries[] | .key as $k
            | "\($k)\t\(if .value.ended then "ended" else "running" end)\t\([$items | to_entries[] | select(.value.session == $k) | .key] | join(" "))"'
          ;;
        *) state_usage_die ;;
      esac
      ;;
    item)
      case "${1:-}" in
        set) shift; state_item_set "$@" ;;
        get)
          { [ $# -eq 2 ] && state_name_ok "$2"; } || state_usage_die
          state_read
          state_q -r --arg id "$2" '.items // {} | has($id)'
          [ "$state_r" = true ] || die "no item $2 is recorded" 1
          state_jq --arg id "$2" '{id: $id} + .items[$id]'
          ;;
        list)
          if [ $# -eq 3 ] && [ "$2" = --stage ]; then
            state_stage_ok "$3" || state_usage_die "unknown stage: $3 (one of: $state_stages)"
          elif [ $# -ne 1 ]; then
            state_usage_die
          fi
          state_read
          state_jq -r --arg stage "${3:-}" '.items // {} | to_entries[] | select($stage == "" or .value.stage == $stage) | "\(.key)\t\(.value.stage // "-")"'
          ;;
        *) state_usage_die ;;
      esac
      ;;
    note)
      case "${1:-}" in
        add)
          [ $# -eq 3 ] && [ -n "$3" ] || state_usage_die
          state_kind_ok "$2" || state_usage_die "unknown note kind: $2 (hold or question)"
          state_write note_add "$2" "$3"
          ;;
        list)
          [ $# -le 2 ] || state_usage_die
          [ $# -eq 1 ] || state_kind_ok "$2" || state_usage_die "unknown note kind: $2 (hold or question)"
          state_read
          state_jq -r --arg kind "${2:-}" '.notes // [] | .[] | select($kind == "" or .kind == $kind) | "\(.id)\t\(.kind)\t\(if .cleared then "cleared" else "open" end)\t\(.text)"'
          ;;
        clear)
          [ $# -eq 2 ] || state_usage_die
          case "$2" in '' | *[!0-9]* | 0*) state_usage_die "the note id is not a whole number of 1 or more: $2" ;; esac
          [ ${#2} -le 15 ] || state_usage_die "the note id is too long: $2"
          state_write note_clear "$2"
          ;;
        *) state_usage_die ;;
      esac
      ;;
    can-dispatch)
      [ $# -eq 0 ] || state_usage_die
      state_can_dispatch
      ;;
    *) state_usage_die ;;
  esac
}
