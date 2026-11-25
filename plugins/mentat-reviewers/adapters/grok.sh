# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # adapter_* are read, and the run's variables set, by lib/adapter.sh
# The Grok adapter (lib/adapter.sh says what an adapter is), with its sandbox profile and
# its isolated home.
#
# Grok gets read-only file tools and no shell, a plain export of the head without git
# history, and, in a review, the diff inside its prompt. It runs as the user's Grok
# sign-in, in a home folder Mentat builds for it, inside Grok's own sandbox (a custom
# profile built on `strict`), which fails closed: if the profile cannot be applied, Grok
# refuses to start. The profile and the permission rules are built from where things are
# at run time, in the per-run folder below. Nothing in the user's Grok home but auth.json
# is copied: no config, MCP servers, hooks or keys. A sign-in whose access token is past
# its expiry, or would pass it before the run ends, is first refreshed by running
# `grok models` once in the user's own Grok home (outside the run, where Grok can write
# it) and is refused before the copy only if that did not extend it, since Grok cannot
# refresh it inside the run. A second opinion may also use Grok's backend web search (the
# local fetch tool stays denied); a review has no web at all.
# Convention: these functions set the caller's variables by name and never return
# values; a reader tracing a variable should start from adapter_run, which declares them.
adapter_display=Grok
GROK_PROFILE="mentat-review"
# Always passed as --reasoning-effort: the setting's value, else its default (docs/settings.md)
# (not checked; a review's record names it, in safe characters, as the level asked for).
GROK_REASONING_EFFORT="${MENTAT_GROK_REASONING_EFFORT:-high}"
realdir() { (cd -P "$1" 2>/dev/null && pwd -P); }
toml_string() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

# Installed, and signed in: an auth.json in the user's Grok home holding a sign-in. Every
# sign-in refusal starts with "Grok is not signed in" or "Grok's sign-in" and is raised
# every time it fails a review (adapter_kind=always).
adapter_available() {
  command -v grok >/dev/null 2>&1 || { adapter_why="grok is not installed"; return 1; }
  command -v jq >/dev/null 2>&1 || { adapter_why="jq is not installed"; return 1; }
  grok_signed_in && return 0
  adapter_kind=always
  return 1
}

# The time limit is MENTAT_REVIEW_TIMEOUT_SECONDS, for every reviewer; Grok's own setting
# is not read any more, and mentat check says so when it is set.
adapter_notes() {
  [ -z "${MENTAT_GROK_TIMEOUT_SECONDS:-}" ] ||
    printf 'MENTAT_GROK_TIMEOUT_SECONDS is set but not read: MENTAT_REVIEW_TIMEOUT_SECONDS is the one time limit for every reviewer\n'
}

adapter_run() {
  local grok_bin real_grok home_real tmpdir denied roots cache ghome entries args=() out err result_file run="" kept
  local web_search=""
  [ "$1" = review ] || web_search=1
  grok_bin=$(command -v grok)
  grok_signin
  grok_run_folder "run-grok"
  grok_export_head
  if [ "$1" = review ]; then
    adapter_roots=("$run/export" "$cache/mentat/${run##*/}/export")
    git -C "$top" diff --no-ext-diff --no-textconv --no-color "$mb" "$head" >"$run/diff" || adapter_fail "could not diff $mb..$head" "" none
    {
      printf 'Review pull request #%s. The working directory is a plain export of its head, commit %s, without git history, and you have no shell. ' "$pr" "$head"
      printf 'Review the change from %s to %s, which is the diff below; read the files around it with your file tools. Do not modify files.\n\n' "$mb" "$head"
      review_criteria " and the diff"
      review_requirements "$issues" "$title" "$body" "$request"
      printf -- '--- BEGIN DIFF DATA ---\n'
      cat "$run/diff"
      printf -- '\n--- END DIFF DATA ---\n\n'
      review_result_line
    } >"$run/in/prompt" || adapter_fail "could not write the prompt" "" none
  else
    {
      printf 'The working directory is a plain export of commit %s, without git history, and you have no shell, only file tools and web search. ' "$head"
      printf 'You may search the web, but you cannot fetch pages: say which claims you checked and where; a claim you could not check is "could not verify".\n\n'
      cat "$res/body"
    } >"$run/in/prompt" || adapter_fail "could not write the prompt" "" none
  fi
  grok_home
  grok_args
  grok_exec
  grok_reply
  cp "$result_file" "$reply" || adapter_fail "could not keep Grok's reply" "" none
  grok_model >"$work/model"
}

