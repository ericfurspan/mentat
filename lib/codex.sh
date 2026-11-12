# shellcheck shell=bash
# The Codex side of mentat: the Codex sandbox profile, run_codex and the local
# review. Sourced by bin/mentat.

# Codex runs its own default model, so no model name lives here and a new release
# needs no change. Effort is pinned.
CODEX_EFFORT="high"
REVIEW_TIMEOUT_SECONDS="${MENTAT_REVIEW_TIMEOUT_SECONDS:-1200}"

# Prints the inline TOML table of Codex's filesystem permissions for a review of
# directory $1: the checkout, its git directory (outside the checkout for a
# worktree), the system paths, /opt/homebrew, /usr/local and the install prefixes
# in $2, one per line, so Codex can start.
codex_filesystem() {
  local gitdir p table='":minimal"="read", "/opt/homebrew"="read", "/usr/local"="read"'
  gitdir=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || gitdir=""
  [ -z "$gitdir" ] || table="$table, \"$gitdir\"=\"read\""
  while IFS= read -r p; do
    # Codex rejects a repeated key.
    case "$table" in *"\"$p\"="*) continue ;; esac
    [ -z "$p" ] || table="$table, \"$p\"=\"read\""
  done <<<"${2:-}"
  printf '{%s, "/tmp"="deny", "/private/tmp"="deny", "/var/tmp"="deny", "/private/var/tmp"="deny", ":workspace_roots"={"."="read", %s}}' "$table" "$CREDENTIAL_DENY"
}
# Files inside the checkout that commonly hold credentials, denied to Codex even
# though the rest of the checkout is readable. Glob denies are pre-expanded to
# GLOB_DEPTH levels before Codex starts. Example files such as .env.example are
# denied too; a review that needs one says it could not read it. A committed file
# stays readable through the git directory; a committed credential is exposed anyway.
CREDENTIAL_DENY='"**/.env"="deny", "**/.env.*"="deny", "**/*.pem"="deny", "**/*.key"="deny", "**/*.p12"="deny", "**/*.pfx"="deny", "**/id_rsa*"="deny", "**/id_ecdsa*"="deny", "**/id_ed25519*"="deny", "**/.netrc"="deny", "**/.npmrc"="deny", "**/.pypirc"="deny"'
GLOB_DEPTH=8

# Prints file $1 with every symlink resolved.
real_file() {
  local f="$1" l n=0
  while [ -L "$f" ]; do
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
    l=$(readlink "$f") || return 1
    case "$l" in /*) f=$l ;; *) f="${f%/*}/$l" ;; esac
  done
  l=$(cd -P "${f%/*}/" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "${l%/}" "${f##*/}"
}

# Prints the install prefix of the program at real path $1: the folder holding
# lib/node_modules for an npm package, else the parent of the bin folder holding it.
install_prefix() {
  local p
  case "$1" in
    */lib/node_modules/*) p="${1%%/lib/node_modules/*}" ;;
    *)
      p="${1%/*}"
      [ "${p##*/}" = bin ] || return 1
      p="${p%/bin}"
      ;;
  esac
  printf '%s\n' "${p:-/}"
}

