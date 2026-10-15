# shellcheck shell=bash
# The Grok side of mentat: review --grok and the Grok run shared with weigh, with
# its sandbox profile and its isolated home. Sourced by bin/mentat.

# A Grok review (`mentat review --grok`) runs beside the Codex review, once per
# pull request. Grok gets read-only file tools and no shell, a plain export of the
# head without git history, and the diff inside its prompt. It runs as the user's
# Grok sign-in, in a home folder Mentat builds for it, inside Grok's own sandbox
# (a custom profile built on `strict`), which fails closed: if the profile cannot
# be applied, Grok refuses to start. The profile and the permission rules are
# built from where things are at run time, in the per-run folder below. Nothing in
# the user's Grok home but auth.json is copied: no config, MCP servers, hooks or
# keys. A sign-in whose access token is past its expiry is refused before the copy,
# since Grok cannot refresh it inside the run.
#
# `mentat weigh` runs Grok the same way on an idea, with no pull request, except that
# it may use Grok's backend web search (the local fetch tool stays denied).
# `mentat consult` runs it on any question with web search alone: no file tools and
# an empty export. The functions below that they share (grok_signin, grok_run_folder,
# grok_export_head, grok_home, grok_args, grok_exec, grok_reply) report a failure by calling the caller's
# function named in `fail`: not_reviewed before a review's start comment, grok_fail
# after it. The pull-request steps (reading it, the start comment, the diff prompt,
# the did-not-finish comment and posting) stay in review_grok's own functions.
# Convention: these functions set the caller's variables by name and never return
# values; that keeps the pull-request path and the weigh path on one set of steps
# without passing a dozen arguments. A reader tracing a variable should start from
# review_grok, weigh_grok and consult_grok, which declare them.
GROK_PROFILE="mentat-review"
# Grok has its own timeout: a review has taken up to 19 minutes, and its JSON
# arrives only at the end.
GROK_TIMEOUT_SECONDS="${MENTAT_GROK_TIMEOUT_SECONDS:-1800}"
# Empty leaves Grok's own default; otherwise passed as --reasoning-effort (the value is not checked).
GROK_REASONING_EFFORT="${MENTAT_GROK_REASONING_EFFORT:-}"
realdir() { (cd -P "$1" 2>/dev/null && pwd -P); }
toml_string() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
# Grok reviews a pull request once. Only this account's own start comment counts:
# anyone who can comment could otherwise post the text and keep Grok from running.
grok_not_started() { # $1 repo, $2 pull request, $3 this account's login
  local n
  n=$(gh api --paginate "repos/$1/issues/$2/comments" | jq -rs --arg me "$3" \
    '[.[][] | select(.user.login == $me and (.body | startswith("Grok review started on ")))] | length') ||
    not_reviewed "could not read the comments on #$2"
  [ "$n" = 0 ] || not_reviewed "Grok already reviewed #$2 (its start comment is on the pull request); it runs once per pull request"
}

# Reads the pull request and everything the review needs from GitHub and git, and
# stops with "not reviewed" when something is missing. Sets the caller's variables
# (top, info, head, base, repo, me, title, body, issues, mb, grok_bin, real_grok).
grok_prepare() {
  local tool fetched
  for tool in git gh jq grok; do
    command -v "$tool" >/dev/null 2>&1 || not_reviewed "$tool is not installed"
  done
  grok_bin=$(command -v grok)
  top=$(git rev-parse --show-toplevel) || not_reviewed "not inside a git repository"
  info=$(gh pr view "$pr" --json headRefOid,baseRefName,title,body,closingIssuesReferences) || not_reviewed "could not read pull request #$pr"
  head=$(jq -r '.headRefOid // empty' <<<"$info")
  base=$(jq -r '.baseRefName // empty' <<<"$info")
  { [ -n "$head" ] && [ -n "$base" ]; } || not_reviewed "could not read pull request #$pr"
  if ! repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || [ -z "$repo" ]; then
    not_reviewed "could not read the repository with gh"
  fi
  me=$(gh api user --jq .login) && [ -n "$me" ] || not_reviewed "could not read which GitHub account gh is signed in as"
  grok_not_started "$repo" "$pr" "$me"
  wait_for_ci "$repo" "$head"
  title=$(jq -r '.title // ""' <<<"$info")
  body=$(jq -r '.body // ""' <<<"$info")
  read_issues "$pr" "$info"
  git -C "$top" fetch -q origin "pull/$pr/head" || not_reviewed "could not fetch pull request #$pr"
  fetched=$(git -C "$top" rev-parse FETCH_HEAD) || not_reviewed "could not read the fetched head"
  [ "$fetched" = "$head" ] || die "the head moved from $head; run mentat review again" 3
  git -C "$top" fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" || not_reviewed "could not fetch $base"
  mb=$(git -C "$top" merge-base "$head" "refs/remotes/origin/$base") || not_reviewed "could not find where #$pr branches from $base"
  grok_signin
}

