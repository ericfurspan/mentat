#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-guard-edits, the PreToolUse hook, with a temporary
# home. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root_dir/hooks/no-guard-edits"
failures=0
check() { if eval "$2"; then printf 'PASS: no-guard-edits %s\n' "$1"; else printf 'FAIL: no-guard-edits %s\n' "$1"; failures=$((failures + 1)); fi; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOME="$root/stub home"
unset XDG_CONFIG_HOME XDG_DATA_HOME
work="$root/work"
mkdir -p "$HOME/.local/bin" "$work/.git" "$work/sub" "$work/dest"

# bash_out <command> [cwd]: prints what the hook prints for a Bash command.
bash_out() { jq -n --arg c "$1" --arg d "${2:-$work}" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' | "$hook"; }
bash_decision() { bash_out "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
# file_out <tool> <path>: prints what the hook prints for a file tool.
file_out() {
  case "$1" in NotebookEdit) key=notebook_path ;; *) key=file_path ;; esac
  jq -n --arg t "$1" --arg k "$key" --arg p "$2" --arg d "$work" \
    '{hook_event_name: "PreToolUse", tool_name: $t, cwd: $d, tool_input: {($k): $p, content: "x"}}' | "$hook"
}
file_decision() { file_out "$@" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }

# File tools: each tool, on each kind of guard file.
for tool in Edit Write MultiEdit NotebookEdit; do
  while IFS= read -r p; do
    check "$tool denies $p" '[ "$(file_decision "$tool" "$p")" = deny ]'
  done <<FILES
.mentat-privacy
$work/sub/.mentat-privacy
$HOME/.config/mentat/pinned-remotes
$HOME/.local/share/mentat/git-guard/hooks/pre-commit
$HOME/.local/share/mentat/git-guard
$HOME/.local/bin/git
$HOME/.gitconfig
$HOME/.config/git/config
.git/config
$root/other/.git/config
.git/config.worktree
$root/main/.git/worktrees/topic/config.worktree
sub/../.mentat-privacy
$HOME/.local/bin/../bin/./git
FILES
  while IFS= read -r p; do
    check "$tool passes $p" '[ "$(file_out "$tool" "$p")" = "{}" ]'
  done <<FILES
README.md
$work/sub/notes.md
.mentat-privacy.md
$HOME/.config/mentat/private-words
$HOME/.local/share/mentat/other
$HOME/.local/bin/gitk
.git/config.lock
.git/HEAD
$root/main/.git/worktrees/topic/HEAD
FILES
done

# Bash commands that write to a guard file.
while IFS= read -r cmd; do
  check "denies: $cmd" '[ "$(bash_decision "$cmd")" = deny ]'
done <<'DENY'
echo "codex: checkout" > .mentat-privacy
echo x >> sub/.mentat-privacy
printf 'x' >| .mentat-privacy
echo x 2> .mentat-privacy
echo x &> .mentat-privacy
echo x > ~/.gitconfig
echo x >> "$HOME/.config/mentat/pinned-remotes"
echo x > ${HOME}/.config/git/config
echo x | tee .mentat-privacy
echo x | tee -a /dev/null ~/.config/mentat/pinned-remotes
mv .mentat-privacy old
mv new .mentat-privacy
mv ~/.local/share/mentat /tmp/gone
mv /tmp/x/git ~/.local/bin/
mv /tmp/x/config .git/
cp /tmp/policy .mentat-privacy
cp /tmp/x/.mentat-privacy sub/
cp /tmp/x/git ~/.local/bin/
cp -r /tmp/x/git-guard ~/.local/share/mentat/
rm .mentat-privacy
rm -f ~/.local/bin/git
rm -rf ~/.local/share/mentat/git-guard/hooks
rm -rf ~/.local/share/mentat
rm -rf ~/.local
rm -rf ~
rm -rf /
rm -- .mentat-privacy
ln -sf /tmp/evil ~/.local/bin/git
ln -s /tmp/evil .mentat-privacy
sed -i '' 's/none/checkout/' .mentat-privacy
sed -i.bak 's/a/b/' .git/config
sed -Ei 's/a/b/' .git/config
sed --in-place 's/a/b/' ~/.gitconfig
chmod 644 .mentat-privacy
chmod -R u+w ~/.local/share/mentat/git-guard
git rm .mentat-privacy
git mv .mentat-privacy old
git checkout main -- .mentat-privacy
git checkout -- sub/.mentat-privacy
git restore --source=main .mentat-privacy
git -C sub restore .mentat-privacy
git config core.hooksPath /tmp/hooks
git config --global core.hooksPath /tmp/hooks
git config --local core.hookspath=/tmp/hooks x
git config --unset core.hooksPath
git config --global --unset-all core.HooksPath
git config set core.hooksPath /tmp/hooks
git -C sub config core.hooksPath .githooks
cd .git && echo x > config
cd sub && echo x > .mentat-privacy
cd ~/.local/bin && rm git
echo start; rm .mentat-privacy
x=$(rm .mentat-privacy)
echo "$(echo x > .mentat-privacy)"
(cd sub && rm .mentat-privacy)
sudo rm ~/.gitconfig
env A=b rm .mentat-privacy
/bin/rm .mentat-privacy
DENY
c='echo x \
  > .mentat-privacy'
check "denies a redirect after a line continuation" '[ "$(bash_decision "$c")" = deny ]'
c='cat <<EOF > .mentat-privacy
codex: checkout
EOF'
check "denies a heredoc written to a guard file" '[ "$(bash_decision "$c")" = deny ]'
check "denies a relative write from the input's cwd" '[ "$(bash_decision "echo x > git" "$HOME/.local/bin")" = deny ]'
rel_input=$(jq -n --arg d "$HOME/.local/bin" '{tool_name: "Write", cwd: $d, tool_input: {file_path: "git"}}')
check "denies a relative file tool path from the input's cwd" \
  '[ "$("$hook" <<<"$rel_input" | jq -r .hookSpecificOutput.permissionDecision)" = deny ]'

# Reads, other files, and guard names that are only text pass.
while IFS= read -r cmd; do
  check "passes with {}: $cmd" '[ "$(bash_out "$cmd")" = "{}" ]'
done <<'PASS'
cat .mentat-privacy
grep codex .mentat-privacy
cat ~/.gitconfig
cp .mentat-privacy /tmp/policy-copy
cp ~/.local/bin/git /tmp/git-copy
ls 2>&1 >/dev/null
echo x >&2
echo x 2>/dev/null
cat < .mentat-privacy
diff <(cat .mentat-privacy) other
echo x > notes.md
echo x > .mentat-privacy.md
echo x > sub/config
cd sub && echo x > config
rm -rf /tmp/scratch-repo
rm -rf ~/.local/share/other
rm -rf .git/hooks/old
mv a b
mv notes.md ~/
mv tool ~/.local/bin/
mv x ~/.config/
mv x ..
sed 's/a/b/' .git/config
sed -n 's/i/x/p' .mentat-privacy
chmod +x script.sh
git checkout main
git checkout -b topic
git restore notes.md
git rm notes.md
git config user.name Someone
git config --get core.hooksPath
git config core.hooksPath
git config --get-regexp core.hooksPath
git config get core.hooksPath
git config --list
git status
echo "echo x > .mentat-privacy"
echo "done; rm .mentat-privacy now"
git commit -m "x && echo y > .mentat-privacy && z"
echo 'rm ~/.gitconfig'
echo 'done; rm .mentat-privacy now'
git commit -m "chore: stop writing core.hooksPath and .mentat-privacy"
git commit -m "rm .mentat-privacy"
ls # done; rm .mentat-privacy
printf '%s\n' "git config core.hooksPath x" | cat
PASS
c='git commit -m "$(cat <<'"'"'EOF'"'"'
fix: echo x > .mentat-privacy and rm ~/.local/bin/git
EOF
)"'
check "passes a commit message heredoc naming guard files" '[ "$(bash_out "$c")" = "{}" ]'
c='cat >notes.md <<EOF
rm .mentat-privacy
git config core.hooksPath /tmp/x
EOF'
check "passes a heredoc body naming guard writes" '[ "$(bash_out "$c")" = "{}" ]'
c='cat <<-EOF > notes.md
	echo x > ~/.gitconfig
	EOF'