# Sets the caller's prefixes to the install prefixes Codex needs, one per line:
# codex's and, for a script run by node, node's. One that cannot be resolved is left
# out. Calls $1 with the reason, which exits, when one is /, the home folder, in it
# or holds it.
codex_prefixes() {
  local fail="$1" home f p first name who
  prefixes=""
  home=$(cd -P "$HOME" 2>/dev/null && pwd -P) || "$fail" "the home folder cannot be resolved, so the Codex profile cannot keep it out"
  for name in codex node; do
    if [ "$name" = codex ]; then
      who="Codex is"
    else
      first=$(head -c 256 "$f" 2>/dev/null | tr -d '\000' | head -n 1)
      case "$first" in '#!'*node*) who="node, which runs Codex, is" ;; *) return 0 ;; esac
    fi
    f=$(command -v "$name") && f=$(real_file "$f") || return 0
    p=$(install_prefix "$f") || continue
    who="$who installed in or above the home folder, which the Codex profile never grants"
    # Inside the home folder, then the home folder or one holding it, / included.
    case "$p/" in "$home"/*) "$fail" "$who" ;; esac
    case "$home/" in "${p%/}"/*) "$fail" "$who" ;; esac
    prefixes="$prefixes$p
"
  done
}

# Runs Codex in directory $1 on prompt file $2 and writes its final message to $3.
# On any failure it calls $4 with the reason, which exits. $5 is Codex's web
# search mode: "disabled" for reviews, which judge the diff; "cached" (OpenAI's
# index, no live fetches) for a second opinion on an idea, which checks current
# practice; "live" for a second opinion with --web, which asks any question. Search
# runs on OpenAI's side, outside the permissions profile below. $6 is optional:
# "outside" adds --skip-git-repo-check, for the --web mode, which runs in an empty folder that is not a repository (Codex refuses
# to start there otherwise). Every other caller passes nothing.
run_codex() {
  local dir="$1" prompt="$2" out="$3" fail="$4" search="$5" log rc secs=0 pid kept filesystem prefixes outside=()
  if [ "${6:-}" = outside ]; then outside=(--skip-git-repo-check); fi
  log="${out%/*}/codex.log"
  codex_prefixes "$fail"
  filesystem=$(codex_filesystem "$dir" "$prefixes")
  # Plain `codex exec`, not `codex exec review`: review mode forces a JSON-only
  # final reply, so it cannot end with the status line the callers check.
  # A permissions profile replaces `--sandbox read-only`, which reads the whole disk
  # and overrides a profile. Mentat passes it because --ignore-user-config skips
  # the user's own. --strict-config makes unknown settings fail instead of being
  # ignored, so a Codex without profiles fails closed. The profile denies
  # ~/.gitconfig, so git runs without one.
  # Codex's shell gets only core environment variables, so tokens in the agent's
  # environment do not reach it.
  # features.apps=false: the apps feature (the ChatGPT account's GitHub connector) is
  # on by default and --ignore-user-config does not turn it off, so Codex could read
  # GitHub beyond the change.
  (cd "$dir" && exec codex exec --ephemeral --ignore-user-config --strict-config ${outside[@]+"${outside[@]}"} \
    -c 'default_permissions="mentat-review"' -c "permissions.mentat-review.filesystem=$filesystem" \
    -c "permissions.mentat-review.filesystem.glob_scan_max_depth=$GLOB_DEPTH" \
    -c 'features.apps=false' -c 'shell_environment_policy.inherit="core"' -c 'shell_environment_policy.set={GIT_CONFIG_GLOBAL="/dev/null"}' \
    -c "model_reasoning_effort=\"$CODEX_EFFORT\"" \
    -c 'approval_policy="never"' -c "web_search=\"$search\"" -o "$out" - <"$prompt") >"$log" 2>&1 &
  pid=$!
  # $SECONDS counts whole seconds, so a limit stops Codex up to a second late, never early.
  secs=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$REVIEW_TIMEOUT_SECONDS" -eq 0 ] || [ $((SECONDS - secs)) -gt "$REVIEW_TIMEOUT_SECONDS" ]; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null
      "$fail" "Codex did not finish within $REVIEW_TIMEOUT_SECONDS seconds"
    fi
    sleep 0.1
  done
  wait "$pid"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # The log is Codex's raw output and may hold a credential, so it is not
    # printed into the agent's session. A copy is kept for the maintainer.
    kept=$(mktemp "${TMPDIR:-/tmp}/mentat-codex-log.XXXXXX") && cp "$log" "$kept"
    "$fail" "codex exited with status $rc; its log may hold credentials, so it is not printed. The maintainer can read it at $kept"
  fi
  [ -s "$out" ] || "$fail" "Codex returned no final message"
}

# A local review reads the pull request's head as GitHub has it, never this
# checkout's working tree: it fetches that commit, reviews it in a temporary
# worktree, then waits for CI on that commit, and posts the result only once CI
# passed there and the head has not moved since.
review_local() {
  local pr="${1:-}" repo info head base title body top tmp mb fetched now issues request request_fp headref baseref
  case "$pr" in '' | *[!0-9]*) die "usage: mentat review [--local | --grok [--stop]] [--request <file>] [--require-ci] <pull request number>" 64 ;; esac
  read_request "$pr"
  local tool
  for tool in git codex; do
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
  # origin/<base> tracking ref: the review skill runs a Codex and a Grok review at once
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

  {
    printf 'Review pull request #%s. The working directory is a checkout of its head, commit %s. ' "$pr" "$head"
    printf 'Review the change from %s to %s (run: git diff %s %s). Do not modify files.\n\n' "$mb" "$head" "$mb" "$head"
    review_criteria ""
    review_requirements "$issues" "$title" "$body" "$request"
    review_result_line
  } >"$tmp/prompt" || not_reviewed "could not write the prompt"

  local out="$tmp/review.md" result url held
  run_codex "$tmp/tree" "$tmp/prompt" "$out" not_reviewed disabled
  localize_review_paths "$out" "$repo" "$head" "$tmp/tree" || not_reviewed "could not rewrite the paths in Codex's reply"
  result=$(last_line "$out")
  case "$result" in
    "REVIEW RESULT: NO FINDINGS" | "REVIEW RESULT: FINDINGS" | "REVIEW RESULT: INCOMPLETE - "*[![:space:]]*) ;;
    *) not_reviewed "Codex's reply has no final REVIEW RESULT line" ;;
  esac
  # The review ran without waiting for CI; it is posted only once CI passes on the same head.
  wait_for_ci "$repo" "$head" "$out" "$pr" "mentat review"
  now=$(gh pr view "$pr" --json headRefOid --jq .headRefOid) || not_reviewed "could not read pull request #$pr"
  [ "$now" = "$head" ] || die "the head moved from $head; run mentat review again" 3
  {
    printf '## Local Codex review of %s: %s, spec fingerprint %s\n\n' "$head" "$(result_word "$result")" "$request_fp"
    printf '<details><summary>Full review</summary>\n\n'
    printf -- '- Change reviewed: %s..%s\n' "$mb" "$head"
    printf -- '- Agreed request fingerprint: %s\n' "$request_fp"
    printf -- '- Codex CLI: %s\n- Model: %s, reasoning effort %s\n- Time: %s\n' \
      "$(codex --version 2>/dev/null)" "Codex default model" "$CODEX_EFFORT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf -- '\n---\n\n'
    cat "$out"
    printf '\n</details>\n\n%s\n' "$result"
  } >"$tmp/comment" || not_reviewed "could not write the comment"
  if held=$(held_comment "$(cat "$tmp/comment")" "$repo"); then not_reviewed "$held"; fi
  url=$(gh pr comment "$pr" --body-file "$tmp/comment") || not_reviewed "could not post the review on #$pr"
  # An incomplete review is posted, so its reason is on the pull request, and is not a review.
  case "$result" in "REVIEW RESULT: INCOMPLETE - "*) not_reviewed "Codex says the review is incomplete: ${result#"REVIEW RESULT: INCOMPLETE - "}" ;; esac
  if [ "$result" = "REVIEW RESULT: NO FINDINGS" ]; then
    printf 'The local Codex review found nothing on %s: %s\n' "$head" "$url"
    exit 0
  fi
  printf 'The local Codex review posted findings on %s: %s\n' "$head" "$url"
  exit 2
}