adapter_meta() {
  printf -- '- Grok CLI: %s\n- Model: %s\n- Reasoning effort asked for: %s\n' "$(grok --version 2>/dev/null | head -n 1)" "$(cat "$work/model" 2>/dev/null)" \
    "$(printf '%s' "$GROK_REASONING_EFFORT" | tr -cd 'A-Za-z0-9._-' | head -c 32)"
  printf -- '- Run with file-reading tools and no shell.\n'
}

# The model that ran, from Grok's report, in safe characters, else unknown.
grok_model() {
  local model
  model=$(jq -r 'if (.modelUsage | type) == "object" and (.modelUsage | length) > 0 then (.modelUsage | keys | join(", ")) else "unknown" end' "$out" 2>/dev/null | tr -cd 'A-Za-z0-9._, -') || model=unknown
  printf '%s\n' "${model:-unknown}"
}

# What Grok is started with besides PATH, HOME, GROK_HOME, TMPDIR and LANG: it
# switches off what the user's other tools and the network would otherwise add. Shared
# by the run (grok_exec) and the sign-in refresh (grok_refresh), so both see the same.
GROK_RUN_ENV=(GROK_MEMORY=0 GROK_TELEMETRY_ENABLED=0 GROK_TELEMETRY_TRACE_UPLOAD=0 GROK_EXTERNAL_OTEL=0 GROK_DISABLE_AUTOUPDATER=1
  GROK_CLAUDE_AGENTS_ENABLED=false GROK_CLAUDE_HOOKS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false GROK_CLAUDE_RULES_ENABLED=false GROK_CLAUDE_SKILLS_ENABLED=false
  GROK_CURSOR_AGENTS_ENABLED=false GROK_CURSOR_HOOKS_ENABLED=false GROK_CURSOR_MCPS_ENABLED=false GROK_CURSOR_RULES_ENABLED=false GROK_CURSOR_SKILLS_ENABLED=false)

# The offline part of the sign-in check: sets the caller's real_grok, the user's Grok
# home, and returns 1, with adapter_why set, unless its auth.json holds a sign-in: one
# JSON object holding a non-empty string at some depth (an empty file, {}, "" or
# {"token":""} is none). A key in the environment is the metered API and is not used.
# Nothing from the file is printed.
grok_signed_in() {
  if ! real_grok=$(realdir "${GROK_HOME:-$HOME/.grok}") || [ ! -f "$real_grok/auth.json" ]; then
    adapter_why="Grok is not signed in: there is no auth.json in its home (run grok login)"
    return 1
  fi
  jq -se 'length == 1 and (.[0] | type == "object") and ([.[0] | .. | strings | select(length > 0)] | length > 0)' \
    "$real_grok/auth.json" >/dev/null 2>&1 && return 0
  adapter_why="Grok is not signed in: its auth.json holds no sign-in (run grok login)"
  return 1
}

# Grok runs on the user's own sign-in, checked again here, then for its expiry: the check
# refuses a sign-in that would expire during the run, counting from now to the end of the
# time limit plus 5 minutes for the setup that comes before Grok starts (the run folder,
# the export, the prompt and Grok's home), because Grok cannot refresh it there (the run
# home is read-only to Grok's own process except vendor): it parks on a credential-less
# 401 until the time limit. Before refusing, it lets Grok refresh the sign-in where Grok
# can (grok_refresh), once, and looks again. A missing or unfamiliar expires_at is
# unknown, not expired, and is not refreshed. Nothing from the file but the timestamp is
# printed. Each refusal is raised every time (always). Reads the caller's grok_bin.
grok_signin() {
  local expiry now ends
  grok_signed_in || adapter_fail "$adapter_why" "" always
  grok_expiry
  if [ -n "$expiry" ] && { [[ "${expiry:0:19}" < "$now" ]] || [[ "${expiry:0:19}" < "$ends" ]]; }; then
    grok_refresh
    grok_expiry
    [ -n "$expiry" ] ||
      adapter_fail "Grok's sign-in could not be read after Mentat tried to refresh it; run grok login or any grok prompt outside Mentat, then retry" "" always
  fi
  [ -n "$expiry" ] || return 0
  if [[ "${expiry:0:19}" < "$now" ]]; then
    adapter_fail "Grok's sign-in expired at ${expiry:0:19}Z; run grok login or any grok prompt outside Mentat, then retry" "" always
  fi
  if [[ "${expiry:0:19}" < "$ends" ]]; then
    adapter_fail "Grok's sign-in expires at ${expiry:0:19}Z, before this run's ${REVIEW_TIMEOUT_SECONDS}-second time limit and 5 minutes of setup would end; run grok login or any grok prompt outside Mentat, then retry" "" always
  fi
}

