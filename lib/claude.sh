# shellcheck shell=bash
# shellcheck disable=SC2154 # root is set by bin/mentat; res, top and head are the caller's
# The Claude side of mentat: the review tools setting, the Claude model choice and
# the Claude runner for weigh, challenge and consult. Sourced by bin/mentat.

# The per-user setting, beside the private word list. `reviewers` lists the tools that
# run, any of claude, codex and grok; missing or empty means no setting. `claude-model`
# optionally names the Claude model.
REVIEWERS_FILE="$HOME/.config/mentat/reviewers"
CLAUDE_MODEL_FILE="$HOME/.config/mentat/claude-model"

# The Claude models, most capable first. Claude reviews with the first one in a
# family other than the builder's (prompts/builder.md).
CLAUDE_MODELS="claude-fable-5-1 claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5"

# Credential files inside the export, denied to Claude's file tools, as CREDENTIAL_DENY
# denies them to Codex. A Read rule also hides the matching files from Grep and Glob.
CLAUDE_CREDENTIAL_DENY=('Read(**/.env)' 'Read(**/.env.*)' 'Read(**/*.pem)' 'Read(**/*.key)' 'Read(**/*.p12)' 'Read(**/*.pfx)'
  'Read(**/id_rsa*)' 'Read(**/id_ecdsa*)' 'Read(**/id_ed25519*)' 'Read(**/.netrc)' 'Read(**/.npmrc)' 'Read(**/.pypirc)')

# Reads the setting into the caller's reviewers: the listed tools in the order codex,
# grok, claude, or empty with no setting. Returns 1, with the reason in the caller's
# reviewers_why, when the file cannot be read or holds another word.
reviewers_read() {
  local list bad flat t
  reviewers="" reviewers_why=""
  [ -e "$REVIEWERS_FILE" ] || return 0
  if ! list=$(tr -s '[:space:]' '\n' <"$REVIEWERS_FILE" 2>/dev/null); then
    reviewers_why="could not read the review tools setting ~/.config/mentat/reviewers"
    return 1
  fi
  bad=$(printf '%s\n' "$list" | grep -v -x -e '' -e claude -e codex -e grok)
  if [ -n "$bad" ]; then
    bad=$(printf '%s\n' "$bad" | head -n 1 | tr -cd 'A-Za-z0-9._-')
    reviewers_why="the review tools setting ~/.config/mentat/reviewers holds an unknown word${bad:+ ($bad)}; it may list only claude, codex and grok"
    return 1
  fi
  flat=" $(printf '%s\n' "$list" | tr '\n' ' ') "
  for t in codex grok claude; do
    case "$flat" in *" $t "*) reviewers="$reviewers $t" ;; esac
  done
  reviewers=${reviewers# }
}

# The tools mentat weigh and mentat consult run: the setting's, else Codex and Grok.
review_tools() {
  reviewers_read || die "$reviewers_why" 64
  tools=${reviewers:-codex grok}
}

claude_family() {
  case "$1" in
    *fable*) printf fable ;;
    *opus*) printf opus ;;
    *sonnet*) printf sonnet ;;
    *haiku*) printf haiku ;;
    *) printf '%s' "$1" ;;
  esac
}

# Sets the caller's claude_builder (the builder's model, from prompts/builder.md),
# claude_reviewer (the setting's model, else the first of CLAUDE_MODELS in another
# family) and claude_same (yes when both are in one family). Returns 1 when
# claude-model holds something that is not a model id.
claude_pick_model() {
  local m
  claude_builder=$(sed -n '2,/^---$/s/^model:[[:space:]]*//p' "$root/prompts/builder.md" 2>/dev/null | head -n 1 | tr -cd 'A-Za-z0-9._-')
  [ -n "$claude_builder" ] || claude_builder=unknown
  claude_reviewer=""
  if [ -e "$CLAUDE_MODEL_FILE" ]; then
    claude_reviewer=$(awk 'NF { print $1; exit }' "$CLAUDE_MODEL_FILE" 2>/dev/null) || return 1
    case "$claude_reviewer" in *[!A-Za-z0-9._-]*) return 1 ;; esac
  fi
  if [ -z "$claude_reviewer" ]; then
    for m in $CLAUDE_MODELS; do
      if [ "$(claude_family "$m")" != "$(claude_family "$claude_builder")" ]; then claude_reviewer=$m; break; fi
    done
  fi
  claude_same=no
  [ "$(claude_family "$claude_reviewer")" != "$(claude_family "$claude_builder")" ] || claude_same=yes
}

