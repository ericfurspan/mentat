#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for the Grok adapter, through `mentat review --outside` with grok the one
# reviewer listed, using a real git origin, a stub gh and a stub grok. Prints PASS/FAIL per case; exits 1 on any FAIL. One case also
# starts the real Grok (when installed) with the generated sandbox profile and no
# sign-in, so no model is called: see "Live profile check" below.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
# The per-run folder must be outside the temporary folders, so the tests use a
# folder under the real ~/.cache, which mentat's default does too.
mkdir -p "$HOME/.cache" || { echo "FAIL: review --outside, grok: cannot create $HOME/.cache"; exit 1; }
cache=$(mktemp -d "$HOME/.cache/mentat-test.XXXXXX") || { echo "FAIL: review --outside, grok: cannot create a folder under $HOME/.cache"; exit 1; }
cleanup() { rm -rf "$root" "$cache"; }
trap cleanup EXIT
# A temporary home beside the run folders: the publish check reads the home path and
# the word list from it. Only the real Grok of the live check keeps the real home.
real_home=$HOME
export HOME="$cache/home"
LIST="$HOME/.config/mentat/private-words"
mkdir -p "$(dirname "$LIST")"
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/tmp"
failures=0
check() { if eval "$2"; then printf 'PASS: review --outside, grok %s\n' "$1"; else printf 'FAIL: review --outside, grok %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export TMPDIR="$root/tmp" XDG_CACHE_HOME="$cache"

# An origin with main and pull request 7, whose head changes README and adds files
# that archive attributes and odd names would trip up. Outside reviewers are on in main's
# .claude/settings.json and list grok alone, so review --outside runs Grok.
REVIEWERS_ON='{"enabledPlugins":{"mentat-reviewers@mentat":true},"env":{"MENTAT_REVIEWERS":"grok"}}'
git init -q --bare -b main "$root/origin.git"
git init -q -b main "$root/seed"
(cd "$root/seed" && echo base >README && mkdir .claude && printf '%s\n' "$REVIEWERS_ON" >.claude/settings.json &&
  git add README .claude/settings.json && git commit -qm base && git push -q "$root/origin.git" main &&
  git checkout -qb feature && echo change >README &&
  printf 'ignored.txt export-ignore\nsubst.txt export-subst\n' >.gitattributes &&
  echo ignored >ignored.txt && echo 'id $Format:%H$' >subst.txt &&
  mkdir "a dir" && echo spaced >"a dir/a file.txt" && ln -s README link &&
  git add -A && git commit -qm change && git push -q "$root/origin.git" HEAD:refs/pull/7/head)
H=$(git -C "$root/seed" rev-parse feature)
BASE=$(git -C "$root/seed" rev-parse main)
# A checkout whose path has a space, with a dirty working tree that must not be what gets reviewed.
git clone -q "$root/origin.git" "$root/work tree"
echo dirty >"$root/work tree/README"
echo untracked >"$root/work tree/untracked.txt"

# The user's Grok home: a sign-in, and the things that must never reach a review.
GH_USER="$root/grok home"
mkdir -p "$GH_USER/hooks"
printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
printf '[models.x]\napi_key = "fake-per-model-key"\n[mcp]\nfake = "fake-mcp-server"\n' >"$GH_USER/config.toml"
echo fake-mcp-secret >"$GH_USER/mcp_credentials.json"
echo fake-hook >"$GH_USER/hooks/hook.json"
GH_REAL=$(cd -P "$GH_USER" && pwd -P)
export GROK_HOME="$GH_USER" XAI_API_KEY=fake-xai-key MENTAT_CANARY=fake-canary GROK_FOLDER_TRUST=0

# gh: pr view serves $STUB/head (moved_head replaces it after the first read);
# its merge state, not a head read, comes from $STUB/mergeable (MERGEABLE when absent);
# check runs come from $STUB/check_runs.json (check_runs_later.json from the second
# read on), and a file named push_on_ci holds a head to switch to when CI is read;
# pr comment records each comment as $STUB/comment.N, and adds it to the comments
# read back, as this account's; it fails when comment_fails exists (every comment)
# or result_fails exists (a --body-file comment).
cat >"$root/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
case "$1 $2" in
  "pr view")
    case "$*" in *mergeable*) if [ -f "$STUB/mergeable" ]; then cat "$STUB/mergeable"; else echo MERGEABLE; fi; exit 0 ;; esac
    n=$(($(cat "$STUB/head_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/head_reads"
    h=$(cat "$STUB/head"); [ "$n" -gt 1 ] && [ -f "$STUB/moved_head" ] && h=$(cat "$STUB/moved_head")
    case "$*" in
      *--jq*) echo "$h" ;;
      *) jq -n --arg h "$h" --argjson c "$(cat "$STUB/closes" 2>/dev/null || echo '[]')" '{headRefOid: $h, baseRefName: "main", title: "Change README", body: "Requirement: README says change.", closingIssuesReferences: $c}' ;;
    esac ;;
  "repo view")
    case "$*" in
      *isPrivate*) [ -f "$STUB/lookup_fails" ] && exit 1; if [ -f "$STUB/private" ]; then echo true; else echo false; fi ;;
      *) echo owner/repo ;;
    esac ;;
  "issue view")
    r=$5; f="$STUB/issue_${r/\//_}_$3"
    [ "$4" = --repo ] && [ -f "$f" ] || exit 1
    printf 'Issue %s#%s: %s\n\n%s' "$r" "$3" "$(head -1 "$f")" "$(tail -n +2 "$f")" ;;
  "api --paginate")
    case "$3" in
      */check-runs)
        # spoof_during_ci: this account's start comment appears while CI is being waited on.
        [ -f "$STUB/spoof_during_ci" ] && jq -n --arg b "Grok review started on $(cat "$STUB/head")" '[{user: {login: "agent-bot"}, body: $b}]' >"$STUB/issue_comments.json"
        n=$(($(cat "$STUB/ci_reads" 2>/dev/null || echo 0) + 1)); echo "$n" >"$STUB/ci_reads"
        [ -f "$STUB/push_on_ci" ] && cp "$STUB/push_on_ci" "$STUB/head"
        if [ "$n" -ge 2 ] && [ -f "$STUB/check_runs_later.json" ]; then cat "$STUB/check_runs_later.json"; else cat "$STUB/check_runs.json"; fi ;;
      */comments) [ -f "$STUB/comments_fail" ] && exit 1; cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]' ;;
      *) exit 99 ;;
    esac ;;
  "api user") [ -f "$STUB/user_fails" ] && exit 1; echo agent-bot ;;
  "pr comment")
    [ -f "$STUB/comment_fails" ] && exit 1
    n=$(($(cat "$STUB/comment_count" 2>/dev/null || echo 0) + 1))
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --body) printf '%s\n' "$2" >"$STUB/comment.$n" ;;
        --body-file) [ -f "$STUB/result_fails" ] && exit 1; cp "$2" "$STUB/comment.$n" ;;
      esac
      shift
    done
    echo "$n" >"$STUB/comment_count"
    jq --rawfile b "$STUB/comment.$n" '. + [{user: {login: "agent-bot"}, body: $b}]' <<<"$(cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]')" >"$STUB/ic.tmp" && mv "$STUB/ic.tmp" "$STUB/issue_comments.json"
    echo "https://example.test/comment/$n" ;;
  *) exit 99 ;;
esac
STUBEOF
# grok: records how it was started and what it can see, and its run in the calls gh records, then replies with
# $STUB/out_json (stdout) and $STUB/exit_code, adding $STUB/err_text to its stderr and
# $STUB/debug_text to its debug file when they exist. In live mode it hands over to the
# real Grok instead, without the sign-in, and keeps the sandbox event.
# (mentat starts it with an empty environment, so its own path is written in.)
{ printf '#!/usr/bin/env bash\nSTUB=%q\nREAL_HOME=%q\n' "$STUB" "$real_home"; cat; } >"$root/bin/grok" <<'STUBEOF'
[ "${1:-}" = --version ] && { echo "grok 9.9.9 (stub)"; exit 0; }
if [ "${1:-}" = models ]; then
  printf '%s\n' "$@" >"$STUB/args_models"
  env | sort >"$STUB/env_models"
  printf '%s\n' "$GROK_HOME" >"$STUB/models_home"
  [ -f "$STUB/models_hang" ] && { echo $$ >"$STUB/model_pid"; exec sleep 30; }
  if [ -f "$STUB/refresh_to" ]; then
    printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token-2"}}\n' "$(cat "$STUB/refresh_to")" >"$GROK_HOME/auth.json"
    chmod 600 "$GROK_HOME/auth.json"
  fi
  exit 0
