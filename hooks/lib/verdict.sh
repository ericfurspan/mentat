# shellcheck shell=bash
# Sourced by Mentat's enforcing PreToolUse hooks; one way to read, decide and print.
# A hook defines a check function that ends with verdict pass, verdict ask <reason>
# or verdict deny <reason> (one line), then calls run_hook <check>. run_hook reads the
# input into $input and $tool, runs the check in a subshell and prints exactly one
# JSON object, exiting 0: {} for pass (no "allow", so the normal permission prompts
# still apply), else a deny or ask decision. It fails closed: no jq, input that is not
# one JSON object with a tool_name, a check that exits non-zero, or a result that is
# empty, more than one line or no verdict word denies, naming the hook.
# Hooks are nets for common mistakes, not a security boundary.

hook_name=${0##*/}
input="" tool=""

# deny_literal <reason>: a deny printed without jq; the reason holds no " or \.
deny_literal() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Mentat: %s"}}\n' "$1"
}

# verdict <word> [reason]: the check's result. It ends the check's subshell.
verdict() {
  printf '%s\n' "$*"
  exit 0
}

# field <jq path>: prints the input's string at that path, or nothing.
field() { printf '%s' "$input" | jq -r "$1 | strings"; }

# decide <deny|ask> <reason>: prints the decision, with "Mentat: " in front of the reason.
decide() {
  local r=$2
  case "$r" in "Mentat: "*) ;; *) r="Mentat: $r" ;; esac
  jq -cn --arg d "$1" --arg r "$r" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}' ||
    deny_literal "$hook_name could not print its verdict, so it blocks this call."
}

# run_hook <check>: reads stdin, runs the check and prints its verdict; never returns.
run_hook() {
  local out rc
  unset CDPATH
  if ! command -v jq >/dev/null 2>&1; then
    deny_literal "$hook_name needs jq, which is missing, so it blocks this call."
    exit 0
  fi
  input=$(cat) || input=""
  tool=$(printf '%s' "$input" |
    jq -sr 'if length == 1 and (.[0] | type) == "object" then .[0].tool_name else empty end | strings' 2>/dev/null) ||
    tool=""
  if [ -z "$tool" ]; then
    decide deny "$hook_name could not read its input (one JSON object with a tool_name), so it blocks this call."
    exit 0
  fi
  out=$("$1")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    decide deny "$hook_name failed (exit $rc), so it blocks this call."
    exit 0
  fi
  case "$out" in
    *$'\n'*) decide deny "$hook_name gave more than one result, so it blocks this call." ;;
    pass) printf '{}\n' ;;
    "ask "?*) decide ask "${out#ask }" ;;
    deny) decide deny "$hook_name blocks this call." ;;
    "deny "?*) decide deny "${out#deny }" ;;
    *) decide deny "$hook_name gave no verdict, so it blocks this call." ;;
  esac
  exit 0
}