# A plain export of commit $2 of the repository at $1 into folder $3: no .git, and
# nothing from the working tree.
claude_export() {
  GIT_INDEX_FILE="$3.index" git -C "$1" -c core.sparseCheckout=false read-tree "$2" &&
    GIT_INDEX_FILE="$3.index" git -C "$1" checkout-index -a -q --prefix="$3/"
}

# Runs headless Claude in directory $1 on prompt file $2 and writes its reply, after
# a line naming the builder and reviewer models, to $3. On any failure it calls
# $4 with the reason, which exits. $5 is the tool list: "Read,Grep,Glob" for weigh
# and challenge, "WebSearch" for consult.
run_claude() {
  local dir="$1" prompt="$2" out="$3" fail="$4" tools="$5" bin log rc secs=0 pid kept allow=()
  local claude_builder claude_reviewer claude_same
  bin=$(command -v claude) || "$fail" "claude is not installed"
  claude_pick_model || "$fail" "the Claude model setting ~/.config/mentat/claude-model does not hold a model id"
  log="${out%/*}/claude.log"
  mkdir -p "${out%/*}/claude-tmp" || "$fail" "could not create Claude's temporary folder"
  # Web search asks for permission, which dontAsk denies, so consult allows it by name.
  [ "$tools" != WebSearch ] || allow=(--allowed-tools WebSearch)
  # --safe-mode drops CLAUDE.md, skills, plugins, hooks and MCP servers;
  # --setting-sources "" drops the user, project and local settings files, so none can
  # widen the permissions; --strict-mcp-config loads no MCP server; --tools is the only
  # tool list, and dontAsk denies anything that would ask, such as a read outside the
  # working folder. Not --bare: it skips the keychain, where the sign-in lives.
  # The environment is rebuilt: PATH to start Claude, HOME and USER for the keychain
  # sign-in and Claude's own config, TMPDIR for its temporary files, LANG for text, and
  # nonessential traffic (telemetry, updates) off. Nothing else of the agent's reaches it.
  (cd "$dir" && exec env -i PATH="$PATH" HOME="$HOME" USER="${USER:-}" TMPDIR="${out%/*}/claude-tmp" LANG="${LANG:-en_US.UTF-8}" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    "$bin" -p --safe-mode --no-session-persistence --strict-mcp-config --setting-sources "" \
    --permission-mode dontAsk --model "$claude_reviewer" --tools "$tools" ${allow[@]+"${allow[@]}"} \
    --disallowed-tools "${CLAUDE_CREDENTIAL_DENY[@]}" <"$prompt") >"$out.raw" 2>"$log" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$secs" -ge "$REVIEW_TIMEOUT_SECONDS" ]; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null
      "$fail" "Claude did not finish within $REVIEW_TIMEOUT_SECONDS seconds"
    fi
    sleep 1
    secs=$((secs + 1))
  done
  wait "$pid"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # Claude's raw output may hold a credential, so it is not printed. A copy is kept.
    kept=$(mktemp "${TMPDIR:-/tmp}/mentat-claude-log.XXXXXX") && cat "$log" "$out.raw" >"$kept"
    "$fail" "claude exited with status $rc; its log may hold credentials, so it is not printed. The maintainer can read it at $kept"
  fi
  grep -q '[^[:space:]]' "$out.raw" 2>/dev/null || "$fail" "Claude returned no reply"
  {
    printf 'Builder model: %s. Reviewer model: %s.\n' "$claude_builder" "$claude_reviewer"
    [ "$claude_same" = no ] || printf 'Note: the builder and reviewer models are the same model.\n'
    printf '\n'
    cat "$out.raw"
  } >"$out" || "$fail" "could not keep Claude's reply"
}

