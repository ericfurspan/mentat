#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat review --grok`, using a real git origin, a stub gh
# and a stub grok. Prints PASS/FAIL per case; exits 1 on any FAIL. One case also
# starts the real Grok (when installed) with the generated sandbox profile and no
# sign-in, so no model is called: see "Live profile check" below.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
# The per-run folder must be outside the temporary folders, so the tests use a
# folder under the real ~/.cache, which mentat's default does too.
mkdir -p "$HOME/.cache" || { echo "FAIL: review --grok: cannot create $HOME/.cache"; exit 1; }
cache=$(mktemp -d "$HOME/.cache/mentat-test.XXXXXX") || { echo "FAIL: review --grok: cannot create a folder under $HOME/.cache"; exit 1; }
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
check() { if eval "$2"; then printf 'PASS: review --grok %s\n' "$1"; else printf 'FAIL: review --grok %s\n' "$1"; failures=$((failures + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export TMPDIR="$root/tmp" XDG_CACHE_HOME="$cache"

# An origin with main and pull request 7, whose head changes README and adds files
# that archive attributes and odd names would trip up.
git init -q --bare -b main "$root/origin.git"
git init -q -b main "$root/seed"
(cd "$root/seed" && echo base >README && git add README && git commit -qm base && git push -q "$root/origin.git" main &&
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
# $STUB/out_json (stdout) and $STUB/exit_code. In live mode it hands over to the
# real Grok instead, without the sign-in, and keeps the sandbox event.
# (mentat starts it with an empty environment, so its own path is written in.)
{ printf '#!/usr/bin/env bash\nSTUB=%q\nREAL_HOME=%q\n' "$STUB" "$real_home"; cat; } >"$root/bin/grok" <<'STUBEOF'
[ "${1:-}" = --version ] && { echo "grok 9.9.9 (stub)"; exit 0; }
if [ "${1:-}" = models ]; then
  printf '%s\n' "$@" >"$STUB/args_models"
  env | sort >"$STUB/env_models"
  printf '%s\n' "$GROK_HOME" >"$STUB/models_home"
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
for a in "${args[@]}"; do [ "$prev" = --debug-file ] && echo "DEBUG-LOG-TEXT" >"$a"; prev=$a; done
[ -f "$STUB/hang" ] && exec sleep 30
# @EXPORT@ in the reply becomes the export's path, which is where Grok works.
sed "s|@EXPORT@|$(pwd -P)|g" "$STUB/out_json"
echo "SECRET-LOG-TEXT" >&2
exit "$(cat "$STUB/exit_code")"
STUBEOF
# codex: only to compare the shared criteria with review --local's.
cat >"$root/bin/codex" <<'STUBEOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo codex-stub; exit 0; }
cat >"$STUB/codex_prompt"
while [ $# -gt 0 ]; do [ "$1" = -o ] && printf 'ok\n\nREVIEW RESULT: NO FINDINGS\n' >"$2"; shift; done
STUBEOF
chmod +x "$root/bin/gh" "$root/bin/grok" "$root/bin/codex"
# CI waits are short, as in tests/review.sh; a passed check with no finish time returns at once.
export PATH="$root/bin:$PATH" MENTAT_REVIEW_INTERVAL_SECONDS=1 MENTAT_CI_TIMEOUT_SECONDS=2 MENTAT_CI_GRACE_SECONDS=1

reply() { # $1 text, $2 stop reason
  jq -n --arg t "$1" --arg s "${2:-end_turn}" '{text: $t, stopReason: $s, sessionId: "s", modelUsage: {"grok-stub": {}}}' >"$STUB/out_json"
}
reset() {
  rm -rf "${STUB:?}"/*
  echo "$H" >"$STUB/head"
  echo 0 >"$STUB/exit_code"
  reply $'The pull request changes README.\n\nNothing to flag.\n\nREVIEW RESULT: NO FINDINGS'
  echo '{"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}' >"$STUB/check_runs.json"
}
run() { (cd "$root/work tree" && "$mentat" review --grok "${1:-7}" >"$STUB/out" 2>&1); echo $?; }
comments() { find "$STUB" -name 'comment.*' | wc -l | tr -d ' '; }
grok_ran() { [ -f "$STUB/args" ]; }
# The posted review: a heading line, then the bullets and the reply folded, then the result line.
heading() { [ "$(head -n 1 "$STUB/comment.2")" = "## Local Grok review of $H: $1, spec fingerprint ${2:-none}" ]; }
folded() { sed -n '/^<details><summary>Full review<\/summary>$/,/^<\/details>$/p' "$STUB/comment.2"; }
fold_shape() { # $1 the final REVIEW RESULT line
  [ "$(sed -n '/^<details><summary>Full review<\/summary>$/{n;s/^$/blank/;p;}' "$STUB/comment.2")" = blank ] && [ "$(tail -n 3 "$STUB/comment.2")" = "</details>

$1" ] && [ "$(grep -c '^</details>$' "$STUB/comment.2")" = 1 ] && [ "$(tail -n 1 "$STUB/comment.2")" = "$1" ] && [ "$(grep -v '^[[:space:]]*$' "$STUB/comment.2" | tail -n 1)" = "$1" ]
}
reply_in_fold() { folded | sed -n "/^---\$/,\$p" | sed "1,2d;\$d"; }

# A git that, right after any fetch of pull/7/head, also fetches main in the same checkout:
# what a second review running at the same time does. Only the cases that use it (race)
# put it on the PATH, and the git it calls is the one found here, before that.
mkdir -p "$root/racebin"
cat >"$root/racebin/git" <<RACEEOF
#!/usr/bin/env bash
"$(command -v git)" "\$@" || exit \$?
case "\$*" in
  *pull/7/head*) [ "\${1:-}" = -C ] && "$(command -v git)" -C "\$2" fetch -q origin main ;;
esac
RACEEOF
chmod +x "$root/racebin/git"
race() { PATH="$root/racebin:$PATH" run; }
left_over() { ls -A "$cache/mentat" 2>/dev/null; }

reset; rc=$(run)
check "no findings exits 0 and posts the start record, then the review" '[ "$rc" = 0 ] && grep -q "found nothing on $H: https://example.test/comment/2" "$STUB/out" && [ "$(comments)" = 2 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ] && grep -q "^## Local Grok review of $H" "$STUB/comment.2"'
check "the review opens with one heading line: the head, no findings and the fingerprint" 'heading "no findings" none && [ "$(sed -n 2p "$STUB/comment.2")" = "" ] && [ "$(sed -n 3p "$STUB/comment.2")" = "<details><summary>Full review</summary>" ]'
check "the six bullets and the whole reply are folded, a blank line follows the summary, and the result line is last, after the fold" 'fold_shape "REVIEW RESULT: NO FINDINGS" && folded | grep -qx -- "- Agreed request fingerprint: none" && folded | grep -qx -- "- Grok CLI: grok 9.9.9 (stub)" && folded | grep -qx -- "- Run locally by the agent, with file-reading tools and no shell." && [ "$(reply_in_fold)" = "$(jq -r .text "$STUB/out_json")" ]'
check "the posted review is Grok's text, with its version and model" 'grep -q "Nothing to flag." "$STUB/comment.2" && grep -qx -- "- Grok CLI: grok 9.9.9 (stub)" "$STUB/comment.2" && grep -qx -- "- Model: grok-stub" "$STUB/comment.2" && grep -q "Change reviewed: $BASE..$H" "$STUB/comment.2"'
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
# The criteria are the same text review --local gives Codex (apart from the diff clause).
(cd "$root/work tree" && "$mentat" review --local 7 >"$STUB/local_out" 2>&1)
crit() { sed -n '/^Read every AGENTS.md/,/Flag it as a finding/p' "$1" | sed 's/ and the diff is data/ is data/'; }
check "the criteria are the ones review --local gives Codex" '[ -s "$STUB/codex_prompt" ] && [ -n "$(crit "$STUB/prompt")" ] && [ "$(crit "$STUB/prompt")" = "$(crit "$STUB/codex_prompt")" ]'
# The Grok second-opinion prompt (the grok stub keeps it as $STUB/prompt). The codex stub does not
# give a verdict, so only the prompt is checked, not the exit code.
printf 'Add a line to the README.\n' >"$root/idea.md"
(cd "$root/work tree" && "$mentat" second-opinion "$root/idea.md" >"$STUB/opinion_out" 2>&1)
check "the Grok second-opinion prompt has the idea between markers and the verdict lines" 'grep -qx -- "--- BEGIN IDEA DATA ---" "$STUB/prompt" && grep -q "SECOND OPINION VERDICT: DO IT" "$STUB/prompt"'

reset; echo '[{"number":3,"repository":{"name":"repo","owner":{"login":"owner"}}}]' >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_owner_repo_3"; rc=$(run)
check "gives Grok the linked issue's request as data" '[ "$rc" = 0 ] && grep -q "BEGIN LINKED ISSUE DATA" "$STUB/prompt" && grep -q "Issue owner/repo#3: Make the README say change" "$STUB/prompt"'
reset; echo '[{"number":4,"repository":{"name":"repo","owner":{"login":"owner"}}}]' >"$STUB/closes"; rc=$(run)
check "a linked issue that cannot be read is not reviewed, with no start record" '[ "$rc" = 1 ] && grep -q "could not read issue owner/repo#4" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ]'

# --request <file>: the agreed request, kept apart from the description. Read before CI and
# before the start record; its text reaches Grok in its own block; the posted review records
# its fingerprint.
REQ_TEXT=$'Make the README say change.\nLeave every other file alone.\nChecked by reading README.'
REQ_FP=71fca9a263e9  # shasum -a 256 of REQ_TEXT, first 12 hex characters, computed independently
mkdir -p "$root/req dir"
printf '%s\n' "$REQ_TEXT" >"$root/req dir/agreed request.md"
runq() { (cd "$root/work tree" && "$mentat" review --grok --request "$1" "${2:-7}" >"$STUB/out" 2>&1); echo $?; }
reset; rc=$(runq "$root/req dir/agreed request.md")
check "--request: the request reaches Grok in its own labeled block, a path with spaces works" '[ "$rc" = 0 ] && sed -n "/^--- BEGIN AGREED REQUEST DATA ---\$/,/^--- END AGREED REQUEST DATA ---\$/p" "$STUB/prompt" | grep -qxF "Leave every other file alone." && grep -qx -- "--- END AGREED REQUEST DATA ---" "$STUB/prompt" && grep -q "BEGIN PULL REQUEST DATA" "$STUB/prompt"'
check "--request: the posted review records the request fingerprint (first 12 hex of its SHA-256)" 'grep -qx -- "- Agreed request fingerprint: $REQ_FP" "$STUB/comment.2" && [ "${#REQ_FP}" = 12 ] && heading "no findings" "$REQ_FP" && folded | grep -qx -- "- Agreed request fingerprint: $REQ_FP"'
reset; rc=$(run)
check "no --request: no agreed request block, and the review says the fingerprint is none" '[ "$rc" = 0 ] && ! grep -q "AGREED REQUEST DATA" "$STUB/prompt" && grep -qx -- "- Agreed request fingerprint: none" "$STUB/comment.2" && heading "no findings" none && folded | grep -qx -- "- Agreed request fingerprint: none"'
reset; echo '[{"number":3,"repository":{"name":"repo","owner":{"login":"owner"}}}]' >"$STUB/closes"; printf 'Make the README say change\nThe README must say change, nothing else.\n' >"$STUB/issue_owner_repo_3"; rc=$(runq "$root/req dir/agreed request.md")
check "--request with a linked issue: both blocks reach Grok" '[ "$rc" = 0 ] && grep -qx -- "--- BEGIN AGREED REQUEST DATA ---" "$STUB/prompt" && grep -qx -- "--- BEGIN LINKED ISSUE DATA ---" "$STUB/prompt" && grep -q "Issue owner/repo#3: Make the README say change" "$STUB/prompt"'
printf ' \n\t\n\n' >"$root/blank.md"
printf 'x\n' >"$root/locked.md"; chmod 000 "$root/locked.md"
unread() { # $1 description, $2 file, $3 expected fragment of the reason
  rc=$(runq "$2"); frag=$3
  check "--request $1: not reviewed (exit 1) before CI, Grok does not run, no start record, nothing is posted" '[ "$rc" = 1 ] && grep -q "not reviewed: .*$frag" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && ! grep -q "check-runs\|pr view\|api user" "$STUB/calls" 2>/dev/null && [ -z "$(left_over)" ]'
}
reset; unread "with a whitespace-only file" "$root/blank.md" "is empty"
reset; unread "with a missing file" "$root/no such file.md" "could not read the agreed request file"
reset; unread "with an unreadable file" "$root/locked.md" "could not read the agreed request file"
reset; unread "with a directory" "$root" "could not read the agreed request file"
reset; unread "with an empty file name (an empty variable)" "" "request file name for #7 is empty"
chmod 600 "$root/locked.md"
rc=$("$mentat" review --request "$root/req dir/agreed request.md" --grok 7 >"$STUB/out" 2>&1; echo $?)
check "--request before the mode is a usage error (exit 64)" '[ "$rc" = 64 ]'

reset; reply $'- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "findings exit 2 and are posted" '[ "$rc" = 2 ] && grep -q "posted findings on $H: https://example.test/comment/2" "$STUB/out" && grep -q "P1 README:1" "$STUB/comment.2"'
check "a FINDINGS reply's heading says findings, and its findings are inside the fold" 'heading findings none && fold_shape "REVIEW RESULT: FINDINGS" && folded | grep -qx -- "- P1 README:1 wrong text"'

# Grok works in an export under the per-run folder and may cite files by its absolute path.
# The posted review holds no such path, and links the file at the reviewed commit.
REPO_URL="https://github.com/owner/repo/blob/$H"
reset; reply $'Changes README.\n\n- P2 [README:1](@EXPORT@/README:1): wrong text\n- P2 [lib/shared.sh:93-95](@EXPORT@/lib/shared.sh:93-95): a range\n- P3 [a dir/a file.txt](@EXPORT@/a dir/a file.txt#L4): a spaced name\n- P3 see @EXPORT@/lib/x.sh:7 and `@EXPORT@/lib/y.sh`\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
RUN_DIR=$(dirname "$(cat "$STUB/cwd")")
check "a finding that cites the export is posted with repository links and no local path" '[ "$rc" = 2 ] && ! grep -qF "$(cat "$STUB/cwd")" "$STUB/comment.2" && ! grep -qF "$RUN_DIR" "$STUB/comment.2" && grep -qF "[README:1]($REPO_URL/README#L1): wrong text" "$STUB/comment.2" && grep -qF "[lib/shared.sh:93-95]($REPO_URL/lib/shared.sh#L93-L95): a range" "$STUB/comment.2" && grep -qF "[a dir/a file.txt]($REPO_URL/a%20dir/a%20file.txt#L4): a spaced name" "$STUB/comment.2"'
check "a plain mention of the export, bare or in code, becomes the repository path, and the rest of the review is kept" 'grep -qF -- "- P3 see lib/x.sh:7 and \`lib/y.sh\`" "$STUB/comment.2" && grep -qx "Changes README." "$STUB/comment.2" && [ "$(tail -n 1 "$STUB/comment.2")" = "REVIEW RESULT: FINDINGS" ]'
check "the rewritten reply is inside the fold, intact, with the result line after the fold" 'fold_shape "REVIEW RESULT: FINDINGS" && [ "$(reply_in_fold)" = "Changes README.

- P2 [README:1]($REPO_URL/README#L1): wrong text
- P2 [lib/shared.sh:93-95]($REPO_URL/lib/shared.sh#L93-L95): a range
- P3 [a dir/a file.txt]($REPO_URL/a%20dir/a%20file.txt#L4): a spaced name
- P3 see lib/x.sh:7 and \`lib/y.sh\`

REVIEW RESULT: FINDINGS" ]'
reset; reply $'- P3 not @EXPORT@-other/z or /Users/other/export/w\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a path that only starts with the export's name, and other absolute paths, are left alone" '[ "$rc" = 2 ] && grep -qxF -- "- P3 not $(cat "$STUB/cwd")-other/z or /Users/other/export/w" "$STUB/comment.2"'
reset; reply $'Could not finish.\n\nREVIEW RESULT: INCOMPLETE - could not read @EXPORT@/lib/z.sh'; rc=$(run)
check "an INCOMPLETE reason that names the export is posted and printed as a repository path" '[ "$rc" = 1 ] && ! grep -qF "$(cat "$STUB/cwd")" "$STUB/comment.2" "$STUB/out" && grep -qx "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" "$STUB/comment.2" && heading incomplete none && fold_shape "REVIEW RESULT: INCOMPLETE - could not read lib/z.sh" && grep -q "incomplete: could not read lib/z.sh" "$STUB/out"'

# An INCOMPLETE reply is a complete reply: the review is posted as the record and is not reviewed.
reset; reply $'I could not read the linked issue.\n\nREVIEW RESULT: INCOMPLETE - the linked issue could not be read'; rc=$(run)
check "an INCOMPLETE reply with a reason is posted and not reviewed (exit 1), with no did-not-finish comment or log" '[ "$rc" = 1 ] && [ "$(comments)" = 2 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ] && heading incomplete none && fold_shape "REVIEW RESULT: INCOMPLETE - the linked issue could not be read" && folded | grep -qx "I could not read the linked issue." && ! grep -rq "Grok review did not finish" "$STUB/out" "$STUB"/comment.* && grep -q "not reviewed: Grok says the review is incomplete: the linked issue could not be read" "$STUB/out" && ! grep -q "posted findings\|found nothing\|can read it at" "$STUB/out" && [ -z "$(left_over)" ]'

# Grok runs at once; the wait for CI on the same head comes after it, and the start comment and
# the review are posted only once CI passed, so a run that is not posted leaves Grok's one run unused.
runs() { printf '{"check_runs":[{"name":"test","status":"%s","conclusion":%s}]}\n' "$1" "$2"; }
# The model run, the CI reads and the posts, in the order gh and grok saw them.
order() { sed -n -e 's/^grok$/model/p' -e 's#.*/check-runs$#ci#p' -e 's/^pr comment .*/post/p' "$STUB/calls" | uniq | tr '\n' ' '; }
# The text printed after the exit-4 line naming the head, without the blank line that follows it.
unposted() { sed "1,/^Review of $H, not posted and not a round:\$/d" "$STUB/out" | sed 1d; }
status() { (cd "$root/work tree" && "$mentat" status 7 2>&1); }
reset; runs in_progress null >"$STUB/check_runs.json"; runs completed '"success"' >"$STUB/check_runs_later.json"; rc=$(run)
check "a review that finishes before CI posts its start comment and review only after CI passes on its head (exit 0)" '[ "$rc" = 0 ] && [ "$(comments)" = 2 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ] && [ "$(order)" = "model ci post " ] && [ "$(cat "$STUB/ci_reads")" -ge 2 ] && ! grep -q "not posted" "$STUB/out"'
check "a posted review is Grok's one run" 'status | grep -q "grok: done,"'
reset; reply $'- P1 README:1 wrong text\n\nREVIEW RESULT: FINDINGS'; runs in_progress null >"$STUB/check_runs.json"; runs completed '"failure"' >"$STUB/check_runs_later.json"; rc=$(run)
check "CI failing after the review exits 4, posts nothing, not even the start comment, and names the failing check" '[ "$rc" = 4 ] && grok_ran && [ "$(comments)" = 0 ] && [ "$(order)" = "model ci " ] && grep -q "CI did not pass on $H" "$STUB/out" && grep -qx -- "- test" "$STUB/out" && [ -z "$(left_over)" ]'
check "CI failing after the review prints the review after a line saying it was not posted and is not a round" '[ "$(unposted)" = "$(jq -r .text "$STUB/out_json")" ]'
check "a review not posted for failed CI leaves Grok not run" 'status | grep -q "grok: none,"'
runs completed '"success"' >"$STUB/check_runs.json"; rm "$STUB/check_runs_later.json" "$STUB/args"; rc=$(run)
check "so a later review --grok is not refused, and posts (exit 2)" '[ "$rc" = 2 ] && grok_ran && [ "$(comments)" = 2 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ]'
reset; runs queued null >"$STUB/check_runs.json"; rc=$(run)
check "CI still running at the timeout exits 4, posts nothing and prints the review" '[ "$rc" = 4 ] && grok_ran && [ "$(comments)" = 0 ] && grep -q "CI did not finish on $H within 2 seconds" "$STUB/out" && [ "$(unposted)" = "$(jq -r .text "$STUB/out_json")" ]'
reset; runs in_progress null >"$STUB/check_runs.json"; runs completed '"success"' >"$STUB/check_runs_later.json"; echo 3333333333333333333333333333333333333333 >"$STUB/push_on_ci"; rc=$(run)
check "a head that moves during the wait for CI exits 3 and posts nothing, not even the start comment" '[ "$rc" = 3 ] && grok_ran && [ "$(comments)" = 0 ] && [ "$(order)" = "model ci " ] && grep -q "the head moved from $H" "$STUB/out" && [ -z "$(left_over)" ]'
reset; runs completed '"failure"' >"$STUB/check_runs.json"; echo 3333333333333333333333333333333333333333 >"$STUB/push_on_ci"; rc=$(run)
check "a head that moves while CI fails on the reviewed head exits 3, not 4, and posts nothing, not even the start comment" '[ "$rc" = 3 ] && grok_ran && [ "$(comments)" = 0 ] && grep -q "the head moved from $H; run mentat review --grok again" "$STUB/out" && ! grep -q "CI did not pass\|not posted" "$STUB/out" && [ -z "$(left_over)" ]'
reset; echo '{"check_runs":[]}' >"$STUB/check_runs.json"; rc=$(run)
check "no CI check on the head: says so, then posts (exit 0)" '[ "$rc" = 0 ] && [ "$(comments)" = 2 ] && grep -qx "No CI checks ran on $H" "$STUB/out"'
# --require-ci: a head where no CI check ran is not a pass, and Grok's run is not used.
reset; echo '{"check_runs":[]}' >"$STUB/check_runs.json"; rc=$(cd "$root/work tree" && "$mentat" review --grok --require-ci 7 >"$STUB/out" 2>&1; echo $?)
check "--require-ci with no CI check on the head exits 4, says so, prints the review and posts nothing, not even the start comment" '[ "$rc" = 4 ] && grok_ran && [ "$(comments)" = 0 ] && grep -qx "No CI checks ran on $H" "$STUB/out" && [ "$(unposted)" = "$(jq -r .text "$STUB/out_json")" ] && [ -z "$(left_over)" ]'
check "--require-ci: a review not posted for a head with no CI leaves Grok not run" 'status | grep -q "grok: none,"'
rm "$STUB/args"; rc=$(run)
check "so a later review --grok without --require-ci is not refused, and posts (exit 0)" '[ "$rc" = 0 ] && grok_ran && [ "$(comments)" = 2 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ]'
reset; rc=$(cd "$root/work tree" && "$mentat" review --grok --require-ci --request "$root/req dir/agreed request.md" 7 >"$STUB/out" 2>&1; echo $?)
check "--require-ci before --request, with CI passed, posts as usual (exit 0)" '[ "$rc" = 0 ] && [ "$(comments)" = 2 ] && grep -qx -- "- Agreed request fingerprint: $REQ_FP" "$STUB/comment.2"'
reset; echo 4444444444444444444444444444444444444444 >"$STUB/head"; rc=$(run)
check "a head the fetch does not match is exit 3, with no start record" '[ "$rc" = 3 ] && ! grok_ran && [ "$(comments)" = 0 ]'
reset; rc=$(race)
check "a fetch of main by another process between this review's fetch and its read is not a moved head (exit 0)" '[ "$rc" = 0 ] && grep -q "found nothing on $H" "$STUB/out" && [ "$(comments)" = 2 ] && [ -z "$(git -C "$root/work tree" for-each-ref refs/mentat)" ]'

# The review must not write the checkout's origin/main either: another review may be using it.
stale=$(git -C "$root/work tree" commit-tree -m stale "$(git -C "$root/work tree" rev-parse 'HEAD^{tree}')")
git -C "$root/work tree" update-ref refs/remotes/origin/main "$stale"
reset; rc=$(run)
check "a review leaves the checkout's origin/main alone" '[ "$rc" = 0 ] && [ "$(git -C "$root/work tree" rev-parse refs/remotes/origin/main)" = "$stale" ]'
git -C "$root/work tree" update-ref refs/remotes/origin/main "$BASE"

# Every way Grok's run can fail is found before the wait for CI and before any comment: nothing is
# posted, so Grok's one run is not used, and the raw log is kept privately, not printed.
not_finished() { # $1 description, $2 expected reason fragment
  frag=$2
  check "$1: exit 1 before CI is read, nothing posted, no log printed" '[ "$rc" = 1 ] && grep -q "not reviewed: .*$frag" "$STUB/out" && [ "$(comments)" = 0 ] && ! grep -q check-runs "$STUB/calls" && ! grep -q "SECRET-LOG-TEXT" "$STUB/out" && [ -z "$(left_over)" ]'
}
reset; echo 3 >"$STUB/exit_code"; rc=$(run)
not_finished "Grok exiting non-zero" "exited with status 3"
check "it keeps a private copy of the raw log for the maintainer" 'p=$(sed -n "s/.*can read it at //p" "$STUB/out"); [ -n "$p" ] && grep -q SECRET-LOG-TEXT "$p"'
reset; reply $'Looks fine.\n\nREVIEW RESULT: NO FINDINGS' max_turn_requests; rc=$(run)
not_finished "a failure stop reason with a plausible result line" "stop reason: max_turn_requests"
reset; reply $'Looks fine.\n\nREVIEW RESULT: NO FINDINGS' future_reason; rc=$(run)
not_finished "an unknown stop reason" "stop reason: future_reason"
reset; echo '{"type":"error","message":"Not signed in. SECRET-LOG-TEXT"}' >"$STUB/out_json"; rc=$(run)
not_finished "an error object with a zero exit" "stop reason: none"
reset; echo '{"type":"error","message":"Not signed in"}' >"$STUB/out_json"; echo 1 >"$STUB/exit_code"; rc=$(run)
not_finished "an error object with exit 1" "exited with status 1"
reset; printf '{"text": "Nothing.\\n\\nREVIEW RESULT: NO FIN' >"$STUB/out_json"; rc=$(run)
not_finished "truncated output" "complete review"
reset; reply $'Looks fine to me.'; rc=$(run)
not_finished "a reply without a result line" "no final REVIEW RESULT line"
reset; reply $'Could not finish.\n\nREVIEW RESULT: INCOMPLETE'; rc=$(run)
not_finished "a bare INCOMPLETE line" "no final REVIEW RESULT line"
reset; reply $'Could not finish.\n\nREVIEW RESULT: INCOMPLETE -'; rc=$(run)
not_finished "an INCOMPLETE line with a dash and no reason" "no final REVIEW RESULT line"
reset; reply $'Could not finish.\n\nREVIEW RESULT: INCOMPLETE -   '; rc=$(run)
not_finished "an INCOMPLETE line with a dash and only spaces" "no final REVIEW RESULT line"
reset; reply $'REVIEW RESULT: NO FINDINGS\n\nBut actually there is a problem.'; rc=$(run)
not_finished "a result line that is not last" "no final REVIEW RESULT line"
reset; reply "   "; rc=$(run)
not_finished "an empty text" "complete review"
reset; { cat "$STUB/out_json"; cat "$STUB/out_json"; } >"$STUB/out_json.2"; mv "$STUB/out_json.2" "$STUB/out_json"; rc=$(run)
not_finished "two JSON objects" "complete review"
reset; : >"$STUB/out_json"; rc=$(run)
not_finished "no output" "complete review"
reset; touch "$STUB/hang"; rc=$(cd "$root/work tree" && MENTAT_GROK_TIMEOUT_SECONDS=2 "$mentat" review --grok 7 >"$STUB/out" 2>&1; echo $?)
not_finished "a timeout (MENTAT_GROK_TIMEOUT_SECONDS)" "did not finish within 2 seconds"
check "a timeout still leaves the debug record in the private log" 'p=$(sed -n "s/.*can read it at //p" "$STUB/out"); [ -n "$p" ] && grep -q DEBUG-LOG-TEXT "$p" && ! grep -q DEBUG-LOG-TEXT "$STUB/out" && [ "$(comments)" = 0 ]'
reset; rc=$(cd "$root/work tree" && MENTAT_REVIEW_TIMEOUT_SECONDS=0 "$mentat" review --grok 7 >"$STUB/out" 2>&1; echo $?)
check "the Codex review timeout does not limit Grok" '[ "$rc" = 0 ]'
reset; touch "$STUB/result_fails"; rc=$(run)
check "a failed post of the review, after the start comment: exit 1, a did-not-finish comment, no review, no log printed" '[ "$rc" = 1 ] && [ "$(comments)" = 2 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ] && grep -q "^Grok review did not finish on $H: .*could not post the review" "$STUB/comment.2" && ! grep -rq "^## Local Grok review" "$STUB"/comment.* && ! grep -q "SECRET-LOG-TEXT" "$STUB/out" "$STUB"/comment.* && [ -z "$(left_over)" ]'

# The publish check, on each comment, right before its post.
held_file() { sed -n 's/.*the maintainer can read it at \([^;]*\).*/\1/p' "$STUB/out"; }
says_held() { # $1 category, $2 the match: named the category and a file holding the match, and did not repeat it
  grep -q "not reviewed: .*the comment holds $1, so it was not posted" "$STUB/out" && grep -qiF -- "$2" "$(held_file)" && ! grep -qiF -- "$2" "$STUB/out"
}
printf '# a comment\n\nStubCodename\nreview started on\ndid not finish on\n' >"$LIST"
reset; rc=$(run)
check "a start comment with a hit is not posted, is kept, and nothing is posted" '[ "$rc" = 1 ] && [ "$(comments)" = 0 ] && grok_ran && says_held "a configured private name" "review started on" && [ "$(cat "$(held_file)")" = "Grok review started on $H" ]'
printf '# a comment\n\nStubCodename\ndid not finish on\n' >"$LIST"
reset; reply $'- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a failure comment with a hit is skipped, with no second try, and the review exits as not reviewed" '[ "$rc" = 1 ] && [ "$(comments)" = 1 ] && [ "$(cat "$STUB/comment.1")" = "Grok review started on $H" ] && grep -q "not reviewed: the review was held back and not posted" "$STUB/out" && [ -z "$(left_over)" ]'
printf '# a comment\n\nStubCodename\n' >"$LIST"
reset; reply $'- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a review with a word from the list is not posted, is kept whole, and the pull request says it did not finish" '[ "$rc" = 1 ] && [ "$(comments)" = 2 ] && says_held "a configured private name" stubcodename && grep -q "^## Local Grok review of $H" "$(held_file)" && [ "$(cat "$STUB/comment.2")" = "Grok review did not finish on $H: the review was held back and not posted" ]'
reset; reply "$(printf -- '- P3 at %s/notes.md\n\nREVIEW RESULT: FINDINGS' "$HOME")"; rc=$(run)
check "a review with the home path is the same" '[ "$rc" = 1 ] && [ "$(comments)" = 2 ] && says_held "a local path" "$HOME" && ! grep -qF "$HOME" "$STUB/comment.2"'
reset; touch "$STUB/lookup_fails"; reply $'- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a failed visibility lookup counts as public" '[ "$rc" = 1 ] && says_held "a configured private name" stubcodename && ! grep -rq stubcodename "$STUB"/comment.*'
reset; touch "$STUB/private"; reply $'- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a private repository's review is posted" '[ "$rc" = 2 ] && grep -q "about stubcodename" "$STUB/comment.2"'
check "a hit looks up the reviewed repository" 'grep -qF "repo view owner/repo --json isPrivate" "$STUB/calls"'
reset; rc=$(run)
check "no hit: posts, with no visibility lookup" '[ "$rc" = 0 ] && [ "$(comments)" = 2 ] && ! grep -q isPrivate "$STUB/calls"'
rm "$LIST"
reset; reply $'- P3 about stubcodename\n\nREVIEW RESULT: FINDINGS'; rc=$(run)
check "a missing word list never blocks" '[ "$rc" = 2 ] && grep -q "about stubcodename" "$STUB/comment.2"'
reset; reply "$(printf -- '- P3 at %s/notes.md\n\nREVIEW RESULT: FINDINGS' "$HOME")"; rc=$(run)
check "with a missing word list the home path is still found" '[ "$rc" = 1 ] && says_held "a local path" "$HOME"'

reset; echo 3333333333333333333333333333333333333333 >"$STUB/moved_head"; rc=$(run)
check "a head that moves during the review exits 3 and posts nothing, not even the start comment" '[ "$rc" = 3 ] && grok_ran && [ "$(comments)" = 0 ] && [ -z "$(left_over)" ]'
reset; touch "$STUB/comment_fails"; rc=$(run)
check "a start record that cannot be posted is not reviewed, and the review is not posted" '[ "$rc" = 1 ] && grep -q "could not post the start comment" "$STUB/out" && grok_ran && [ "$(comments)" = 0 ]'
reset; rm "$GH_USER/auth.json"; rc=$(run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "no Grok sign-in is not reviewed, with no start record" '[ "$rc" = 1 ] && grep -q "Grok is not signed in" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && [ ! -e "$STUB/args_models" ]'
reset; printf '{"https://auth.x.ai::test":{"expires_at":"2020-01-01T00:00:00.000000Z","key":"fake-token"}}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "an expired Grok sign-in is not reviewed, with no start record and its token not printed" '[ "$rc" = 1 ] && grep -q "Grok'"'"'s sign-in expired at 2020-01-01T00:00:00Z" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && ! grep -q fake-token "$STUB/out" && [ -f "$STUB/args_models" ]'
reset; printf '{"https://auth.x.ai::test":{"expires_at":"2099-01-01T00:00:00.000000Z","key":"fake-token"}}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "a Grok sign-in with its expiry in the future is reviewed" '[ "$rc" = 0 ] && grok_ran && [ ! -e "$STUB/args_models" ]'
soon=$(date -u -v+600S +%Y-%m-%dT%H:%M:%S.000000Z)
reset; printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token"}}\n' "$soon" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(MENTAT_GROK_TIMEOUT_SECONDS=1800 run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "a Grok sign-in that expires before the time limit would end is not reviewed, with no start record and its token not printed" '[ "$rc" = 1 ] && grep -q "Grok'"'"'s sign-in expires at ${soon:0:19}Z, before this run'"'"'s 1800-second time limit and 5 minutes of setup would end" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && ! grep -q fake-token "$STUB/out" && [ -f "$STUB/args_models" ]'
reset; printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token"}}\n' "$soon" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; rc=$(MENTAT_GROK_TIMEOUT_SECONDS=60 run); printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"
check "the same sign-in with a 60-second time limit is reviewed" '[ "$rc" = 0 ] && grok_ran && [ ! -e "$STUB/args_models" ]'
# A sign-in that is expired, or too short for the run, is first refreshed by grok models
# in the user's own Grok home; the stub's models branch rewrites it only when refresh_to exists.
set_signin() { printf '{"https://auth.x.ai::test":{"expires_at":"%s","key":"fake-token"}}\n' "$1" >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; }
reset_signin() { printf '{"fake":"credential"}\n' >"$GH_USER/auth.json"; chmod 600 "$GH_USER/auth.json"; }
refresh_used() { [ "$(cat "$STUB/args_models")" = models ] && [ "$(cat "$STUB/models_home")" = "$GH_REAL" ] && grep -qx "GROK_AUTH_EARLY_INVALIDATION_SECS=2160" "$STUB/env_models" && grep -qx "GROK_HOME=$GH_REAL" "$STUB/env_models" && grep -qx "TMPDIR=$TMPDIR" "$STUB/env_models" && grep -qx "GROK_MEMORY=0" "$STUB/env_models" && ! grep -q "XAI_API_KEY\|MENTAT_CANARY" "$STUB/env_models" && grep -q fake-token-2 "$STUB/auth_copy"; }

reset; echo 2099-01-01T00:00:00.000000Z >"$STUB/refresh_to"; set_signin 2020-01-01T00:00:00.000000Z; rc=$(MENTAT_GROK_TIMEOUT_SECONDS=1800 run); reset_signin
check "an expired Grok sign-in is refreshed by grok models in the user's own Grok home, and the review goes ahead with the refreshed sign-in" '[ "$rc" = 0 ] && grok_ran && refresh_used'
reset; echo 2099-01-01T00:00:00.000000Z >"$STUB/refresh_to"; set_signin "$soon"; rc=$(MENTAT_GROK_TIMEOUT_SECONDS=1800 run); reset_signin
check "a Grok sign-in that is too short for the time limit is refreshed too, and the review goes ahead" '[ "$rc" = 0 ] && grok_ran && refresh_used'
reset; echo 2021-01-01T00:00:00.000000Z >"$STUB/refresh_to"; set_signin 2020-01-01T00:00:00.000000Z; rc=$(run); reset_signin
check "a refresh that does not extend an expired sign-in is not reviewed, with the expired message and no start record" '[ "$rc" = 1 ] && grep -q "Grok'"'"'s sign-in expired at 2021-01-01T00:00:00Z" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && [ -f "$STUB/args_models" ] && ! grep -q fake-token "$STUB/out"'
reset; echo garbage >"$STUB/refresh_to"; set_signin 2020-01-01T00:00:00.000000Z; rc=$(run); reset_signin
check "a sign-in that cannot be read after the refresh is not reviewed, names grok login, and prints nothing from the file" '[ "$rc" = 1 ] && grep -q "Grok'"'"'s sign-in could not be read after Mentat tried to refresh it" "$STUB/out" && grep -q "grok login" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && ! grep -q "fake-token\|garbage" "$STUB/out"'
reset; set_signin "$soon"; rc=$(MENTAT_GROK_TIMEOUT_SECONDS=soon run); reset_signin
check "a time limit that is not a number is not reviewed, without a refresh" '[ "$rc" = 1 ] && grep -q "could not work out when Grok'"'"'s time limit ends (MENTAT_GROK_TIMEOUT_SECONDS is soon)" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ] && [ ! -e "$STUB/args_models" ]'
reset; rc=$(cd "$root/work tree" && XDG_CACHE_HOME="$root/tmp/cache" "$mentat" review --grok 7 >"$STUB/out" 2>&1; echo $?)
check "a cache folder inside a temporary folder is refused before any start record" '[ "$rc" = 1 ] && grep -q "is inside .*, which the Grok review denies" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ]'
reset; mkdir "$root/nogrok"; for t in gh git jq; do ln -s "$(command -v $t)" "$root/nogrok/$t"; done
rc=$(cd "$root/work tree" && PATH="$root/nogrok:/usr/bin:/bin" "$mentat" review --grok 7 >"$STUB/out" 2>&1; echo $?)
check "a missing grok is not reviewed" '[ "$rc" = 1 ] && grep -q "grok is not installed" "$STUB/out"'

# Grok runs once per pull request, and only this account's own start comment counts.
start_comment() { jq -n --arg u "$1" --arg b "Grok review started on $H" '[{user: {login: $u}, body: $b}]'; }
reset; start_comment someone-else >"$STUB/issue_comments.json"; rc=$(run)
check "a start comment from another account does not stop the review" '[ "$rc" = 0 ] && grok_ran && [ "$(comments)" = 2 ]'
reset; start_comment agent-bot >"$STUB/issue_comments.json"; rc=$(run)
check "the signed-in account own start comment stops it: not reviewed, no new comment, Grok does not run" '[ "$rc" = 1 ] && grep -q "Grok already reviewed #7" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ]'
reset; touch "$STUB/spoof_during_ci"; rc=$(run)
check "this account's start comment appearing before the post (here during the CI wait) stops it: exit 1, nothing posted" '[ "$rc" = 1 ] && grep -q "Grok already reviewed #7" "$STUB/out" && grok_ran && [ "$(comments)" = 0 ] && [ -z "$(left_over)" ]'
reset; touch "$STUB/user_fails"; rc=$(run)
check "an account that cannot be read is not reviewed" '[ "$rc" = 1 ] && grep -q "could not read which GitHub account" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ]'
reset; touch "$STUB/comments_fail"; rc=$(run)
check "comments that cannot be read are not reviewed" '[ "$rc" = 1 ] && grep -q "could not read the comments" "$STUB/out" && ! grok_ran && [ "$(comments)" = 0 ]'

for args in "--grok" "--grok abc" "--grok 7 8" "--grok --local 7" "--grok --local" "--local --grok 7" "--grok 7 --local" "--grok --require-ci --require-ci 7" "--require-ci --grok 7"; do
  # shellcheck disable=SC2086 # the words are the arguments
  rc=$("$mentat" review $args >/dev/null 2>&1; echo $?)
  check "usage error (exit 64) for: review $args" '[ "$rc" = 64 ]'
done

# Live profile check. Starts the real Grok through the review, with the sign-in removed
# so that no model is called and nothing is sent, and reads the event Grok writes when it
# applies the generated profile: it must apply, be enforced, and carry the profile's
# grants and denials. That shows the installed Grok accepts what Mentat writes and fails
# closed on it; the stub run above shows what Mentat wrote. It does not exercise the
# kernel rules themselves, which only a tool call inside a model run can (the pull
# request records one such run), and says nothing about Linux.
live="review --grok live profile"
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