# Grok runs on the user's own sign-in. A key in the environment is the metered API
# and is not used. Sets the caller's real_grok, the user's Grok home.
#
# The check refuses a sign-in that would expire during the run, because Grok cannot
# refresh it there (the run home is read-only to Grok's own process except vendor):
# it parks on a credential-less 401 until the time limit. A missing or unfamiliar
# expires_at is unknown, not expired, and nothing from the file but the timestamp is
# printed. Every sign-in refusal here starts with "Grok's sign-in" or "Grok is not
# signed in", so that the skills can tell it from other failures.
grok_signin() {
  local expiry now ends
  real_grok=$(realdir "${GROK_HOME:-$HOME/.grok}") && [ -f "$real_grok/auth.json" ] ||
    "$fail" "Grok is not signed in: there is no auth.json in its home (run grok login)"
  expiry=$(jq -r '[.. | objects | .expires_at? | strings] | max // empty' "$real_grok/auth.json" 2>/dev/null) || expiry=""
  case "$expiry" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*Z) ;; *) expiry="" ;; esac
  now=$(date -u +%Y-%m-%dT%H:%M:%S)
  if [ -n "$expiry" ] && [[ "${expiry:0:19}" < "$now" ]]; then
    "$fail" "Grok's sign-in expired at ${expiry:0:19}Z; run grok login or any grok prompt outside Mentat, then retry"
  fi
  if [ -n "$expiry" ]; then
    ends=$(date -u -v+"${GROK_TIMEOUT_SECONDS}"S +%Y-%m-%dT%H:%M:%S 2>/dev/null) ||
      "$fail" "could not work out when Grok's time limit ends (MENTAT_GROK_TIMEOUT_SECONDS is $GROK_TIMEOUT_SECONDS)"
    if [[ "${expiry:0:19}" < "$ends" ]]; then
      "$fail" "Grok's sign-in expires at ${expiry:0:19}Z, before this run's ${GROK_TIMEOUT_SECONDS}-second time limit would end; run grok login or any grok prompt outside Mentat, then retry"
    fi
  fi
}