# The weigh runner: an export of the weighed commit, file tools only.
weigh_claude() {
  local tmp
  command -v claude >/dev/null 2>&1 || pair_fail "claude is not installed"
  tmp=$(mktemp -d) || pair_fail "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand now, so the path is fixed when the trap is set
  trap "rm -rf $(printf %q "$tmp")" EXIT
  mkdir "$tmp/export" || pair_fail "could not create the export folder"
  claude_export "$top" "$head" "$tmp/export" || pair_fail "could not export $head"
  {
    printf 'The working directory is a plain export of commit %s, without git history, and you have only file tools: no shell and no web.\n\n' "$head"
    cat "$res/body"
  } >"$tmp/prompt" || pair_fail "could not write the prompt"
  run_claude "$tmp/export" "$tmp/prompt" "$tmp/out" pair_fail "Read,Grep,Glob"
  pair_keep "$tmp/out" weigh_verdict_ok "WEIGH VERDICT"
}

# The consult runner: an empty folder, web search alone.
consult_claude() {
  local tmp
  command -v claude >/dev/null 2>&1 || pair_fail "claude is not installed"
  tmp=$(mktemp -d) || pair_fail "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand now, so the path is fixed when the trap is set
  trap "rm -rf $(printf %q "$tmp")" EXIT
  mkdir "$tmp/dir" || pair_fail "could not create the working folder"
  {
    printf 'You have no shell and no files, only web search.\n\n'
    cat "$res/body"
  } >"$tmp/prompt" || pair_fail "could not write the prompt"
  run_claude "$tmp/dir" "$tmp/prompt" "$tmp/out" pair_fail WebSearch
  pair_keep "$tmp/out" consult_line_ok "CONSULT"
}

# mentat challenge with Claude: an export of HEAD, file tools only. The result is
# printed, not posted.
challenge_claude() {
  local plan="$1" tool top head changes dirty=no tmp out verdict
  for tool in git claude; do
    command -v "$tool" >/dev/null 2>&1 || not_challenged "$tool is not installed"
  done
  top=$(git rev-parse --show-toplevel) || not_challenged "not inside a git repository"
  head=$(git -C "$top" rev-parse HEAD) || not_challenged "could not read HEAD"
  changes=$(git -C "$top" status --porcelain) || not_challenged "could not read git status"
  [ -z "$changes" ] || dirty=yes
  tmp=$(mktemp -d) || not_challenged "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand now, so the path is fixed when the trap is set
  trap "rm -rf $(printf %q "$tmp")" EXIT
  mkdir "$tmp/export" || not_challenged "could not create the export folder"
  claude_export "$top" "$head" "$tmp/export" || not_challenged "could not export $head"
  {
    printf 'Challenge the plan below before it is built. The working directory is a plain export of the repository it is for, '
    printf 'at commit %s, without git history or uncommitted changes, and you have only file tools: no shell and no web. Do not modify files.\n\n' "$head"
    challenge_body "$plan" || not_challenged "could not read $plan"
  } >"$tmp/prompt" || not_challenged "could not write the prompt"
  out="$tmp/challenge.md"
  run_claude "$tmp/export" "$tmp/prompt" "$out" not_challenged "Read,Grep,Glob"
  verdict=$(last_line "$out")
  challenge_verdict_ok "$verdict" || not_challenged "Claude's reply has no final CHALLENGE VERDICT line"
  printf '## Plan challenge by local Claude, run by the agent\n\n'
  printf -- '- Plan: %s\n- Started at commit: %s (uncommitted changes: %s; only the commit was read)\n' "$plan" "$head" "$dirty"
  printf -- '- Claude Code: %s\n- Time: %s\n' "$(claude --version 2>/dev/null | head -n 1)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf -- '- This is a plan challenge, not a review.\n\n---\n\n'
  cat "$out"
}