check "passes a tab-stripped heredoc body naming a guard write" '[ "$(bash_out "$c")" = "{}" ]'

# XDG folders add their own copies of the home paths.
check "denies a write to the guard folder under XDG_DATA_HOME" \
  '[ "$(XDG_DATA_HOME="$root/data" bash_decision "echo x > \"$root/data/mentat/git-guard/scan\"")" = deny ]'
check "denies a write to the pins under XDG_CONFIG_HOME" \
  '[ "$(XDG_CONFIG_HOME="$root/conf" bash_decision "echo x > \"$root/conf/mentat/pinned-remotes\"")" = deny ]'

check "the reason names the guard files" \
  '[ "$(bash_out "rm .mentat-privacy" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "Mentat: agents never change Mentat'"'"'s guard files (the privacy file, pinned remotes, the git guard and its wrapper, git config); the maintainer does." ]'
check "the core.hooksPath reason names the setting" \
  '[ "$(bash_out "git config core.hooksPath x" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "Mentat: agents never set core.hooksPath, which would skip Mentat'"'"'s git guard." ]'
read_input=$(jq -n '{tool_name: "Read", tool_input: {file_path: ".mentat-privacy"}}')
check "passes the Read tool on a guard file" '[ "$("$hook" <<<"$read_input")" = "{}" ]'
body=$(awk 'BEGIN { for (i = 0; i < 2000; i++) printf "line %d with \\$x and a; rm .mentat-privacy > ~/.gitconfig\n", i }')
check "a body of about 100 KB is read in under 10 seconds and passes" \
  's=$(date +%s); r=$(bash_out "git commit -m \"$body\""); e=$(( $(date +%s) - s )); [ "$r" = "{}" ] && [ "$e" -lt 10 ]'
check "hooks.json runs it on PreToolUse for the file tools and Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Edit|Write|MultiEdit|NotebookEdit|Bash\") | .hooks[].command | select(endswith(\"/hooks/no-guard-edits\"))] | length == 1" "$root_dir/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