# The per-run folder and Grok's home inside it, checked against the folders the
# profile denies. $1 is the folder's name (default grok-review). Sets the caller's
# variables (cache, run, home_real, denied, tmpdir, roots, ghome, out, err,
# result_file).
grok_run_folder() {
  local d
  # The per-run folder holds everything Grok may read besides the system: the
  # export (its working directory), its home, the prompt and its temporary folder.
  # It is not under a temporary folder or ~/Library, which the profile denies, so
  # the cache folder is the default place. It goes at exit.
  cache=${XDG_CACHE_HOME:-$HOME/.cache}
  case "$cache" in /*) ;; *) "$fail" "XDG_CACHE_HOME is not an absolute path" ;; esac
  mkdir -p "$cache/mentat" || "$fail" "could not create $cache/mentat"
  run=$(mktemp -d "$cache/mentat/${1:-grok-review}.XXXXXX") || "$fail" "could not create a folder under $cache/mentat"
  # shellcheck disable=SC2064 # expand now, so the path is fixed when the trap is set
  trap "rm -rf $(printf %q "$run")" EXIT
  run=$(realdir "$run") || "$fail" "could not resolve $run"
  home_real=$(realdir "$HOME") || home_real=$HOME
  denied=(/tmp /private/tmp /var/tmp /private/var/tmp /var/folders /private/var/folders "$home_real/Library" "$real_grok")
  if [ -n "${TMPDIR:-}" ] && tmpdir=$(realdir "$TMPDIR"); then denied+=("$tmpdir"); fi
  # `strict` also lets Grok read the system folders. Its tools have no use for them,
  # and they are denied to the tools below. A deny always beats an allow, so none of
  # these may contain the run folder, which holds the export the tools must read.
  roots=(/private /Library /etc /var /opt /Volumes /Applications /System /usr /bin /sbin /dev /tmp "$home_real/Library" "$real_grok")
  if [ -n "${tmpdir:-}" ]; then roots+=("$tmpdir"); fi
  for d in "${denied[@]}" "${roots[@]}"; do
    case "$run/" in "$d"/*) "$fail" "$cache is inside $d, which the Grok review denies; set XDG_CACHE_HOME to a folder outside it" ;; esac
  done
  # Grok's home has a name the pull request cannot know: a symlink in the export
  # such as `../home` would otherwise reach the sign-in around the permission rules.
  ghome=$(mktemp -d "$run/home.XXXXXX") || "$fail" "could not create Grok's home"
  mkdir "$run/export" "$run/in" "$run/tmp" "$ghome/vendor" "$ghome/sessions" || "$fail" "could not create the Grok folders"
  out="$run/out.json" err="$run/err.log" result_file="$run/review.md"
}

# A plain export of commit $head of the repository at $top into the per-run folder:
# no .git, and nothing from the working tree.
grok_export_head() {
  GIT_INDEX_FILE="$run/index" git -C "$top" -c core.sparseCheckout=false read-tree "$head" || "$fail" "could not read the tree of $head"
  GIT_INDEX_FILE="$run/index" git -C "$top" checkout-index -a -q --prefix="$run/export/" || "$fail" "could not export $head"
}

# The review's diff and prompt, in the per-run folder.
grok_pr_prompt() {
  git -C "$top" diff --no-ext-diff --no-textconv --no-color "$mb" "$head" >"$run/diff" || not_reviewed "could not diff $mb..$head"
  {
    printf 'Review pull request #%s. The working directory is a plain export of its head, commit %s, without git history, and you have no shell. ' "$pr" "$head"
    printf 'Review the change from %s to %s, which is the diff below; read the files around it with your file tools. Do not modify files.\n\n' "$mb" "$head"
    review_criteria " and the diff"
    review_requirements "$issues" "$title" "$body"
    printf -- '--- BEGIN DIFF DATA ---\n'
    cat "$run/diff"
    printf -- '\n--- END DIFF DATA ---\n\n'
    review_result_line
  } >"$run/in/prompt" || not_reviewed "could not write the prompt"
}

grok_home() {
  local d
  # Grok's home: the sign-in, a config, and the sandbox profile. The profile starts
  # from `strict` and denies what `strict` still lets through: the temporary
  # folders, ~/Library, the user's own Grok home, and the credential files Codex's
  # profile denies. The prompt folder is the one extra place it may read, and the
  # empty vendor folder in its home the one extra place it may write: Grok unpacks
  # its search program (ripgrep) there the first time it searches, and without it
  # the grep tool fails.
  (umask 077 && cp "$real_grok/auth.json" "$ghome/auth.json") || "$fail" "could not copy Grok's sign-in"
  printf '%s\n' '# Written by mentat.' '[features]' 'codebase_indexing = false' 'telemetry = false' >"$ghome/config.toml" ||
    "$fail" "could not write Grok's config"
  entries=""
  for d in "${denied[@]}" '**/.env' '**/.env.*' '**/*.pem' '**/*.key' '**/*.p12' '**/*.pfx' '**/id_rsa*' '**/id_ecdsa*' '**/id_ed25519*' '**/.netrc' '**/.npmrc' '**/.pypirc'; do
    entries="$entries$(toml_string "$d"), "
  done
  {
    printf '[profiles.%s]\nextends = "strict"\n' "$GROK_PROFILE"
    printf 'read_only = [%s]\nread_write = [%s]\n' "$(toml_string "$run/in")" "$(toml_string "$ghome/vendor")"
    printf 'deny = [%s]\n' "${entries%, }"
  } >"$ghome/sandbox.toml" || "$fail" "could not write Grok's sandbox profile"
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
  # Web search is a backend search on xAI's side, on only for weigh and consult (the
  # caller's web_search); the local fetch tool is denied in every path and web_fetch
  # is never in the allowlist. A review has no web at all. The file tools come from
  # the caller's grok_tools; review and weigh set nothing and get the three file
  # tools. Consult sets grok_tools="" and web_search=1, so Grok gets web search alone.
  local tools="${grok_tools-read_file,grep,list_dir}" search=(--disable-web-search)
  if [ -n "${web_search:-}" ]; then tools="${tools:+$tools,}web_search" search=(); fi
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
  if [ -n "$GROK_REASONING_EFFORT" ]; then
    args+=(--reasoning-effort "$GROK_REASONING_EFFORT")
  fi
}