# Reads the sign-in's expiry and the clock into the caller's expiry (empty unless it is
# in the recognized form), now, and ends (now plus the time limit and 5 minutes).
grok_expiry() {
  expiry=$(jq -r '[.. | objects | .expires_at? | strings] | max // empty' "$real_grok/auth.json" 2>/dev/null) || expiry=""
  case "$expiry" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*Z) ;; *) expiry="" ;; esac
  now=$(date -u +%Y-%m-%dT%H:%M:%S)
  ends=$(date -u -v+$((REVIEW_TIMEOUT_SECONDS + 300))S +%Y-%m-%dT%H:%M:%S 2>/dev/null)
}

# Lets Grok refresh the sign-in: `grok models` lists the models and exits, with no
# prompt and no tools, and renews the access token with the refresh token on the way.
# It runs in the user's own Grok home, as the real Grok does outside Mentat, with the
# rebuilt environment of the run (the run's own folder does not exist yet).
# GROK_AUTH_EARLY_INVALIDATION_SECS, Grok's refresh buffer, is set to the time limit,
# the 5 minutes and a minute more, so a token that is still valid but too short for
# the run is renewed too. It has 30 seconds, and its exit status does not matter:
# grok_signin reads the file again and decides. Reads the caller's real_grok and grok_bin.
grok_refresh() {
  local pid secs=0
  (umask 077 && exec env -i PATH="$PATH" HOME="$HOME" GROK_HOME="$real_grok" TMPDIR="${TMPDIR:-/tmp}" LANG="${LANG:-en_US.UTF-8}" \
    GROK_AUTH_EARLY_INVALIDATION_SECS=$((REVIEW_TIMEOUT_SECONDS + 360)) "${GROK_RUN_ENV[@]}" \
    "$grok_bin" models) >/dev/null 2>&1 </dev/null &
  pid=$!
  # $SECONDS counts whole seconds, so the limit ends up to a second late, never early.
  secs=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - secs)) -gt 30 ]; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null
      break
    fi
    sleep 0.1
  done
  wait "$pid" 2>/dev/null || true
}

