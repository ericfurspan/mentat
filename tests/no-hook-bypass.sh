#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-hook-bypass, the PreToolUse hook, and for the rule that
# a quoted or heredoc git commit gets no prompt from any Bash hook in hooks.json.
# Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-hook-bypass"
failures=0
check() { if eval "$2"; then printf 'PASS: no-hook-bypass %s\n' "$1"; else printf 'FAIL: no-hook-bypass %s\n' "$1"; failures=$((failures + 1)); fi; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
unset XDG_CONFIG_HOME XDG_DATA_HOME
mkdir -p "$HOME" "$tmp/bin"
# A gh that records every call and fails, so no case reads GitHub.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/gh-calls"\nexit 99\n' "$tmp" >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

decision_json() {
  jq -n --arg d "$1" --arg c "$2" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$hook"
}
decision() { decision_json "$1" "$2" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
reason() { decision_json "$1" "$2" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }

# A repository with an origin whose HEAD is main, on a feature branch, clean.
g init -q --bare "$tmp/origin.git"
g init -q "$tmp/repo"
g -C "$tmp/repo" remote add origin "$tmp/origin.git"
g -C "$tmp/repo" commit -q --allow-empty -m first
g -C "$tmp/repo" push -q origin main
g -C "$tmp/repo" remote set-head origin main >/dev/null
cp -R "$tmp/repo" "$tmp/feat"
g -C "$tmp/feat" checkout -q -b feat/x

# Real git arguments that skip the hooks are denied.
bypass="Mentat: agents never skip Mentat's git hooks (--no-verify, commit -n or a core.hooksPath override)."
while IFS= read -r cmd; do
  check "denies: $cmd" '[ "$(reason "$tmp/feat" "$cmd")" = "$bypass" ]'
done <<'DENY'
git commit --no-verify -m x
git commit -m x --no-verify
git commit --no-veri -m x
git commit --no-verif -m x
git commit -n -m x
git commit -nm x
git commit -an -m x
git commit -anm x
git -C . commit -n -m x
git push --no-verify
git push --no-verify origin feat/x
git merge --no-verify feat/y
git -c core.hooksPath=/tmp/x commit -m x
git -c core.hookspath=/tmp/x push
git -c CORE.HOOKSPATH=/tmp/x status
git -c core.hooksPath commit -m x
git --config-env core.hooksPath=VAR commit -m x
git --config-env=core.hooksPath=VAR push
git config core.hooksPath /tmp/x
git config --local core.hooksPath /tmp/x
git config set core.hooksPath /tmp/x
git config --unset core.hooksPath
env GIT_TRACE=0 git commit -n -m x
command git commit --no-verify -m x
/usr/bin/git commit --no-verify -m x
true && git commit -n -m x
echo $(git commit --no-verify -m x)
DENY
while IFS= read -r cmd; do
  check "leaves alone: $cmd" '[ "$(decision_json "$tmp/feat" "$cmd")" = "{}" ]'
done <<'PASS'
git commit -m "skip with --no-verify later"
git commit -m --no-verify
git commit -m -n
git commit -F -n
git commit -mn
git commit -C -n
git commit --message -n
git commit --author -n -m x
git commit -am "x"
git commit -- -n
git push -n origin feat/x
git push --dry-run origin feat/x
git log -n 3
git config --get core.hooksPath
git config core.hooksPath
git config get core.hooksPath
git config user.name t
echo git commit --no-verify
echo "git commit -n"
printf '%s\n' 'git -c core.hooksPath=/x commit'
grep -- --no-verify notes.txt
ls
PASS
heredoc_body=$'cat >notes.txt <<EOF\ngit commit --no-verify -m x\ngit -c core.hooksPath=/x push\nEOF'
check "a heredoc body is not a command" '[ "$(decision_json "$tmp/feat" "$heredoc_body")" = "{}" ]'
comment=$'# git commit --no-verify\nls'
check "a comment is not a command" '[ "$(decision_json "$tmp/feat" "$comment")" = "{}" ]'

# A quoted or heredoc git commit gets no prompt from any Bash hook in hooks.json, from a
# clean checkout. Each hook prints exactly {}.
msg_heredoc=$'git commit -m "$(cat <<\'EOF\'\nfix: skip hooks with --no-verify, or -n, or -c core.hooksPath=/x\n\ngh pr create --fill; git push origin main; gh pr comment 7\nEOF\n)"'
msg_quoted='git commit -m "docs: never run git commit --no-verify; gh pr create; git push --force origin main"'
msg_single="git commit -m 'git -c core.hooksPath=/x commit -n && gh release create v1'"
bash_hooks=$(jq -r '.hooks.PreToolUse[] | select(.matcher | split("|") | index("Bash")) | .hooks[].command | sub("^\"\\$\\{CLAUDE_PLUGIN_ROOT\\}\"/"; "")' "$root/hooks/hooks.json")
check "hooks.json wires at least five Bash hooks" '[ "$(printf "%s\n" "$bash_hooks" | grep -c .)" -ge 5 ]'
while IFS= read -r h; do
  [ -n "$h" ] || continue
  for m in msg_heredoc msg_quoted msg_single; do
    out=$(jq -n --arg d "$tmp/feat" --arg c "${!m}" '{tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$root/$h")
    check "$h gives no prompt for a git commit with a ${m#msg_} message" '[ "$out" = "{}" ]'
  done
done <<<"$bash_hooks"

# gh pr create and gh pr new: a real gh command only.
cp -R "$tmp/feat" "$tmp/untracked"
touch "$tmp/untracked/new.txt"
cp -R "$tmp/feat" "$tmp/edited"
printf 'a\n' >"$tmp/edited/file.txt"
g -C "$tmp/edited" add file.txt
g -C "$tmp/edited" commit -q -m file
printf 'b\n' >"$tmp/edited/file.txt"
cp -R "$tmp/feat" "$tmp/staged"
printf 'a\n' >"$tmp/staged/file.txt"
g -C "$tmp/staged" add file.txt
unclean_reason="Mentat: agents push and open pull requests from a clean working tree, and git status lists uncommitted changes. Approve only if you want to go ahead without committing them."
for d in untracked edited staged; do
  while IFS= read -r cmd; do
    check "with uncommitted changes ($d) asks before: $cmd" '[ "$(reason "$tmp/$d" "$cmd")" = "$unclean_reason" ]'
  done <<'ASK'
gh pr create --fill
gh pr create --title "x" --body "y"
gh pr new --draft
git status; gh pr create --fill
git push -u origin feat/x && gh pr create --fill
ASK
done
while IFS= read -r cmd; do
  check "with uncommitted changes leaves alone: $cmd" '[ "$(decision_json "$tmp/edited" "$cmd")" = "{}" ]'
done <<'PASS'
git push
git push -u origin feat/x
git status
gh pr view
gh pr list
gh pr checks
gh -R o/r pr view
gh pr -R o/r view
gh issue create --title x
echo "gh pr create --fill"
git commit -m "then gh pr create --fill"
git commit -m "fix: a; gh pr create --fill"
sh -c "true; gh pr create --fill"
ls
PASS
heredoc_pr=$'cat >notes.txt <<EOF\ngh pr create --fill\nEOF'
check "with uncommitted changes, gh pr create in a heredoc body leaves alone" '[ "$(decision_json "$tmp/edited" "$heredoc_pr")" = "{}" ]'
while IFS= read -r cmd; do
  check "with uncommitted changes asks before: $cmd" '[ "$(reason "$tmp/edited" "$cmd")" = "$unclean_reason" ]'
done <<'ASK'
gh -R o/r pr create --fill
gh --repo o/r pr create --fill
gh pr -R o/r create --fill
gh pr --repo o/r create --fill
gh --repo=o/r pr create --fill
/usr/local/bin/gh pr create -d
GH_REPO=o/r gh pr create --draft
(gh pr create --draft)
gh --repo "o & r" pr create --fill
gh pr -R 'a; b' create --fill
ASK
check "a clean checkout leaves gh pr create alone" '[ "$(decision_json "$tmp/feat" "gh pr create --fill")" = "{}" ]'
check "a quoted separator in a title leaves alone" '[ "$(decision_json "$tmp/feat" "gh pr create --title \"a; b\" --fill")" = "{}" ]'

# A cd earlier in the command sets the directory for the pieces after it.
cp -R "$tmp/edited" "$tmp/my edited"
cp -R "$tmp/feat" "$tmp/my feat"
while IFS= read -r cmd; do
  check "from a clean checkout asks before: $cmd" '[ "$(reason "$tmp/feat" "$cmd")" = "$unclean_reason" ]'
done <<ASK
cd ../edited && gh pr create --fill
cd $tmp/edited && gh pr create --fill
cd "../my edited" && gh pr create --fill
env A=1 cd ../edited && gh pr create --fill
cd ../edited && git push && gh pr create --fill
ASK
# A cd joined by && away from a checkout with changes checks only the directory it goes to.
while IFS= read -r cmd; do
  check "from a checkout with changes, a cd joined by && to a clean one leaves alone: $cmd" '[ "$(decision_json "$tmp/edited" "$cmd")" = "{}" ]'
done <<PASS
cd ../feat && gh pr create --fill
cd "$tmp/my feat" && gh pr create --fill
cd ../feat && gh pr create --title "a; b & c | d" --fill
PASS
# Any other join still checks the session directory too.
while IFS= read -r cmd; do
  check "from a checkout with changes asks before: $cmd" '[ "$(reason "$tmp/edited" "$cmd")" = "$unclean_reason" ]'
done <<ASK
cd ../feat; gh pr create --fill
cd "$tmp/my feat" & gh pr create --fill
(cd ../feat && true) >log && gh pr create --fill
ASK
newline_pr=$'cd ../feat\ngh pr create --fill'
check "from a checkout with changes, a cd on the line before still asks" '[ "$(reason "$tmp/edited" "$newline_pr")" = "$unclean_reason" ]'
multi_pr=$'cd ../feat && gh pr create --title t --body "line one\nline two"'
check "from a checkout with changes, a quoted newline in a pull request body leaves alone" '[ "$(decision_json "$tmp/edited" "$multi_pr")" = "{}" ]'
check "a cd ~/ goes to HOME" '[ "$(HOME="$tmp" reason "$tmp/feat" "cd ~/edited && gh pr create --fill")" = "$unclean_reason" ]'
cont_fill=$'gh pr create \\\n  --fill'
check "a continued line leaves alone: gh pr create --fill" '[ "$(decision_json "$tmp/feat" "$cont_fill")" = "{}" ]'
check "a continued line with uncommitted changes asks before: gh pr create --fill" '[ "$(reason "$tmp/edited" "$cont_fill")" = "$unclean_reason" ]'
# A long inline body stays fast: the hook reads each command before it runs.
row="| \`hooks/no-hook-bypass\` | it's a table row; with a & b, \$x and a \\\\ backslash | yes |"
body=""
for ((k = 0; k < 250; k++)); do body+="$row"$'\n'; done
long="gh pr create --title \"feat: x\" --body \"$body\" --fill"
start=$SECONDS
long_reason=$(reason "$tmp/edited" "$long")
elapsed=$((SECONDS - start))
check "a ${#long}-character pull request body with uncommitted changes asks, in ${elapsed}s (under 20s)" \
  '[ "$long_reason" = "$unclean_reason" ] && [ "$elapsed" -lt 20 ]'

# A pull request whose branch changes agent instruction files asks, from the merge base with origin/<default>.
g init -q "$tmp/ibase"
mkdir -p "$tmp/ibase/skills/x" "$tmp/ibase/prompts" "$tmp/ibase/docs/prompts"
for f in AGENTS.md rules.md prompts/builder.md skills/x/SKILL.md docs/rules.md docs/prompts/x.md README.md; do
  printf 'a\n' >"$tmp/ibase/$f"
done
g -C "$tmp/ibase" add -A
g -C "$tmp/ibase" commit -q -m base
g -C "$tmp/ibase" update-ref refs/remotes/origin/main HEAD
g -C "$tmp/ibase" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
g -C "$tmp/ibase" checkout -q -b feat/i
# branch <name> <change>: a copy of ibase with <change> run in it and committed.
branch() {
  cp -R "$tmp/ibase" "$tmp/$1"
  (cd "$tmp/$1" && eval "$2") >/dev/null
  g -C "$tmp/$1" add -A
  g -C "$tmp/$1" commit -q -m change
}
branch i-agents 'printf "b\n" >>AGENTS.md'
branch i-new 'mkdir -p a/b && printf "x\n" >a/b/AGENTS.override.md'
branch i-claude 'printf "x\n" >docs/CLAUDE.md'
branch i-skill 'printf "b\n" >>skills/x/SKILL.md'
branch i-rules 'printf "b\n" >>rules.md'
branch i-prompts 'printf "b\n" >>prompts/builder.md'
branch i-rename 'g mv AGENTS.md notes.md'
branch i-delete 'g rm -q rules.md'
branch i-other 'printf "b\n" >>README.md; printf "b\n" >>docs/rules.md; printf "b\n" >>docs/prompts/x.md; printf "x\n" >AGENTS.txt'
instr_reason="Mentat: this pull request changes agent instructions, and no design review on record (mentat second-opinion --link) names this branch's item. Approve only if Codex and Grok are off for this session or the change alters no meaning."
for d in i-agents i-new i-claude i-skill i-rules i-prompts i-rename i-delete; do
  while IFS= read -r cmd; do
    check "a branch changing instructions ($d) asks with that reason before: $cmd" '[ "$(reason "$tmp/$d" "$cmd")" = "$instr_reason" ]'
  done <<'ASK'
gh pr create --fill
gh pr new --draft
git push -u origin feat/i && gh pr create --fill
ASK
done
while IFS= read -r cmd; do
  check "a branch changing only other files leaves alone: $cmd" '[ "$(decision_json "$tmp/i-other" "$cmd")" = "{}" ]'
done <<'PASS'
gh pr create --fill
gh pr new --draft
PASS
while IFS= read -r cmd; do
  check "a branch changing instructions leaves alone: $cmd" '[ "$(decision_json "$tmp/i-agents" "$cmd")" = "{}" ]'
done <<'PASS'
git push
git push -u origin feat/i
gh pr view
echo "gh pr create --fill"
PASS
# Without origin/HEAD, origin/main or origin/master is the default.
cp -R "$tmp/i-agents" "$tmp/i-nohead"
g -C "$tmp/i-nohead" symbolic-ref --delete refs/remotes/origin/HEAD
check "a branch changing instructions, no origin/HEAD but origin/main: asks with that reason" \
  '[ "$(reason "$tmp/i-nohead" "gh pr create --fill")" = "$instr_reason" ]'
# No default-branch ref, or no merge base with it: nothing to compare, no prompt.
cp -R "$tmp/i-nohead" "$tmp/i-noref"
g -C "$tmp/i-noref" update-ref -d refs/remotes/origin/main
check "a branch changing instructions, no default-branch ref: leaves alone" '[ "$(decision_json "$tmp/i-noref" "gh pr create --fill")" = "{}" ]'
cp -R "$tmp/i-agents" "$tmp/i-unrelated"
g -C "$tmp/i-unrelated" update-ref refs/remotes/origin/main "$(g -C "$tmp/i-unrelated" commit-tree -m other "$(g -C "$tmp/i-unrelated" mktree </dev/null)")"
check "a branch changing instructions, no merge base with the default branch: leaves alone" \
  '[ "$(decision_json "$tmp/i-unrelated" "gh pr create --fill")" = "{}" ]'
# With uncommitted changes too, one prompt gives both reasons.
cp -R "$tmp/i-agents" "$tmp/i-dirty"
touch "$tmp/i-dirty/new.txt"
check "a branch changing instructions with uncommitted changes: one prompt names both" \
  '[ "$(reason "$tmp/i-dirty" "gh pr create --fill")" = "$unclean_reason $instr_reason" ]'
# A cd is followed as for the clean-tree check.
check "a cd to a branch changing instructions asks before gh pr create" \
  '[ "$(reason "$tmp/feat" "cd ../i-agents && gh pr create --fill")" = "$instr_reason" ]'
check "a cd joined by && away from a branch changing instructions checks only its directory" \
  '[ "$(decision_json "$tmp/i-agents" "cd ../feat && gh pr create --fill")" = "{}" ]'
check "a cd joined by || away from a branch changing instructions still asks before gh pr create" \
  '[ "$(reason "$tmp/i-agents" "cd ../feat || gh pr create --fill")" = "$instr_reason" ]'
check "a cd joined by ; away from a branch changing instructions still asks" \
  '[ "$(reason "$tmp/i-agents" "cd ../i-other; gh pr create --fill")" = "$instr_reason" ]'
# Paths are read from the repository root, even from a subdirectory with diff.relative set.
cp -R "$tmp/i-rules" "$tmp/i-relative"
g -C "$tmp/i-relative" config diff.relative true
check "a branch changing the root rules.md, from a subdirectory with diff.relative: asks with that reason" \
  '[ "$(reason "$tmp/i-relative/docs" "gh pr create --fill")" = "$instr_reason" ]'

# A design review linked to the branch's item, in the record in the shared git folder, asks nothing for that reason.
# on_branch <dir> <branch> [linked id]: a copy of i-agents on <branch>, whose record links the id.
on_branch() {
  cp -R "$tmp/i-agents" "$tmp/$1"
  g -C "$tmp/$1" branch -q -m "$2"
  [ -z "${3:-}" ] || { mkdir -p "$tmp/$1/.git/mentat" && printf 'link 2026-01-02 %s 0123456789ab\n' "$3" >>"$tmp/$1/.git/mentat/second-opinions"; }
}
# The link step writes the record: a review of the idea file's content, then the link.
on_branch l-linked feat/abc-26-branch-key
printf 'An idea.\n' >"$tmp/idea.md"
mkdir -p "$tmp/l-linked/.git/mentat"
printf 'review 2026-01-02 %s %s\n' "$(g -C "$tmp/l-linked" rev-parse HEAD)" "$(printf '%s' "$(cat "$tmp/idea.md")" | shasum -a 256 | cut -c1-12)" >"$tmp/l-linked/.git/mentat/second-opinions"
(cd "$tmp/l-linked" && "$root/bin/mentat" second-opinion --link ABC-26 "$tmp/idea.md" >/dev/null)
check "a branch changing instructions whose item the link step linked leaves alone: feat/abc-26-branch-key" '[ "$(decision_json "$tmp/l-linked" "gh pr create --fill")" = "{}" ]'
on_branch l-bare feat/abc-26 abc-26
check "a branch changing instructions named by a linked id alone leaves alone: feat/abc-26" '[ "$(decision_json "$tmp/l-bare" "gh pr create --fill")" = "{}" ]'
on_branch l-case feat/ABC-26-Key abc-26
check "a linked id matches the branch ignoring case: feat/ABC-26-Key" '[ "$(decision_json "$tmp/l-case" "gh pr create --fill")" = "{}" ]'
on_branch l-unlinked feat/abc-27-key abc-26
check "a branch changing instructions with an unlinked id asks with that reason" '[ "$(reason "$tmp/l-unlinked" "gh pr create --fill")" = "$instr_reason" ]'
on_branch l-longer feat/abc-260-key abc-26
check "a branch id that only starts like a linked one asks: abc-260 for abc-26" '[ "$(reason "$tmp/l-longer" "gh pr create --fill")" = "$instr_reason" ]'
on_branch l-shorter feat/abc-26-branch-key abc-2
check "a linked id never matches the start of a longer number: abc-2 for abc-26" '[ "$(reason "$tmp/l-shorter" "gh pr create --fill")" = "$instr_reason" ]'
on_branch l-inside feat/xabc-26-key abc-26
check "a linked id inside a longer segment asks: xabc-26" '[ "$(reason "$tmp/l-inside" "gh pr create --fill")" = "$instr_reason" ]'
on_branch l-noid feat/branch-key abc-26
check "a branch with no item id asks with that reason" '[ "$(reason "$tmp/l-noid" "gh pr create --fill")" = "$instr_reason" ]'
on_branch l-norecord feat/abc-26-branch-key
check "a missing record asks with that reason" '[ "$(reason "$tmp/l-norecord" "gh pr create --fill")" = "$instr_reason" ]'
on_branch l-unreadable feat/abc-26-branch-key abc-26
chmod 000 "$tmp/l-unreadable/.git/mentat/second-opinions"
check "an unreadable record asks with that reason" '[ "$(reason "$tmp/l-unreadable" "gh pr create --fill")" = "$instr_reason" ]'
chmod 600 "$tmp/l-unreadable/.git/mentat/second-opinions"
on_branch l-detached feat/abc-26-branch-key abc-26
g -C "$tmp/l-detached" checkout -q --detach
check "a detached HEAD asks with that reason" '[ "$(reason "$tmp/l-detached" "gh pr create --fill")" = "$instr_reason" ]'
# Worktrees share the record: written from one worktree's git folder, read in another and in the main one.
on_branch w-main feat/abc-26-main
g -C "$tmp/w-main" worktree add -q -b feat/abc-30-a "$tmp/w-a"
g -C "$tmp/w-main" worktree add -q -b feat/abc-26-b "$tmp/w-b"
shared=$(g -C "$tmp/w-a" rev-parse --git-common-dir)
mkdir -p "$shared/mentat" && printf 'link 2026-01-02 abc-26 0123456789ab\n' >"$shared/mentat/second-opinions"
check "a record shared with a worktree: written from one worktree, a linked branch in another leaves alone" '[ "$(decision_json "$tmp/w-b" "gh pr create --fill")" = "{}" ]'
check "a record shared with a worktree: a linked branch in the main worktree, from a subdirectory, leaves alone" '[ "$(decision_json "$tmp/w-main/docs" "gh pr create --fill")" = "{}" ]'
check "a record shared with a worktree: an unlinked branch in the worktree that wrote it asks" '[ "$(reason "$tmp/w-a" "gh pr create --fill")" = "$instr_reason" ]'

# Without a cwd in the input, the process directory is used.
nocwd() { (cd "$tmp/edited" && jq -n '{tool_name: "Bash", tool_input: {command: "gh pr create --fill"}}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'); }
check "no cwd in the input: uses the process directory" '[ "$(nocwd)" = "$unclean_reason" ]'
out=$(jq -n --arg d "$tmp/edited" '{tool_name: "Write", cwd: $d, tool_input: {command: "gh pr create --fill; git commit -n"}}' | "$hook")
check "another tool passes with {}" '[ "$out" = "{}" ]'
check "never calls gh" '[ ! -e "$tmp/gh-calls" ]'

check "hooks.json runs it on PreToolUse for Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | select(endswith(\"/hooks/no-hook-bypass\"))] | length == 1" "$root/hooks/hooks.json" >/dev/null'
check "hooks.json no longer runs the command-text commit and push hooks" \
  '! grep -q -e no-commit-secrets -e no-default-push "$root/hooks/hooks.json"'

[ "$failures" -eq 0 ]