# Keeps a copy of Grok's raw log for the maintainer and sets the caller's kept to
# its path (empty when there was nothing to keep). The log may hold a credential, so
# callers name the path and never print the log. Reads the caller's err, out and
# ghome; err exists only once the run folder is built.
grok_keep_log() {
  kept=""
  if [ -e "$err" ]; then
    if kept=$(mktemp "${TMPDIR:-/tmp}/mentat-grok-log.XXXXXX") && { cat "$err" "$out"; cat "$ghome/sessions/debug.log" 2>/dev/null; true; } >"$kept" 2>/dev/null; then :; else kept=""; fi
  fi
}

# After the start comment, any failure says so on the pull request. The log is
# Grok's raw output and may hold a credential, so it is not printed or posted; a
# copy is kept for the maintainer. Reads the caller's pr, head, started, err, out
# and ghome.
grok_fail() {
  local kept
  grok_keep_log
  if [ "$started" = yes ]; then
    gh pr comment "$pr" --body "Grok review did not finish on $head: $1" >/dev/null || printf 'mentat: could not post that Grok did not finish\n' >&2
  fi
  not_reviewed "$1${kept:+; its log may hold credentials, so it is not printed. The maintainer can read it at $kept}"
}

# Runs Grok in the rebuilt environment under its time limit, and calls "$fail"
# unless it exits 0. Reads the caller's run, out, err, ghome, grok_bin and args.
grok_exec() {
  local pid secs=0 rc
  # The environment is rebuilt for Grok alone: nothing else of the agent's reaches it.
  (cd "$run/export" && exec env -i PATH="$PATH" HOME="$HOME" GROK_HOME="$ghome" TMPDIR="$run/tmp" LANG="${LANG:-en_US.UTF-8}" \
    GROK_MEMORY=0 GROK_TELEMETRY_ENABLED=0 GROK_TELEMETRY_TRACE_UPLOAD=0 GROK_EXTERNAL_OTEL=0 GROK_DISABLE_AUTOUPDATER=1 \
    GROK_CLAUDE_AGENTS_ENABLED=false GROK_CLAUDE_HOOKS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false GROK_CLAUDE_RULES_ENABLED=false GROK_CLAUDE_SKILLS_ENABLED=false \
    GROK_CURSOR_AGENTS_ENABLED=false GROK_CURSOR_HOOKS_ENABLED=false GROK_CURSOR_MCPS_ENABLED=false GROK_CURSOR_RULES_ENABLED=false GROK_CURSOR_SKILLS_ENABLED=false \
    "$grok_bin" "${args[@]}") >"$out" 2>"$err" </dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$secs" -ge "$GROK_TIMEOUT_SECONDS" ]; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null
      "$fail" "Grok did not finish within $GROK_TIMEOUT_SECONDS seconds"
    fi
    sleep 1
    secs=$((secs + 1))
  done
  wait "$pid"
  rc=$?
  [ "$rc" -eq 0 ] || "$fail" "Grok exited with status $rc"
}