# The per-run folder and Grok's home inside it, checked against the folders the
# profile denies. $1 is the folder's name. Sets the caller's variables (cache, run,
# home_real, denied, tmpdir, roots, ghome, out, err, result_file).
grok_run_folder() {
  local d
  # The per-run folder holds everything Grok may read besides the system: the
  # export (its working directory), its home, the prompt and its temporary folder.
  # It is not under a temporary folder or ~/Library, which the profile denies, so
  # the cache folder is the default place. It goes when the runner exits.
  cache=${XDG_CACHE_HOME:-$HOME/.cache}
  case "$cache" in /*) ;; *) adapter_fail "XDG_CACHE_HOME is not an absolute path" "" none ;; esac
  mkdir -p "$cache/mentat" || adapter_fail "could not create Mentat's cache folder" "" none
  run=$(mktemp -d "$cache/mentat/$1.XXXXXX") || adapter_fail "could not create a folder in Mentat's cache folder" "" none
  # shellcheck disable=SC2064 # expand now, so the path is fixed when the trap is set
  trap "rm -rf $(printf %q "$run")" EXIT
  run=$(realdir "$run") || adapter_fail "could not resolve Grok's run folder" "" none
  home_real=$(realdir "$HOME") || home_real=$HOME
  denied=(/tmp /private/tmp /var/tmp /private/var/tmp /var/folders /private/var/folders "$home_real/Library" "$real_grok")
  if [ -n "${TMPDIR:-}" ] && tmpdir=$(realdir "$TMPDIR"); then denied+=("$tmpdir"); fi
  # `strict` also lets Grok read the system folders. Its tools have no use for them,
  # and they are denied to the tools below. A deny always beats an allow, so none of
  # these may contain the run folder, which holds the export the tools must read.
  roots=(/private /Library /etc /var /opt /Volumes /Applications /System /usr /bin /sbin /dev /tmp "$home_real/Library" "$real_grok")
  if [ -n "${tmpdir:-}" ]; then roots+=("$tmpdir"); fi
  for d in "${denied[@]}" "${roots[@]}"; do
    case "$run/" in "$d"/*) adapter_fail "Mentat's cache folder is inside a folder the Grok sandbox denies" "$cache is inside $d; set XDG_CACHE_HOME to a folder outside it" none ;; esac
  done
  # Grok's home has a name the pull request cannot know: a symlink in the export
  # such as `../home` would otherwise reach the sign-in around the permission rules.
  ghome=$(mktemp -d "$run/home.XXXXXX") || adapter_fail "could not create Grok's home" "" none
  mkdir "$run/export" "$run/in" "$run/tmp" "$ghome/vendor" "$ghome/sessions" || adapter_fail "could not create the Grok folders" "" none
  out="$run/out.json" err="$run/err.log" result_file="$run/review.md"
}

# A plain export of commit $head of the repository at $top into the per-run folder:
# no .git, and nothing from the working tree.
grok_export_head() {
  GIT_INDEX_FILE="$run/index" git -C "$top" -c core.sparseCheckout=false read-tree "$head" || adapter_fail "could not read the tree of $head" "" none
  GIT_INDEX_FILE="$run/index" git -C "$top" checkout-index -a -q --prefix="$run/export/" || adapter_fail "could not export $head" "" none
}

grok_home() {
  local d
  # Grok's home: the sign-in, a config, and the sandbox profile. The profile starts
  # from `strict` and denies what `strict` still lets through: the temporary
  # folders, ~/Library, the user's own Grok home, and the credential files named
  # below. The prompt folder is the one extra place it may read, and the
  # empty vendor folder in its home the one extra place it may write: Grok unpacks
  # its search program (ripgrep) there the first time it searches, and without it
  # the grep tool fails.
  (umask 077 && cp "$real_grok/auth.json" "$ghome/auth.json") || adapter_fail "could not copy Grok's sign-in" "" none
  printf '%s\n' '# Written by mentat.' '[features]' 'codebase_indexing = false' 'telemetry = false' >"$ghome/config.toml" ||
    adapter_fail "could not write Grok's config" "" none
  entries=""
  for d in "${denied[@]}" '**/.env' '**/.env.*' '**/*.pem' '**/*.key' '**/*.p12' '**/*.pfx' '**/id_rsa*' '**/id_ecdsa*' '**/id_ed25519*' '**/.netrc' '**/.npmrc' '**/.pypirc'; do
    entries="$entries$(toml_string "$d"), "
  done
  {
    printf '[profiles.%s]\nextends = "strict"\n' "$GROK_PROFILE"
    printf 'read_only = [%s]\nread_write = [%s]\n' "$(toml_string "$run/in")" "$(toml_string "$ghome/vendor")"
    printf 'deny = [%s]\n' "${entries%, }"
  } >"$ghome/sandbox.toml" || adapter_fail "could not write Grok's sandbox profile" "" none
}

# Builds the arguments of the Grok run into the caller's array args.
grok_args() {
  local d
  # Reading this pull request's own files is the job. Grok's home holds the sign-in
  # and the kernel must let Grok read it, so its tools are kept out of it by
  # permission rules. Each rule names a folder as a path (a search or listing of the
  # folder itself) and as everything under it, for both Grok homes and the system
  # folders above. Rules follow symlinks to their target, and a deny beats an allow,
  # so the export and the prompt are what the tools can still reach; the kernel
  # profile keeps the rest of the user's folders out of reach. The debug file is the
  # record of a run that never finishes (the JSON arrives only at the end): it goes
  # in the sessions folder, which Grok may write and its tools may not read.
  # Web search is a backend search on xAI's side, on only for a second opinion (the
  # caller's web_search); the local fetch tool is denied in every path and web_fetch
  # is never in the allowlist. A review has no web at all.
  local tools="read_file,grep,list_dir" search=(--disable-web-search)
  if [ -n "${web_search:-}" ]; then tools="$tools,web_search" search=(); fi
  args=(--cwd "$run/export" --prompt-file "$run/in/prompt" --output-format json
    --tools "$tools" --disallowed-tools "Agent,run_terminal_command,run_terminal_cmd"
    --deny MCPTool --deny WebFetch --debug-file "$ghome/sessions/debug.log"
    --no-subagents --no-plan --no-leader --no-memory --no-auto-update ${search[@]+"${search[@]}"}
    --permission-mode dontAsk --max-turns 60 --sandbox "$GROK_PROFILE")
  for d in "$ghome" "${roots[@]}"; do
    args+=(--deny "Read($d)" --deny "Read($d/**)" --deny "Grep($d)" --deny "Grep($d/**)")
  done
  # The folders above the export are denied as paths only (a listing of the folder
  # itself, which shows the folders below it), never as trees: the export is below them.
  d="$run/export"
  while [ "$d" != / ]; do
    d=$(dirname "$d")
    args+=(--deny "Read($d)" --deny "Grep($d)")
  done
  args+=(--reasoning-effort "$GROK_REASONING_EFFORT")
}

