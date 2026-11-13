#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for hooks/no-repo-admin, the PreToolUse hook. Prints PASS/FAIL per
# case; exits 1 on any FAIL.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/no-repo-admin"
failures=0
check() { if eval "$2"; then printf 'PASS: no-repo-admin %s\n' "$1"; else printf 'FAIL: no-repo-admin %s\n' "$1"; failures=$((failures + 1)); fi; }

# The hook decides from its input alone: a gh that records every call and fails
# proves it never reads GitHub.
root_tmp=$(mktemp -d)
trap 'rm -rf "$root_tmp"' EXIT
export STUB="$root_tmp/stub"
mkdir -p "$STUB" "$root_tmp/bin"
cat >"$root_tmp/bin/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/calls"
exit 99
STUBEOF
chmod +x "$root_tmp/bin/gh"
export PATH="$root_tmp/bin:$PATH"

output() { jq -n --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}' | "$hook"; }
decision() { output "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }

while IFS= read -r cmd; do
  check "denies: $cmd" '[ "$(decision "$cmd")" = deny ]'
done <<'DENY'
gh release create v1.0 --notes x
gh release edit v1.0 --draft=false
gh release delete v1.0 --yes
gh release upload v1.0 dist.tgz
gh release delete-asset v1.0 dist.tgz
gh -R o/r release create v1
gh release -R o/r create v1
gh secret set TOKEN
gh secret delete TOKEN
gh secret remove TOKEN
gh variable set NAME --body x
gh variable delete NAME
gh variable remove NAME
gh repo edit --visibility public
gh repo delete o/r --yes
gh repo rename newname
gh repo archive o/r
gh repo unarchive o/r
gh ruleset create
gh rs delete 1
gh api -X PATCH repos/o/r -f description=x
gh api --method DELETE repos/o/r
gh api -X PUT repos/o/r/branches/main/protection --input p.json
gh api -X DELETE repos/{owner}/{repo}/branches/main/protection/required_signatures
gh api -X POST repos/o/r/rulesets --input r.json
gh api --method=PUT /repos/o/r/actions/secrets/TOKEN -f encrypted_value=x
gh api -XPOST repos/o/r/actions/variables -f name=A -f value=b
gh api -X PUT repos/o/r/environments/prod
gh api -X PUT repos/o/r/collaborators/someone
gh api repos/o/r/hooks -f url=https://example.invalid
gh api -X POST repos/o/r/keys -f key=x
gh api repos/o/r/releases -f tag_name=v1
gh api -X POST repos/o/r/pages --input p.json
gh api -X PUT repos/o/r/vulnerability-alerts
gh api -X DELETE repos/o/r/automated-security-fixes
gh api -X post "repos/o/r/releases?x=1" -f tag_name=v1
gh api -X POST "repos/$repo/hooks" -f url=x
gh api -X PATCH https://api.github.com/repos/o/r -f description=x
echo start && gh release create v1
X=1 gh secret set A
env GH_REPO=o/r gh secret set A
/opt/homebrew/bin/gh repo delete o/r --yes
v=$(gh release create v1)
(gh variable set A --body b)
DENY
c='gh api \
  -X PUT \
  repos/o/r/branches/main/protection \
  --input p.json'
check "denies a write after line continuations" '[ "$(decision "$c")" = deny ]'
while IFS= read -r cmd; do
  check "passes with {}: $cmd" '[ "$(output "$cmd")" = "{}" ]'
done <<'PASS'
gh release list
gh release view v1
gh release download v1
gh secret list
gh variable get NAME
gh repo view o/r
gh repo clone o/r
gh ruleset list
gh ruleset view 1
gh rs check main
gh pr create --title "gh release create notes"
gh api repos/o/r
gh api repos/o/r/releases
gh api repos/o/r/branches/main/protection
gh api -X GET repos/o/r/releases -f per_page=5
gh api -X POST repos/o/r/issues -f title=t
gh api -X POST "repos/$repo/issues" -f title=t
gh api -X POST repos/o/r/issues/7/comments -f body=hooks
gh api -X DELETE repos/o/r/git/refs/heads/topic
gh api -X POST repos/o/r/pulls -f title=t -f head=x -f base=main
gh api graphql -f query=x
echo "gh release create v1"
echo "done; gh release create v1"
git commit -m "x && gh secret set TOKEN"
git commit -m "gh secret set TOKEN"
printf '%s\n' 'gh repo delete o/r --yes'
echo 'done; gh release create v1'
ls # done; gh repo delete o/r
PASS
c='git commit -m "$(cat <<'"'"'EOF'"'"'
chore: gh release create v2 and gh api -X PATCH repos/o/r
EOF
)"'
check "passes a commit message heredoc naming the commands" '[ "$(output "$c")" = "{}" ]'
c='cat >notes.md <<EOF
gh secret set TOKEN
EOF'
check "passes a heredoc body naming a command" '[ "$(output "$c")" = "{}" ]'
read_input=$(jq -n '{tool_name: "Read", tool_input: {file_path: "x"}}')
check "passes a non-Bash tool with {}" '[ "$("$hook" <<<"$read_input")" = "{}" ]'
check "the reason names the rule" \
  '[ "$(output "gh release create v1" | jq -r .hookSpecificOutput.permissionDecisionReason)" = "Mentat: agents never publish releases or change secrets, variables or repository settings; the maintainer does." ]'
body=$(awk 'BEGIN { for (i = 0; i < 2000; i++) printf "line %d with \\$x and a; gh release create word\n", i }')
check "a body of about 100 KB is read in under 10 seconds and passes" \
  's=$(date +%s); r=$(output "gh pr create --title t --body \"$body\""); e=$(( $(date +%s) - s )); [ "$r" = "{}" ] && [ "$e" -lt 10 ]'
check "reads nothing from GitHub" '[ ! -f "$STUB/calls" ]'
check "hooks.json runs it on PreToolUse for Bash" \
  'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Bash\") | .hooks[].command | select(endswith(\"/hooks/no-repo-admin\"))] | length == 1" "$root/hooks/hooks.json" >/dev/null'

[ "$failures" -eq 0 ]