fi
echo grok >>"$STUB/calls"
args=("$@")
prev=""
printf '%s\n' "$@" >"$STUB/args"
env | sort >"$STUB/env"
pwd -P >"$STUB/cwd"
ls -A "$GROK_HOME" >"$STUB/home_files"
ls -A "$GROK_HOME/vendor" >"$STUB/vendor_files"
ls -A "$GROK_HOME/.." >"$STUB/run_entries"
cp "$GROK_HOME/auth.json" "$STUB/auth_copy"
stat -f '%Lp' "$GROK_HOME/auth.json" >"$STUB/auth_mode"
cp "$GROK_HOME/sandbox.toml" "$GROK_HOME/config.toml" "$STUB/"
find . -mindepth 1 -not -type d | sort >"$STUB/export_files"
[ -e .git ] && echo yes >"$STUB/has_git"
prompt=""
while [ $# -gt 0 ]; do [ "$1" = --prompt-file ] && prompt=$2; shift; done
cp "$prompt" "$STUB/prompt"
ls -A "$(dirname "$prompt")" >"$STUB/prompt_dir"
cp -R . "$STUB/export_copy"
if [ -f "$STUB/live" ]; then
  rm -f "$GROK_HOME/auth.json"
  HOME=$REAL_HOME "$(cat "$STUB/live")" "${args[@]}" >"$STUB/live_out" 2>"$STUB/live_err" </dev/null
  rc=$?
  cp "$GROK_HOME/sessions/sandbox-events.jsonl" "$STUB/sandbox-events.jsonl" 2>/dev/null
  exit "$rc"
fi
for a in "${args[@]}"; do [ "$prev" = --debug-file ] && { echo "DEBUG-LOG-TEXT"; cat "$STUB/debug_text" 2>/dev/null; } >"$a"; prev=$a; done
[ -f "$STUB/hang" ] && { echo $$ >"$STUB/model_pid"; exec sleep 30; }
# @EXPORT@ in the reply becomes the export's path, which is where Grok works.
sed "s|@EXPORT@|$(pwd -P)|g" "$STUB/out_json"
echo "SECRET-LOG-TEXT" >&2
[ -f "$STUB/err_text" ] && cat "$STUB/err_text" >&2
exit "$(cat "$STUB/exit_code")"
STUBEOF
# codex: only to compare the shared criteria with the ones the Codex adapter gives.
cat >"$root/bin/codex" <<'STUBEOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo codex-stub; exit 0; }
cat >"$STUB/codex_prompt"
while [ $# -gt 0 ]; do [ "$1" = -o ] && printf 'ok\n\nREVIEW RESULT: NO FINDINGS\n' >"$2"; shift; done
STUBEOF
chmod +x "$root/bin/gh" "$root/bin/grok" "$root/bin/codex"
# CI waits are short, as in tests/review.sh; a passed check with no finish time returns at once.
export PATH="$root/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_CI_TIMEOUT_SECONDS=2 MENTAT_CI_GRACE_SECONDS=1
unset MENTAT_REVIEW_ROUNDS MENTAT_REVIEW_TIMEOUT_SECONDS MENTAT_GROK_TIMEOUT_SECONDS MENTAT_REVIEWERS

reply() { # $1 text, $2 stop reason
  jq -n --arg t "$1" --arg s "${2:-end_turn}" '{text: $t, stopReason: $s, sessionId: "s", modelUsage: {"grok-stub": {}}}' >"$STUB/out_json"
}
# stub_reset clears the stubs' state; reset also clears the record of failures in a row.
stub_reset() {
  rm -rf "${STUB:?}"/*
  echo "$H" >"$STUB/head"
  echo 0 >"$STUB/exit_code"
  reply $'The pull request changes README.\n\nNothing to flag.\n\nREVIEW RESULT: NO FINDINGS'
  echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' >"$STUB/check_runs.json"
}
reset() { stub_reset; rm -f "$cache"/mentat/reviewer-failures-*; }
# Outside reviewers run only on a head Claude's latest review found nothing on: before each
# run, once per case, this account's Local Claude review of the head GitHub reports says so.
claude_clean() {
  [ -f "$STUB/claude_clean" ] && return 0
  jq --arg b "## Local Claude review of $(cat "$STUB/head"): no findings, spec fingerprint none" '. + [{user: {login: "agent-bot"}, body: $b}]' \
    <<<"$(cat "$STUB/issue_comments.json" 2>/dev/null || echo '[]')" >"$STUB/ic.tmp" && mv "$STUB/ic.tmp" "$STUB/issue_comments.json" && touch "$STUB/claude_clean"
}
runrc() { claude_clean; (cd "$root/work tree" && "$mentat" review --outside "$@" >"$STUB/out" 2>&1); echo $?; }
run() { runrc "${1:-7}"; }
comments() { find "$STUB" -name 'comment.*' | wc -l | tr -d ' '; }
grok_ran() { [ -f "$STUB/args" ]; }
# The posted review: a heading line naming the head, the spec fingerprint and the list, then
# Grok's result line, the run's bullets, and its reply folded with the record of the run;
# the reply's own result line is the last line inside the fold, and nothing follows the fold.
C="$STUB/comment.1"
heading() { [ "$(head -n 1 "$C")" = "## Outside review of $H: spec fingerprint ${2:-none}, reviewers grok" ] && grep -qxF -- "- grok: $1" "$C"; }
folded() { sed -n '/^<details><summary>Grok<\/summary>$/,/^<\/details>$/p' "$C"; }
# The last non-blank line before the fold closes, in file $1.
last_in_fold() { grep -v '^[[:space:]]*$' "$1" | tail -n 2 | head -n 1; }
fold_shape() { # $1 the final REVIEW RESULT line
  [ "$(sed -n '/^<details><summary>Grok<\/summary>$/{n;s/^$/blank/;p;}' "$C")" = blank ] && [ "$(tail -n 1 "$C")" = "</details>" ] &&
    [ "$(grep -c '^</details>$' "$C")" = 1 ] && [ "$(last_in_fold "$C")" = "$1" ] && [ "$(grep -cxF -- "$1" "$C")" = 1 ]
}
reply_in_fold() { folded | sed -n "/^---\$/,\$p" | sed "1,2d;\$d"; }
# The summary line for Grok, and the maintainer's local line for it.
summary() { sed -n 's/^grok: //p' "$STUB/out"; }
local_line() { sed -n 's/^mentat: grok: //p' "$STUB/out"; }
kept_log() { local_line | sed -n 's/.*The maintainer can read it at //p'; }
# What a run left in the cache folder besides the record of failures in a row, which stays.
left_over() { find "$cache/mentat" -mindepth 1 -maxdepth 1 ! -name reviewer-failures-grok 2>/dev/null; }
# settings_list <names>: main's MENTAT_REVIEWERS on origin.
settings_list() {
  (cd "$root/seed" && git checkout -q main && printf '{"enabledPlugins":{"mentat-reviewers@mentat":true},"env":{"MENTAT_REVIEWERS":"%s"}}\n' "$1" >.claude/settings.json &&
    git commit -qam "list $1" && git push -q "$root/origin.git" main && git checkout -q feature)
}

reset; rc=$(run)
check "no findings exits 0 and posts one comment, the outside review" '[ "$rc" = 0 ] && grep -q "found nothing on $H: https://example.test/comment/1" "$STUB/out" && [ "$(comments)" = 1 ] && grep -q "^## Outside review of $H" "$C"'
check "the review opens with one heading line, a blank line, then Grok's result" 'heading "no findings" none && [ "$(sed -n 2p "$C")" = "" ] && [ "$(sed -n 3p "$C")" = "- grok: no findings" ]'
check "the record and the whole reply are folded, a blank line follows the summary, the reply's result line is last inside the fold, and nothing follows the fold" 'fold_shape "REVIEW RESULT: NO FINDINGS" && folded | grep -qx -- "- Grok CLI: grok 9.9.9 (stub)" && folded | grep -qx -- "- Run with file-reading tools and no shell." && [ "$(reply_in_fold)" = "$(jq -r .text "$STUB/out_json")" ]'
check "the posted review is Grok's text, with its version and model" 'grep -q "Nothing to flag." "$C" && grep -qx -- "- Grok CLI: grok 9.9.9 (stub)" "$C" && grep -qx -- "- Model: grok-stub" "$C" && grep -q "Change reviewed: $BASE..$H" "$C"'
# Grok's effort: high unless MENTAT_GROK_REASONING_EFFORT names another level; set but empty is high too.
grok_effort() { [ "$(grep -x -A1 -- "--reasoning-effort" "$STUB/args" | tail -n 1)" = "$1" ] && [ "$(grep -cx -- "--reasoning-effort" "$STUB/args")" = 1 ] && folded | grep -qx -- "- Reasoning effort asked for: $1"; }
reset; rc=$(unset MENTAT_GROK_REASONING_EFFORT; run)
check "without MENTAT_GROK_REASONING_EFFORT Grok runs with --reasoning-effort high, and the record names high as asked for" '[ "$rc" = 0 ] && grok_effort high'
reset; rc=$(MENTAT_GROK_REASONING_EFFORT='' run)
check "MENTAT_GROK_REASONING_EFFORT set but empty runs Grok with --reasoning-effort high" '[ "$rc" = 0 ] && grok_effort high'
reset; rc=$(MENTAT_GROK_REASONING_EFFORT=medium run)
check "MENTAT_GROK_REASONING_EFFORT=medium runs Grok with --reasoning-effort medium, and the record names medium" '[ "$rc" = 0 ] && grok_effort medium'
reset; rc=$(run)
check "the per-run folder is gone afterward" '[ -z "$(left_over)" ]'
check "runs in the export, with the prompt from a file and the JSON output" '[ "$(sed -n "/^--cwd\$/{n;p;}" "$STUB/args")" = "$(cat "$STUB/cwd")" ] && grep -qx -- "--prompt-file" "$STUB/args" && [ "$(grep -x -A1 -- "--output-format" "$STUB/args" | tail -n 1)" = json ]'
check "exports the head's files, with no .git, matching the commit" '[ ! -f "$STUB/has_git" ] && ! grep -q "\.git/" "$STUB/export_files" && [ "$(sed "s#^\./##" "$STUB/export_files" | sort)" = "$(git -C "$root/seed" ls-tree -r --name-only "$H" | sort)" ] && [ "$(cat "$STUB/export_copy/README")" = change ]'
check "the export ignores export-ignore and export-subst, and nothing from the working tree" '[ -f "$STUB/export_copy/ignored.txt" ] && grep -qF "\$Format:%H\$" "$STUB/export_copy/subst.txt" && [ ! -e "$STUB/export_copy/untracked.txt" ] && [ "$(cat "$STUB/export_copy/a dir/a file.txt")" = spaced ] && [ -L "$STUB/export_copy/link" ]'
check "Grok gets read-only tools and no shell, agents, plan, memory, web, fetch or leader" 'm="" && for f in "--tools" "read_file,grep,list_dir" "--disallowed-tools" "Agent,run_terminal_command,run_terminal_cmd" "--no-subagents" "--no-plan" "--no-leader" "--no-memory" "--no-auto-update" "--disable-web-search" "--permission-mode" "dontAsk" "--max-turns" "60"; do grep -qxF -- "$f" "$STUB/args" || m="$m $f"; done && { [ -z "$m" ] || { echo "missing:$m"; false; }; } && grep -x -A1 -- "--deny" "$STUB/args" | grep -qxF WebFetch'
EXPORT_RUN=$(cat "$STUB/cwd")
check "no deny rule covers the export or the prompt, which the tools must read (a deny beats an allow)" 'c="" && for r in "$EXPORT_RUN" "$(dirname "$EXPORT_RUN")/in/prompt"; do while IFS= read -r a; do case "$a" in Read\(*\)|Grep\(*\)) p=${a#*(}; p=${p%)}; case "$p" in */\*\*) q=${p%/\*\*}; case "$r/" in "$q"/*) c="$c $a covers $r;" ;; esac ;; *) [ "$p" != "$r" ] || c="$c $a covers $r;" ;; esac ;; esac; done <"$STUB/args"; done && { [ -z "$c" ] || { echo "$c"; false; }; }'
check "the folders above the export are denied as paths, so they cannot be listed" 'm=""; p=$EXPORT_RUN; while [ "$p" != / ]; do p=$(dirname "$p"); for t in Read Grep; do grep -qxF -- "$t($p)" "$STUB/args" || m="$m $t($p)"; done; done && { [ -z "$m" ] || { echo "missing:$m"; false; }; }'
check "never passes --trust, --yolo or an always-approve mode" '! grep -qxE -- "--trust|--yolo|--always-approve|--allow|--sandbox-off|bypassPermissions" "$STUB/args"'
HOME_RUN=$(sed -n 's/^GROK_HOME=//p' "$STUB/env")
SYSTEM_ROOTS="/private /Library /etc /var /opt /Volumes /Applications /System /usr /bin /sbin /dev /tmp $(cd -P "$HOME" && pwd -P)/Library $(cd -P "$root/tmp" && pwd -P)"
check "denies MCP tools, and reading or searching both Grok homes and the system folders, each as a folder and as everything under it" 'grep -qxF -- "MCPTool" "$STUB/args" && m="" && for h in "$HOME_RUN" "$GH_REAL" $SYSTEM_ROOTS; do for t in Read Grep; do for p in "$h" "$h/**"; do grep -qxF -- "$t($p)" "$STUB/args" || m="$m $t($p)"; done; done; done && { [ -z "$m" ] || { echo "missing:$m"; false; }; }'
check "runs under the Grok sandbox with the profile Mentat wrote" '[ "$(grep -x -A1 -- "--sandbox" "$STUB/args" | tail -n 1)" = mentat-review ] && grep -qx "\[profiles.mentat-review\]" "$STUB/sandbox.toml" && grep -qx "extends = \"strict\"" "$STUB/sandbox.toml"'
check "the profile denies the temporary folders, ~/Library, both Grok homes and the credential files" 'm="" && for f in /tmp /private/tmp /var/tmp /private/var/tmp /var/folders /private/var/folders "$(cd -P "$HOME" && pwd -P)/Library" "$GH_REAL" "$(cd -P "$root/tmp" && pwd -P)"; do grep -qF "\"$f\"" "$STUB/sandbox.toml" || m="$m $f"; done && { [ -z "$m" ] || { echo "missing:$m"; false; }; } && m2="" && for g in "**/.env" "**/.env.*" "**/*.pem" "**/*.key" "**/*.p12" "**/*.pfx" "**/id_rsa*" "**/id_ecdsa*" "**/id_ed25519*" "**/.netrc" "**/.npmrc" "**/.pypirc"; do grep -qF "\"$g\"" "$STUB/sandbox.toml" || m2="$m2 $g"; done && { [ -z "$m2" ] || { echo "missing:$m2"; false; }; }'
check "the profile lets Grok read the prompt folder, which holds only the prompt, and write only its vendor folder" 'grep -qE "^read_only = \[\".*/in\"\]\$" "$STUB/sandbox.toml" && [ "$(cat "$STUB/prompt_dir")" = prompt ] && grep -qxF "read_write = [\"$HOME_RUN/vendor\"]" "$STUB/sandbox.toml"'
check "its home holds only the sign-in, the Mentat config, the profile and an empty vendor folder" '[ "$(tr "\n" " " <"$STUB/home_files")" = "auth.json config.toml sandbox.toml sessions vendor " ] && [ ! -s "$STUB/vendor_files" ] && [ "$(cat "$STUB/auth_copy")" = "$(cat "$GH_USER/auth.json")" ] && [ "$(cat "$STUB/auth_mode")" = 600 ] && [ "$HOME_RUN" != "$GH_REAL" ] && grep -qx "codebase_indexing = false" "$STUB/config.toml"'
check "Grok writes a debug file in its sessions folder, which is where a run that never finishes leaves its record" '[ "$(grep -x -A1 -- "--debug-file" "$STUB/args" | tail -n 1)" = "$HOME_RUN/sessions/debug.log" ]'
check "its home has a name a pull request cannot guess, so a symlink such as ../home reaches nothing" '! grep -qx home "$STUB/run_entries" && grep -qx "$(basename "$HOME_RUN")" "$STUB/run_entries"'
check "nothing from the user config, MCP credentials or hooks reaches its home" '! grep -rq "fake-per-model-key\|fake-mcp" "$STUB/config.toml" "$STUB/sandbox.toml" "$STUB/prompt" "$STUB/args" "$STUB/env"'
check "Grok gets a rebuilt environment: no API key, no other variables, real HOME, compatibility off" '! grep -q "^XAI_API_KEY=" "$STUB/env" && ! grep -q "MENTAT_CANARY\|GROK_FOLDER_TRUST" "$STUB/env" && grep -qx "HOME=$HOME" "$STUB/env" && grep -q "^PATH=" "$STUB/env" && grep -q "^LANG=" "$STUB/env" && m="" && for v in GROK_MEMORY=0 GROK_TELEMETRY_ENABLED=0 GROK_TELEMETRY_TRACE_UPLOAD=0 GROK_EXTERNAL_OTEL=0 GROK_DISABLE_AUTOUPDATER=1 GROK_CLAUDE_AGENTS_ENABLED=false GROK_CLAUDE_HOOKS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false GROK_CLAUDE_RULES_ENABLED=false GROK_CLAUDE_SKILLS_ENABLED=false GROK_CURSOR_AGENTS_ENABLED=false GROK_CURSOR_HOOKS_ENABLED=false GROK_CURSOR_MCPS_ENABLED=false GROK_CURSOR_RULES_ENABLED=false GROK_CURSOR_SKILLS_ENABLED=false; do grep -qx "$v" "$STUB/env" || m="$m $v"; done && { [ -z "$m" ] || { echo "missing:$m"; false; }; }'
check "its temporary folder and home are in the run folder, outside the temporary folders" 'case "$(sed -n "s/^TMPDIR=//p" "$STUB/env")" in "$(dirname "$HOME_RUN")"/tmp) true ;; *) false ;; esac && case "$HOME_RUN" in /tmp/* | /private/tmp/* | /var/* | /private/var/*) false ;; *) true ;; esac'
check "the prompt has the diff between markers, the description and the status line" 'grep -qx -- "--- BEGIN DIFF DATA ---" "$STUB/prompt" && grep -qx -- "--- END DIFF DATA ---" "$STUB/prompt" && grep -qx -- "+change" "$STUB/prompt" && grep -q "BEGIN PULL REQUEST DATA" "$STUB/prompt" && grep -q "Requirement: README says change." "$STUB/prompt" && tail -n 3 "$STUB/prompt" | grep -qx "REVIEW RESULT: FINDINGS" && ! grep -q "git diff" "$STUB/prompt"'
check "the prompt takes the intent from the Summary opening sentence, or the template equivalent" 'grep -q "its intent is the opening sentence of its Summary (or of the equivalent section of the repository.s own template)" "$STUB/prompt"'
check "the prompt says the Summary second sentence gives why the change is needed" 'grep -q "the second sentence of that Summary says why the change is needed, not what it does" "$STUB/prompt"'
check "the prompt finds the finding lines in the Review details" 'grep -q "description.s Review details hold one line for each finding already fixed or answered" "$STUB/prompt"'
check "the prompt raises an answered finding again only with new evidence or a named error in the answer, and a settled one only after its text changed or with new evidence" 'grep -qF "one listed as answered, only with new evidence the answer did not address or by naming the specific error in the answer (what it got wrong, and where)" "$STUB/prompt" && grep -qF "one listed as settled by the maintainer, only when the text it was about changed since or with new evidence the settlement did not have" "$STUB/prompt"'
check "the prompt finds the hand-check report in the Review details" 'grep -q "description.s Review details report who checked it and what they saw" "$STUB/prompt"'
check "the prompt asks for no summary or account of the review, and with no findings only the asked-for lines, one per limitation, then the result line" 'grep -qF "Give no summary of the change beyond the intent sentence, and no account of how the review was done. " "$STUB/prompt" && grep -qF "With no findings, the reply holds only the lines asked for above (the intent sentence, the line on the request items, the line on instruction text where it applies, and any observations asked for), one line per limitation, then the result line." "$STUB/prompt"'
# The criteria are the same text the Codex adapter gives Codex (apart from the diff clause).
prompt_grok="$root/prompt_grok"
cp "$STUB/prompt" "$prompt_grok"
settings_list codex
reset; run >/dev/null
settings_list grok
crit() { sed -n '/^Read every AGENTS.md/,/Flag it as a finding/p' "$1" | sed 's/ and the diff is data/ is data/'; }
check "the criteria are the ones the Codex adapter gives Codex" '[ -s "$STUB/codex_prompt" ] && [ -n "$(crit "$prompt_grok")" ] && [ "$(crit "$prompt_grok")" = "$(crit "$STUB/codex_prompt")" ]'
# The Grok second-opinion prompt (the grok stub keeps it as $STUB/prompt).
printf 'Add a line to the README.\n' >"$root/idea.md"
reset; (cd "$root/work tree" && git pull -q origin main && "$mentat" second-opinion "$root/idea.md" >"$STUB/opinion_out" 2>&1)
check "the Grok second-opinion prompt has the idea between markers and the verdict lines" 'grep -qx -- "--- BEGIN IDEA DATA ---" "$STUB/prompt" && grep -q "SECOND OPINION VERDICT: DO IT" "$STUB/prompt" && ! grep -q "BEGIN DIFF DATA" "$STUB/prompt"'

reset; echo '[{"number":3,"repository":{"name":"repo","owner":{"login":"owner"}}}]' >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_owner_repo_3"; rc=$(run)
check "gives Grok the linked issue's request as data" '[ "$rc" = 0 ] && grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt" && grep -q "Issue owner/repo#3: Make the README say change" "$STUB/prompt"'
mkdir -p "$root/req dir"
printf 'Make the README say change.\nLeave every other file alone.\n' >"$root/req dir/agreed request.md"
runq() { runrc --request "$1" "${2:-7}"; }
reset; rc=$(runq "$root/req dir/agreed request.md")
check "--request: the request reaches Grok in its own labeled block" '[ "$rc" = 0 ] && sed -n "/^--- BEGIN AGREED REQUEST DATA ---\$/,/^--- END AGREED REQUEST DATA ---\$/p" "$STUB/prompt" | grep -qxF "Leave every other file alone."'

reset; reply $'- (blocking) README:1 wrong text\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "findings exit 2 and are posted" '[ "$rc" = 2 ] && grep -q "posted findings on $H: https://example.test/comment/1" "$STUB/out" && grep -q "(blocking) README:1" "$C"'
check "a FINDINGS reply's result line says findings, and its findings are inside the fold" 'heading findings none && fold_shape "REVIEW RESULT: FINDINGS" && folded | grep -qx -- "- (blocking) README:1 wrong text"'

# Grok works in an export under the per-run folder and may cite files by its absolute path.
# The posted review holds no such path, and links the file at the reviewed commit.
REPO_URL="https://github.com/owner/repo/blob/$H"
reset; reply $'Changes README.\n\n- (non-blocking) [README:1](@EXPORT@/README:1): wrong text\n- (non-blocking) [lib/shared.sh:93-95](@EXPORT@/lib/shared.sh:93-95): a range\n- (non-blocking) [a dir/a file.txt](@EXPORT@/a dir/a file.txt#L4): a spaced name\n- (non-blocking) see @EXPORT@/lib/x.sh:7 and `@EXPORT@/lib/y.sh`\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
RUN_DIR=$(dirname "$(cat "$STUB/cwd")")
check "a finding that cites the export is posted with repository links and no local path" '[ "$rc" = 2 ] && ! grep -qF "$(cat "$STUB/cwd")" "$C" && ! grep -qF "$RUN_DIR" "$C" && grep -qF "[README:1]($REPO_URL/README#L1): wrong text" "$C" && grep -qF "[lib/shared.sh:93-95]($REPO_URL/lib/shared.sh#L93-L95): a range" "$C" && grep -qF "[a dir/a file.txt]($REPO_URL/a%20dir/a%20file.txt#L4): a spaced name" "$C"'
check "a plain mention of the export, bare or in code, becomes the repository path, and the rest of the review is kept" 'grep -qF -- "- (non-blocking) see lib/x.sh:7 and \`lib/y.sh\`" "$C" && grep -qx "Changes README." "$C" && [ "$(last_in_fold "$C")" = "REVIEW RESULT: FINDINGS" ]'
check "the rewritten reply is inside the fold, intact, with its result line last inside the fold" 'fold_shape "REVIEW RESULT: FINDINGS" && [ "$(reply_in_fold)" = "Changes README.

- (non-blocking) [README:1]($REPO_URL/README#L1): wrong text
- (non-blocking) [lib/shared.sh:93-95]($REPO_URL/lib/shared.sh#L93-L95): a range
- (non-blocking) [a dir/a file.txt]($REPO_URL/a%20dir/a%20file.txt#L4): a spaced name
- (non-blocking) see lib/x.sh:7 and \`lib/y.sh\`

REVIEW RESULT: FINDINGS" ]'
reset; reply $'- (non-blocking) not @EXPORT@-other/z or /Users/other/export/w\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a path that only starts with the export's name, and other absolute paths, are left alone" '[ "$rc" = 2 ] && grep -qxF -- "- (non-blocking) not $(cat "$STUB/cwd")-other/z or /Users/other/export/w" "$C"'
reset; reply $'Could not finish.\n\nREVIEW RESULT: INCOMPLETE - could not read @EXPORT@/lib/z.sh'; rc=$(run)
check "an INCOMPLETE reason that names the export is posted and printed as a repository path, and Grok did not finish" '[ "$rc" = 0 ] && ! grep -qF "$(cat "$STUB/cwd")" "$C" "$STUB/out" && grep -qx "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" "$C" && heading "did not finish (Grok says the review is incomplete)" none && fold_shape "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" && grep -qx "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" "$STUB/out" && [ -z "$(left_over)" ]'

# Every way Grok's run can fail: Grok did not finish, its reason in Mentat's words is posted,
# the run goes on to CI and the post, and the raw log is kept privately, named only on the
# maintainer's local line, never printed or posted.
not_finished() { # $1 description, $2 expected public reason
  why=$2
  check "$1: did not finish, said in Mentat's words, posted, no log text printed or posted" '[ "$rc" = 0 ] && [ "$(summary)" = "did not finish ($why)" ] && heading "did not finish ($why)" && ! grep -q "SECRET-LOG-TEXT\|DEBUG-LOG-TEXT" "$STUB/out" "$C" && [ -z "$(left_over)" ]'
}
reset; echo 3 >"$STUB/exit_code"; rc=$(run)
not_finished "Grok exiting non-zero" "Grok exited with status 3"
check "it keeps a private copy of the raw log for the maintainer, named on the local line only" 'p=$(kept_log); [ -n "$p" ] && grep -q SECRET-LOG-TEXT "$p" && ! grep -qF "$p" "$C"'
reset; reply $'Looks fine.\n\nREVIEW RESULT: NO FINDINGS' max_turn_requests; rc=$(run)
not_finished "a failure stop reason with a plausible result line" "Grok did not return a complete review"
check "the stop reason is on the local line only" 'local_line | grep -q "^stop reason: max_turn_requests; its log may hold credentials" && ! grep -q max_turn_requests "$C"'
reset; reply $'Looks fine.\n\nREVIEW RESULT: NO FINDINGS' future_reason; rc=$(run)
not_finished "an unknown stop reason" "Grok did not return a complete review"
reset; echo '{"type":"error","message":"Not signed in. SECRET-LOG-TEXT"}' >"$STUB/out_json"; rc=$(run)
not_finished "an error object with a zero exit" "Grok did not return a complete review"
reset; echo '{"type":"error","message":"Not signed in"}' >"$STUB/out_json"; echo 1 >"$STUB/exit_code"; rc=$(run)
not_finished "an error object with exit 1" "Grok exited with status 1"
reset; printf '{"text": "Nothing.\\n\\nREVIEW RESULT: NO FIN' >"$STUB/out_json"; rc=$(run)
not_finished "truncated output" "Grok did not return a complete review"
reset; reply $'Looks fine to me.'; rc=$(run)
not_finished "a reply without a result line" "Grok's reply has no final REVIEW RESULT line"
for bare in 'REVIEW RESULT: INCOMPLETE' 'REVIEW RESULT: INCOMPLETE -' 'REVIEW RESULT: INCOMPLETE -   '; do
  reset; reply $'Could not finish.\n\n'"$bare"; rc=$(run)
  not_finished "an INCOMPLETE line without a reason ('$bare')" "Grok's reply has no final REVIEW RESULT line"
done
reset; reply $'REVIEW RESULT: NO FINDINGS\n\nBut actually there is a problem.'; rc=$(run)
not_finished "a result line that is not last" "Grok's reply has no final REVIEW RESULT line"
reset; reply "   "; rc=$(run)
not_finished "an empty text" "Grok did not return a complete review"
reset; { cat "$STUB/out_json"; cat "$STUB/out_json"; } >"$STUB/out_json.2"; mv "$STUB/out_json.2" "$STUB/out_json"; rc=$(run)
not_finished "two JSON objects" "Grok did not return a complete review"
reset; : >"$STUB/out_json"; rc=$(run)
not_finished "no output" "Grok did not return a complete review"
reset; touch "$STUB/hang"; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=2 run)
not_finished "a timeout (MENTAT_REVIEW_TIMEOUT_SECONDS)" "Grok did not finish within 2 seconds"
check "a timeout still leaves the debug record in the private log, and stops Grok" 'p=$(kept_log); [ -n "$p" ] && grep -q DEBUG-LOG-TEXT "$p" && ! grep -q DEBUG-LOG-TEXT "$STUB/out" && ! kill -0 "$(cat "$STUB/model_pid")" 2>/dev/null'
reset; touch "$STUB/hang"; rc=$(MENTAT_GROK_TIMEOUT_SECONDS=1 MENTAT_REVIEW_TIMEOUT_SECONDS=2 run)
check "MENTAT_GROK_TIMEOUT_SECONDS is not read: MENTAT_REVIEW_TIMEOUT_SECONDS limits Grok" '[ "$(summary)" = "did not finish (Grok did not finish within 2 seconds)" ]'

# Sign-in: refused before any refresh or Grok run when there is none; Grok did not finish,
# its reason posted, and its token never printed.
reset; rm "$GH_USER/auth.json"; rc=$(run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "no Grok sign-in: did not finish, no Grok run, no refresh" '[ "$rc" = 0 ] && [ "$(summary)" = "did not finish (Grok is not signed in: there is no auth.json in its home (run grok login))" ] && ! grok_ran && [ ! -e "$STUB/args_models" ]'
reset; printf '{"https://auth.x.ai::test":{"expires_at":"2020-01-01T00:00:00.000000Z","key":"fake-token"}}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "an expired Grok sign-in did not finish, with its token not printed or posted" '[ "$rc" = 0 ] && summary | grep -q "^did not finish (Grok'"'"'s sign-in expired at 2020-01-01T00:00:00Z" && ! grok_ran && ! grep -q fake-token "$STUB/out" "$C" && [ -f "$STUB/args_models" ]'
reset; printf '{"https://auth.x.ai::test":{"expires_at":"2099-01-01T00:00:00.000000Z","key":"fake-token"}}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "a Grok sign-in with its expiry in the future is reviewed" '[ "$rc" = 0 ] && grok_ran && [ ! -e "$STUB/args_models" ]'
soon=$(date -u -v+600S +%Y-%m-%dT%H:%M:%S.000000Z)
reset; printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token"}}\n' "$soon" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1800 run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "a Grok sign-in that expires before the time limit would end did not finish, with its token not printed" '[ "$rc" = 0 ] && summary | grep -qF "did not finish (Grok'"'"'s sign-in expires at ${soon:0:19}Z, before this run'"'"'s 1800-second time limit and 5 minutes of setup would end" && ! grok_ran && ! grep -q fake-token "$STUB/out" && [ -f "$STUB/args_models" ]'
reset; printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token"}}\n' "$soon" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=60 run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "the same sign-in with a 60-second time limit is reviewed" '[ "$rc" = 0 ] && grok_ran && [ ! -e "$STUB/args_models" ]'
# A sign-in that is expired, or too short for the run, is first refreshed by grok models
# in the user's own Grok home; the stub's models branch rewrites it only when refresh_to exists.
set_signin() { printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token"}}\n' "$1" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; }
reset_signin() { printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; }
# A sign-in file that is not a JSON object holding a non-empty string at some depth is no
# sign-in: refused like a missing file, before any refresh or Grok run.
for s in '' '{}' '""' '{"token":""}' '{"a":{"b":"","c":[]}}' 'not json' '{"fake":"credential"} {"fake":"credential"}'; do
  reset; printf '%s' "$s" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(run); reset_signin
  check "a sign-in file holding ${s:-nothing} is refused as not signed in: no Grok run, no refresh" '[ "$rc" = 0 ] && summary | grep -q "^did not finish (Grok is not signed in" && ! grok_ran && [ ! -e "$STUB/args_models" ] && ! grep -q "token\|not json" "$STUB/out"'
done
refresh_used() { [ "$(cat "$STUB/args_models")" = models ] && [ "$(cat "$STUB/models_home")" = "$GH_REAL" ] && grep -qx "GROK_AUTH_EARLY_INVALIDATION_SECS=2160" "$STUB/env_models" && grep -qx "GROK_HOME=$GH_REAL" "$STUB/env_models" && grep -qx "TMPDIR=$TMPDIR" "$STUB/env_models" && grep -qx "GROK_MEMORY=0" "$STUB/env_models" && ! grep -q "XAI_API_KEY\|MENTAT_CANARY" "$STUB/env_models" && grep -q fake-token-2 "$STUB/auth_copy"; }
reset; echo 2099-01-01T00:00:00.000000Z >"$STUB/refresh_to"; set_signin 2020-01-01T00:00:00.000000Z; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1800 run); reset_signin
check "an expired Grok sign-in is refreshed by grok models in the user's own Grok home, and the review goes ahead with the refreshed sign-in" '[ "$rc" = 0 ] && grok_ran && refresh_used && [ "$(summary)" = "no findings" ]'
reset; echo 2099-01-01T00:00:00.000000Z >"$STUB/refresh_to"; set_signin "$soon"; rc=$(MENTAT_REVIEW_TIMEOUT_SECONDS=1800 run); reset_signin
check "a Grok sign-in that is too short for the time limit is refreshed too, and the review goes ahead" '[ "$rc" = 0 ] && grok_ran && refresh_used'
reset; echo 2021-01-01T00:00:00.000000Z >"$STUB/refresh_to"; set_signin 2020-01-01T00:00:00.000000Z; rc=$(run); reset_signin
check "a refresh that does not extend an expired sign-in did not finish, with the expired message" '[ "$rc" = 0 ] && summary | grep -q "^did not finish (Grok'"'"'s sign-in expired at 2021-01-01T00:00:00Z" && ! grok_ran && [ -f "$STUB/args_models" ] && ! grep -q fake-token "$STUB/out"'
reset; echo garbage >"$STUB/refresh_to"; set_signin 2020-01-01T00:00:00.000000Z; rc=$(run); reset_signin
check "a sign-in that cannot be read after the refresh did not finish, says so, and prints nothing from the file" '[ "$rc" = 0 ] && summary | grep -q "^did not finish (Grok'"'"'s sign-in could not be read after Mentat tried to refresh it" && ! grok_ran && ! grep -q "fake-token\|garbage" "$STUB/out"'
reset; rc=$(XDG_CACHE_HOME="$root/tmp/cache" run)
check "a cache folder inside a temporary folder is refused before Grok runs, naming the folder only locally" '[ "$rc" = 0 ] && [ "$(summary)" = "did not finish (Mentat'"'"'s cache folder is inside a folder the Grok sandbox denies)" ] && local_line | grep -q "is inside .*; set XDG_CACHE_HOME to a folder outside it" && ! grok_ran && ! grep -qF "$root" "$C"'
reset; mkdir "$root/nogrok"; for t in gh git jq; do ln -s "$(command -v $t)" "$root/nogrok/$t"; done
rc=$(claude_clean; cd "$root/work tree" && PATH="$root/nogrok:/usr/bin:/bin" "$mentat" review --outside 7 >"$STUB/out" 2>&1; echo $?)
check "a missing grok did not finish" '[ "$rc" = 0 ] && [ "$(summary)" = "did not finish (grok is not installed)" ]'

# Interrupts, as in tests/review-local.sh: mentat in its own process group with default INT
# handling, signalled once the sign-in refresh or Grok has started, or the wait for CI has
# begun. Within seconds nothing of the run is left: no process in its group, no Grok, no run folder.
runs() { printf '{"check_runs":[{"name":"test","status":"%s","conclusion":%s}]}\n' "$1" "$2"; }
interrupt() { # $1 ci for a long pause between CI reads, which the signal must not wait out
  local i
  claude_clean
  (
    cd "$root/work tree" || exit 1
    [ "${1:-}" != ci ] || export MENTAT_REVIEW_INTERVAL_SECONDS=30 MENTAT_CI_TIMEOUT_SECONDS=120
    exec perl -e '$SIG{INT} = "DEFAULT"; setpgrp(0, 0); exec @ARGV or die' -- "$mentat" review --outside 7 >"$STUB/out" 2>&1
  ) &
  ip=$! ready=no
  for i in $(seq 100); do
    if [ -f "$STUB/model_pid" ] || grep -q '^Waiting for CI' "$STUB/out" 2>/dev/null; then ready=yes; break; fi
    sleep 0.1
  done
  before=$(left_over) took=$SECONDS
  kill -INT -- "-$ip"
  wait "$ip"
  for i in $(seq 50); do kill -0 -- "-$ip" 2>/dev/null || break; sleep 0.1; done
  took=$((SECONDS - took))
}
gone() { [ "$ready" = yes ] && [ "$took" -lt 10 ] && ! kill -0 -- "-$ip" 2>/dev/null && { [ ! -f "$STUB/model_pid" ] || ! kill -0 "$(cat "$STUB/model_pid")" 2>/dev/null; } && [ -z "$(left_over)" ]; }
reset; touch "$STUB/models_hang"; set_signin 2020-01-01T00:00:00.000000Z; interrupt; reset_signin
check "INT to its process group while grok models refreshes the sign-in stops it within seconds" 'gone'
kill -9 -- "-$ip" 2>/dev/null
reset; touch "$STUB/hang"; interrupt
check "INT to its process group while Grok runs stops Grok and removes the run folder within seconds" '[ -n "$before" ] && [ -s "$STUB/cwd" ] && [ ! -e "$(dirname "$(cat "$STUB/cwd")")" ] && gone'
kill -9 -- "-$ip" 2>/dev/null
reset; runs in_progress null >"$STUB/check_runs.json"; interrupt ci
check "INT to its process group during the wait for CI leaves no process, removes the run folder within seconds and posts nothing" 'gone && [ "$(comments)" = 0 ]'
kill -9 -- "-$ip" 2>/dev/null

# Grok's failures in a row are kept in its own record, keyed by the adapter's name: a
# sign-in refusal is raised at once, a refusal for usage or billing (below) at the first
# one in a row, and any other failure from the second in a row.
REC="$cache/mentat/reviewer-failures-grok"
raised() { grep '^mentat: tell the maintainer now:' "$STUB/out"; }
git -C "$root/seed" push -q "$root/origin.git" "$H:refs/pull/8/head"
reset; rm "$GH_USER/auth.json"; rc=$(run 7); reset_signin
check "a Grok sign-in refusal is raised at once: one line naming Grok, one failure, the pull request and the reason" '[ "$rc" = 0 ] && [ "$(raised)" = "mentat: tell the maintainer now: Grok has failed 1 time in a row (owner/repo#7): Grok is not signed in: there is no auth.json in its home (run grok login)" ] && [ "$(cut -d" " -f2,3 "$REC")" = "fail owner/repo#7" ] && ! grok_ran'
stub_reset; echo 1 >"$STUB/exit_code"; rc=$(run 8)
check "a Grok run failure next is the second in a row: raised with both pull requests and its kept log by path only, no log text" '[ "$(raised | wc -l | tr -d " ")" = 1 ] && raised | grep -qF "mentat: tell the maintainer now: Grok has failed 2 times in a row (owner/repo#7, owner/repo#8): Grok exited with status 1; its log may hold credentials, so it is not printed. The maintainer can read it at $TMPDIR/mentat-log.grok." && ! grep -q "SECRET-LOG-TEXT\|DEBUG-LOG-TEXT" "$STUB/out"'
stub_reset; runs completed '"failure"' >"$STUB/check_runs.json"; rc=$(run 7)
check "a checked Grok reply ends the run of failures, even when CI then fails and nothing is posted" '[ "$rc" = 4 ] && [ "$(tail -n 1 "$REC" | cut -d" " -f2,3)" = "ok owner/repo#7" ]'
stub_reset; reply 'No result line here.'; rc=$(run 7)
check "a Grok reply with no result line after a checked reply is the first failure in a row, not raised" '[ "$(summary)" = "did not finish (Grok'"'"'s reply has no final REVIEW RESULT line)" ] && [ -z "$(raised)" ] && [ "$(tail -n 1 "$REC" | cut -d" " -f2,3)" = "fail owner/repo#7" ]'
mkdir -p "$root/badcache" && : >"$root/badcache/mentat"
stub_reset; rm "$GH_USER/auth.json"; rc=$(XDG_CACHE_HOME="$root/badcache" run 7); reset_signin
check "with a cache folder that cannot be used, a sign-in refusal is still raised, as one failure on this pull request" '[ "$(raised)" = "mentat: tell the maintainer now: Grok has failed 1 time in a row (owner/repo#7): Grok is not signed in: there is no auth.json in its home (run grok login)" ]'
# The raise line and the comment hold no text from Grok's output; the local line keeps its stop reason.
CANARY="CANARY-STOP-REASON-4821"
reset; reply 'Partial.' "$CANARY"; run 7 >/dev/null; stub_reset; reply 'Partial.' "$CANARY"; rc=$(run 7)
check "an incomplete Grok run twice in a row: the raise line and the comment leave out Grok's stop reason, which the local line keeps" '[ "$(raised | wc -l | tr -d " ")" = 1 ] && raised | grep -qF "mentat: tell the maintainer now: Grok has failed 2 times in a row (owner/repo#7): Grok did not return a complete review; its log may hold credentials, so it is not printed. The maintainer can read it at $TMPDIR/mentat-log.grok." && ! raised | grep -qF "$CANARY" && ! grep -qF "$CANARY" "$C" && local_line | grep -qF "stop reason: $CANARY; its log"'
reset

# A Grok run refused for usage or billing: only the message of an error object in Grok's JSON
# output is read for it. The reason is Mentat's own words, with no text from the run, and it is
# raised at the first failure when it is the first out-of-usage one in the row; the kept log
# is still named by its path.
USAGE="Grok refused this run for usage or billing; the maintainer can top up or wait for the usage limit to reset, and reviews and second opinions go on without Grok"
USAGE_CANARY="USAGE-CANARY-5170"
usage_error() { jq -cn --arg m "$1 $USAGE_CANARY" '{type: "error", message: $m}' >"$STUB/out_json"; }
usage_named() { # $1 description
  check "$1: did not finish in Mentat's words, raised at the first failure, its log kept, no run text printed or posted" '[ "$(summary)" = "did not finish ($USAGE)" ] && [ "$(raised | wc -l | tr -d " ")" = 1 ] && raised | grep -qF "mentat: tell the maintainer now: Grok has failed 1 time in a row (owner/repo#7): $USAGE; its log may hold credentials, so it is not printed. The maintainer can read it at $TMPDIR/mentat-log.grok." && [ "$(cut -d" " -f2,3 "$REC")" = "fail owner/repo#7" ] && p=$(kept_log) && grep -q "$USAGE_CANARY" "$p" && ! grep -q "$USAGE_CANARY\|SECRET-LOG-TEXT\|DEBUG-LOG-TEXT\|exited with status\|stop reason" "$STUB/out" "$C"'
}
reset; usage_error "Request failed with status 402 Payment Required:"; echo 1 >"$STUB/exit_code"; rc=$(run 7)
usage_named "an out-of-usage error object with exit 1"
reset; usage_error "Request failed with status 402 Payment Required:"; rc=$(run 7)
usage_named "an out-of-usage error object with a zero exit"
for m in "STATUS 402" "payment required" "You have Run Out Of Credits." "You have hit your WEEKLY limit." "You've hit your free usage limit." "Usage Balance Exhausted."; do
  reset; usage_error "$m"; echo 1 >"$STUB/exit_code"; rc=$(run 7)
  check "the marker \"$m\", in any case, is an out-of-usage refusal, raised at once" 'raised | grep -qF "(owner/repo#7): $USAGE; its log"'
done
# A marker anywhere but the message of an error object in Grok's JSON output is not one.
not_usage() { # $1 description, $2 expected reason
  frag=$2
  check "$1: not an out-of-usage refusal, today's reason, not raised at the first failure" '[ "$(summary)" = "did not finish ($frag)" ] && ! grep -qF "$USAGE" "$STUB/out" && [ -z "$(raised)" ]'
}
reset; echo 1 >"$STUB/exit_code"; echo "Request failed with status 402 Payment Required" >"$STUB/err_text"; rc=$(run 7)
not_usage "a marker only in Grok's stderr" "Grok exited with status 1"
reset; echo 1 >"$STUB/exit_code"; echo "You have run out of credits" >"$STUB/debug_text"; rc=$(run 7)
not_usage "a marker only in Grok's debug log" "Grok exited with status 1"
printf 'Make the README say change.\nIf Grok answers status 402 Payment Required, say so.\n' >"$root/req dir/usage request.md"
reset; echo 1 >"$STUB/exit_code"; rc=$(runq "$root/req dir/usage request.md")
not_usage "a marker only in the prompt" "Grok exited with status 1"
check "that marker reached Grok's prompt" 'grep -q "status 402 Payment Required" "$STUB/prompt"'
(cd "$root/seed" && git checkout -q -b usage feature && echo "Usage balance exhausted: status 402 Payment Required" >usage.txt &&
  git add usage.txt && git commit -qm usage && git push -q "$root/origin.git" HEAD:refs/pull/9/head && git checkout -q feature)
reset; git -C "$root/seed" rev-parse usage >"$STUB/head"; echo 1 >"$STUB/exit_code"; rc=$(run 9)
not_usage "a marker only in the diff" "Grok exited with status 1"
check "that marker reached Grok's prompt in the diff" 'grep -q "^+Usage balance exhausted: status 402 Payment Required" "$STUB/prompt"'
reset; reply "You have run out of credits." max_turns; rc=$(run 7)
not_usage "a marker in the text of a reply that did not finish" "Grok did not return a complete review"
reset; jq -cn '{type: "result", message: "Request failed with status 402 Payment Required"}' >"$STUB/out_json"; echo 1 >"$STUB/exit_code"; rc=$(run 7)
not_usage "a marker in the message of an object that is not an error" "Grok exited with status 1"
reset; jq -cn '{type: "error", message: "Internal error", detail: "status 402 Payment Required"}' >"$STUB/out_json"; echo 1 >"$STUB/exit_code"; rc=$(run 7)
not_usage "a marker in an error object outside its message" "Grok exited with status 1"
reset

# Out-of-usage refusals in one row of Grok failures in this machine's record (the fail lines
# after the last ok): only the first out-of-usage failure in the row is raised; a later one
# says did not finish in Mentat's words alone. Its fail line carries one fixed word after the
# token, nothing from Grok's output. Other failures keep today's rule.
usage_fail() { # $1 pull request
  stub_reset; usage_error "Request failed with status 402 Payment Required:"; echo 1 >"$STUB/exit_code"
  rc=$(run "${1:-7}")
}
other_fail() { stub_reset; echo 1 >"$STUB/exit_code"; rc=$(run "${1:-7}"); }
signin_fail() { stub_reset; rm "$GH_USER/auth.json"; rc=$(run 7); reset_signin; }
usage_quiet() { [ "$(summary)" = "did not finish ($USAGE)" ] && [ -z "$(raised)" ]; }
# Each record line's kind, pull request, fifth field and field count; then the field counts alone.
rec_fields() { awk '{ print $2, $3, $5, NF }' "$REC"; }
rec_widths() { awk '{ print NF }' "$REC" | tr '\n' ' '; }
usage_raised() { # $1 the expected "Grok has failed ..." part
  [ "$(raised | wc -l | tr -d " ")" = 1 ] && raised | grep -qF "mentat: tell the maintainer now: $1: $USAGE; its log may hold credentials"
}
reset; usage_fail 7; usage_fail 8
check "a second out-of-usage failure in the same row is not raised, and still says did not finish in Mentat's words" 'usage_quiet'
check "each out-of-usage fail line carries the fixed word after its token, and nothing from Grok's output" '[ "$(rec_fields)" = "$(printf "fail owner/repo#7 usage 5\nfail owner/repo#8 usage 5")" ] && ! grep -q "$USAGE_CANARY" "$REC"'
reset; other_fail 7; usage_fail 8
check "an out-of-usage failure after another kind of failure in the row is raised, counting both" 'usage_raised "Grok has failed 2 times in a row (owner/repo#7, owner/repo#8)" && [ "$(rec_widths)" = "4 5 " ]'
usage_fail 7
check "the next out-of-usage failure in that row is not raised" 'usage_quiet'
reset; signin_fail; usage_fail 7
check "an out-of-usage failure after a sign-in refusal in the row is raised once" 'usage_raised "Grok has failed 2 times in a row (owner/repo#7)"'
usage_fail 7
check "the next out-of-usage failure in that row is not raised" 'usage_quiet'
reset; mkdir -p "${REC%/*}" && echo "2026-01-01T00:00:00Z fail owner/repo#5 older-run" >"$REC"; usage_fail 7
check "an older fail line without the word counts as another kind of failure: the out-of-usage failure after it is raised" 'usage_raised "Grok has failed 2 times in a row (owner/repo#5, owner/repo#7)"'
reset; usage_fail 7; signin_fail
check "a sign-in refusal after an out-of-usage failure in the row is still raised" '[ "$(raised)" = "mentat: tell the maintainer now: Grok has failed 2 times in a row (owner/repo#7): Grok is not signed in: there is no auth.json in its home (run grok login)" ]'
reset; usage_fail 7; other_fail 8
check "another failure after an out-of-usage failure is the second in a row and still raised" '[ "$(raised | wc -l | tr -d " ")" = 1 ] && raised | grep -qF "mentat: tell the maintainer now: Grok has failed 2 times in a row (owner/repo#7, owner/repo#8): Grok exited with status 1;"'
reset; usage_fail 7; stub_reset; rc=$(run 7); usage_fail 8
check "a checked Grok reply ends the row: the next out-of-usage failure is raised again, as the first in a row" 'usage_raised "Grok has failed 1 time in a row (owner/repo#8)"'
# A record that cannot be written: a folder in its place, so Grok's run folder is still made.
reset; mkdir -p "$REC"; usage_fail 7; usage_fail 7
check "with a record that cannot be written, every out-of-usage failure is still raised, as one failure on this pull request" 'usage_raised "Grok has failed 1 time in a row (owner/repo#7)"'
rmdir "$REC"
# Out-of-usage lines are counted up to this run's own line: of two runs at the same moment,
# the one whose line comes first raises. $1 is the other run's line, added right after this
# run's own; $2, when given, a line already there before it.
raced_usage() {
  (
    rm -f "$REC"; mkdir -p "${REC%/*}" || exit 1
    [ -z "${2:-}" ] || printf '%s\n' "$2" >"$REC"
    # shellcheck source=/dev/null
    . "$(dirname "$mentat")/../lib/shared.sh" || exit 1
    eval "own_$(declare -f reviewer_record)"
    # shellcheck disable=SC2329 # reviewer_failed calls it
    reviewer_record() { own_reviewer_record "$@" && printf '%s\n' "$other" >>"$REC"; }
    other=$1 repo=owner/repo pr=7
    reviewer_failed grok Grok usage
    # shellcheck disable=SC2154 # set by reviewer_failed in lib/shared.sh
    printf '%s\n' "$review_raise"
  )
}
check "another run's out-of-usage line after this run's own leaves this run raised, as the first in the row" '[ "$(raced_usage "2026-01-01T00:00:02Z fail owner/repo#9 other-run usage")" = "Grok has failed 1 time in a row (owner/repo#7)" ]'
check "another run's out-of-usage line before this run's own leaves this run not raised" '[ -z "$(raced_usage "2026-01-01T00:00:02Z ok owner/repo#9 later-run" "2026-01-01T00:00:01Z fail owner/repo#9 other-run usage")" ]'
reset

# Live profile check. Starts the real Grok through the review, with the sign-in removed
# so that no model is called and nothing is sent, and reads the event Grok writes when it
# applies the generated profile: it must apply, be enforced, and carry the profile's
# grants and denials. That shows the installed Grok accepts what Mentat writes and fails
# closed on it; the stub run above shows what Mentat wrote. It does not exercise the
# kernel rules themselves, which only a tool call inside a model run can (the pull
# request records one such run), and says nothing about Linux.
live="review --outside, grok live profile"
live_run() {
  local real_grok="" d ev
  local IFS=:
  # shellcheck disable=SC2086 # split PATH on colons
  for d in $PATH; do
    [ "$d" != "$root/bin" ] && [ -x "$d/grok" ] && { real_grok="$d/grok"; break; }
  done
  IFS=$' \t\n'
  if [ -z "$real_grok" ]; then printf 'SKIP: %s: grok is not installed (it is optional)\n' "$live"; return 0; fi
  reset; echo "$real_grok" >"$STUB/live"
  rc=$(run)
  ev="$STUB/sandbox-events.jsonl"
  if ! grep -q "Not signed in" "$STUB/live_out" 2>/dev/null; then
    printf 'FAIL: %s: Grok did not start as far as its sign-in check (exit %s): %s\n' "$live" "$rc" "$(head -c 300 "$STUB/live_err" 2>/dev/null)"
    failures=$((failures + 1)); return 0
  fi
  if [ ! -s "$ev" ]; then
    printf 'FAIL: %s: Grok wrote no sandbox event\n' "$live"
    failures=$((failures + 1)); return 0
  fi
  local run_dir
  run_dir=$(dirname "$(sed -n 's/^GROK_HOME=//p' "$STUB/env")")
  if jq -s -e --arg run "$run_dir" --arg real "$GH_REAL" '
      [.[] | select(.event_type == "ProfileApplied")] | .[0] as $e
      | $e != null and $e.profile == "mentat-review" and $e.enforced == true and $e.platform == "macos/seatbelt"
      and ($e.deny_paths | index("/tmp") != null and index("/private/var/folders") != null and index($real) != null and any(.[]; endswith("/Library")) and any(.[]; endswith("/**/.env")))
      and ($e.read_only_paths | index($run + "/in") != null)
      and ($e.read_write_paths | index($run + "/export") != null and any(.[]; endswith("/vendor")))' "$ev" >/dev/null 2>&1; then
    printf 'PASS: %s: %s applied and enforced the profile, with its grants and denials\n' "$live" "$("$real_grok" --version 2>/dev/null | head -n 1)"
  else
    printf 'FAIL: %s: the sandbox event does not show the generated profile enforced: %s\n' "$live" "$(head -c 600 "$ev")"
    failures=$((failures + 1))
  fi
}
if [ "$(uname)" != Darwin ]; then
  printf 'SKIP: %s: %s sandboxing differs from macOS, where Mentat runs\n' "$live" "$(uname)"
else
  live_run
fi

[ "$failures" -eq 0 ]