# Keeps a copy of Grok's raw log for the maintainer and sets the caller's kept to
# its path (empty when there was nothing to keep). The log may hold a credential, so
# only its path is printed, never the log, and nothing of it is posted.
grok_keep_log() {
  kept=""
  if [ -e "$err" ]; then
    if kept=$(mktemp "${TMPDIR:-/tmp}/mentat-log.grok.XXXXXX") && { cat "$err" "$out"; cat "$ghome/sessions/debug.log" 2>/dev/null; true; } >"$kept" 2>/dev/null; then :; else kept=""; fi
  fi
}

# Once Grok has run, a failure of Grok's own keeps a copy of its log for the maintainer
# and counts in its failures in a row ($2: empty, or usage).
grok_failed() { # $1 public reason, $2 kind
  grok_keep_log
  adapter_fail "$1" "${kept:+its log may hold credentials, so it is not printed. The maintainer can read it at $kept}" "${2:-}"
}

# Runs Grok in the rebuilt environment under the time limit, and fails unless it exits 0.
# Reads the caller's run, out, err, ghome, grok_bin and args.
grok_exec() {
  # The environment is rebuilt for Grok alone: nothing else of the agent's reaches it.
  (cd "$run/export" && exec env -i PATH="$PATH" HOME="$HOME" GROK_HOME="$ghome" TMPDIR="$run/tmp" LANG="${LANG:-en_US.UTF-8}" \
    "${GROK_RUN_ENV[@]}" "$grok_bin" "${args[@]}") >"$out" 2>"$err" </dev/null &
  grok_keep_log_on_timeout "$!"
  [ "$adapter_rc" -eq 0 ] || grok_run_failed "Grok exited with status $adapter_rc"
}
# adapter_wait, with Grok's log kept when the time limit stops it.
grok_keep_log_on_timeout() { # $1 pid
  local secs=$SECONDS
  while kill -0 "$1" 2>/dev/null; do
    if [ $((SECONDS - secs)) -gt "$REVIEW_TIMEOUT_SECONDS" ]; then
      kill "$1" 2>/dev/null
      sleep 2
      kill -9 "$1" 2>/dev/null
      wait "$1" 2>/dev/null
      grok_failed "Grok did not finish within $REVIEW_TIMEOUT_SECONDS seconds"
    fi
    sleep 0.1
  done
  wait "$1"
  adapter_rc=$?
}

# Grok refusing a run for usage or billing, in Mentat's own words: no text from the run.
GROK_OUT_OF_USAGE="Grok refused this run for usage or billing; the maintainer can top up or wait for the usage limit to reset, and reviews and second opinions go on without Grok"
# A Grok run that failed (it exited non-zero, or returned no complete reply): fails with
# GROK_OUT_OF_USAGE, counted as usage, when the message of an error object in Grok's JSON
# output names an out-of-usage or billing refusal, else with $1. Only that message is
# read, never Grok's stderr, its debug log or the rest of its output, which can hold the
# prompt or diff; output that is not JSON has no such message.
grok_run_failed() {
  if jq -s -e 'any(.[]; type == "object" and .type == "error" and (.message | type) == "string" and
      (.message | test("status 402|payment required|run out of credits|hit your weekly limit|hit your free usage limit|usage balance exhausted"; "i")))' \
      "$out" >/dev/null 2>&1; then
    grok_failed "$GROK_OUT_OF_USAGE" usage
  fi
  grok_failed "$1"
}

# Reads Grok's reply from $out into $result_file, and fails unless it is a complete
# reply: exactly one JSON object that ended its turn with a non-empty text. Anything
# else, including a stop reason this does not know, is not a reply.
grok_reply() {
  local stop
  stop=$(jq -s -r 'if length == 1 and (.[0] | type) == "object" then (.[0].stopReason // "none" | tostring) else "none" end' "$out" 2>/dev/null | tr -cd 'A-Za-z0-9_-' | head -c 40)
  if ! jq -s -e 'length == 1 and (.[0] | type) == "object" and .[0].stopReason == "end_turn" and (.[0].text | type) == "string" and (.[0].text | test("\\S"))' "$out" >/dev/null 2>&1; then
    grok_run_failed "Grok did not return a complete reply (stop reason: ${stop:-none})"
  fi
  jq -r '.text' "$out" >"$result_file" || grok_failed "could not read Grok's reply"
}