# Posts the start record, then runs Grok.
grok_run() {
  # The start record comes after CI passed and the head matched, and is what keeps
  # the review loop from starting a second Grok review on this pull request. The
  # check is repeated here because a start comment may have appeared during the CI
  # wait (this narrows the window; it does not serialize two sessions).
  grok_not_started "$repo" "$pr" "$me"
  gh pr comment "$pr" --body "Grok review started on $head" >/dev/null || not_reviewed "could not post the start comment on #$pr"
  started=yes
  fail=grok_fail
  grok_exec
}

# Reads Grok's reply from $out into $result_file, and calls "$fail" unless it is a
# complete reply: exactly one JSON object that ended its turn with a non-empty
# text. Anything else, including a stop reason this does not know, is not a reply.
grok_reply() {
  local stop
  stop=$(jq -s -r 'if length == 1 and (.[0] | type) == "object" then (.[0].stopReason // "none" | tostring) else "none" end' "$out" 2>/dev/null | tr -cd 'A-Za-z0-9_-' | head -c 40)
  if ! jq -s -e 'length == 1 and (.[0] | type) == "object" and .[0].stopReason == "end_turn" and (.[0].text | type) == "string" and (.[0].text | test("\\S"))' "$out" >/dev/null 2>&1; then
    "$fail" "Grok did not return a complete review (stop reason: ${stop:-none})"
  fi
  jq -r '.text' "$out" >"$result_file" || "$fail" "could not read Grok's reply"
}

# Checks Grok's reply, posts it on the pull request and exits with the result. The
# review is posted for the commit Grok reviewed, even if the head has moved since:
# the start comment stops a rerun, so a review dropped here would be lost.
# A reply ending INCOMPLETE is a complete reply: it is posted like any other and
# then exits 1 as "not reviewed", with no did-not-finish comment or private log
# (grok_fail's), because the posted review is the record.
grok_post() {
  local result model url
  grok_reply
  result=$(last_line "$result_file")
  case "$result" in
    "REVIEW RESULT: NO FINDINGS" | "REVIEW RESULT: FINDINGS" | "REVIEW RESULT: INCOMPLETE - "*[![:space:]]*) ;;
    *) grok_fail "Grok's reply has no final REVIEW RESULT line" ;;
  esac
  model=$(jq -r 'if (.modelUsage | type) == "object" and (.modelUsage | length) > 0 then (.modelUsage | keys | join(", ")) else "unknown" end' "$out" 2>/dev/null | tr -cd 'A-Za-z0-9._, -') || model=unknown
  [ -n "$model" ] || model=unknown
  {
    printf '## Local Grok review of %s\n\n' "$head"
    printf -- '- Change reviewed: %s..%s\n' "$mb" "$head"
    printf -- '- Grok CLI: %s\n- Model: %s\n- Time: %s\n' "$("$grok_bin" --version 2>/dev/null | head -n 1)" "$model" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '- Run locally by the agent, with file-reading tools and no shell.\n\n---\n\n'
    cat "$result_file"
  } >"$run/comment" || grok_fail "could not write the comment"
  url=$(gh pr comment "$pr" --body-file "$run/comment") || grok_fail "could not post the review on #$pr"
  case "$result" in "REVIEW RESULT: INCOMPLETE - "*) not_reviewed "Grok says the review is incomplete: ${result#"REVIEW RESULT: INCOMPLETE - "}" ;; esac
  if [ "$result" = "REVIEW RESULT: NO FINDINGS" ]; then
    printf 'The local Grok review found nothing on %s: %s\n' "$head" "$url"
    exit 0
  fi
  printf 'The local Grok review posted findings on %s: %s\n' "$head" "$url"
  exit 2
}

review_grok() {
  local pr="${1:-}" repo info head base title body top mb issues grok_bin me
  local run="" started=no real_grok home_real tmpdir denied roots cache ghome
  local entries args=() out err result_file fail=not_reviewed
  # shellcheck disable=SC2034 # read by grok_args
  local web_search=""
  case "$pr" in '' | *[!0-9]*) die "usage: mentat review --grok <pull request number>" 64 ;; esac
  grok_prepare
  grok_run_folder
  grok_export_head
  grok_pr_prompt
  grok_home
  grok_args
  grok_run
  grok_post
}
