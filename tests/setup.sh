#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# (File-wide: each check is a string evaluated after its case runs.)
# Behavior tests for `mentat setup`, using a stub gh that serves one JSON file
# per API path. Prints PASS/FAIL per case; exits 1 on any FAIL.
set -uo pipefail

mentat="$(cd "$(dirname "$0")/.." && pwd)/bin/mentat"
root=$(mktemp -d)
trap 'chmod -R u+w "$root" 2>/dev/null; rm -rf "$root"' EXIT
export STUB="$root/stub"
mkdir -p "$STUB" "$root/bin" "$root/cwd"
failures=0
check() { if eval "$2"; then printf 'PASS: setup %s\n' "$1"; else printf 'FAIL: setup %s\n' "$1"; failures=$((failures + 1)); fi; }

# Serves $STUB/api/<path with / ? = & as _>.json; a missing file is an API error.
# With --paginate, a <same name>.page2 file is served as the next page.
# Any call that is not an explicit GET is recorded in $STUB/writes and fails.
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(printf '%s' "$*" | tr '\n' ' ')" >>"$STUB/calls"
[ "$1" = api ] || { echo "$*" >>"$STUB/writes"; exit 99; }
shift
method="" path="" filter="" paginate=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    --paginate) paginate=1; shift ;;
    *) path="$1"; shift ;;
  esac
done
[ "$method" = GET ] || { echo "$path" >>"$STUB/writes"; exit 98; }
f="$STUB/api/$(printf '%s' "$path" | tr '/?=&' '____').json"
[ -f "$f" ] || exit 1
if [ -n "$filter" ]; then jq -r "$filter" "$f" || exit 1; else cat "$f"; fi
[ -z "$paginate" ] || [ ! -f "$f.page2" ] || cat "$f.page2"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/bin/codex"
chmod +x "$root/bin/gh" "$root/bin/codex"
export PATH="$root/bin:$PATH"

A="$STUB/api"
put() { printf '%s\n' "$2" >"$A/$(printf '%s' "$1" | tr '/?=&' '____').json"; }
# mut <api path> <jq filter>: edits one fixture in place.
mut() { local f; f="$A/$(printf '%s' "$1" | tr '/?=&' '____').json"; jq "$2" "$f" >"$f.new" && mv "$f.new" "$f"; }
codeowners() { put "repos/owner/repo/contents/.github/CODEOWNERS?ref=trunk" "$(jq -n --arg c "$(printf '%b' "$1" | base64)" '{content: $c}')"; }
R=repos/owner/repo
RULES="$R/rules/branches/trunk"
good() {
  rm -rf "$STUB" "$root/cwd"; mkdir -p "$A" "$root/cwd"
  put "$R" '{"owner":{"login":"owner","type":"User"},"default_branch":"trunk","permissions":{"admin":false,"push":true}}'
  put user '{"login":"agent"}'
  put "$RULES" '[{"type":"deletion","ruleset_id":1},{"type":"non_fast_forward","ruleset_id":1},
    {"type":"pull_request","ruleset_id":1,"parameters":{"allowed_merge_methods":["squash"],"dismiss_stale_reviews_on_push":true,"require_code_owner_review":true,"require_last_push_approval":true}},
    {"type":"required_status_checks","ruleset_id":1,"parameters":{"required_status_checks":[{"context":"test","integration_id":15368}]}}]'
  put "$R/rulesets/1" '{"current_user_can_bypass":"never"}'
  codeowners '# The owner approves everything.\n* @owner\n'
  put "$R/codeowners/errors?ref=trunk" '{"errors":[]}'
  put "$R/actions/secrets" '{"total_count":0,"secrets":[]}'
  put "$R/dependabot/secrets" '{"total_count":0,"secrets":[]}'
  put "$R/environments" '{"total_count":0,"environments":[]}'
}
run() { (cd "$root/cwd" && "$mentat" setup "$@" >"$STUB/out" 2>&1); echo $?; }
last() { tail -n 1 "$STUB/out"; }
export_ok() { [ -f "$root/cwd/mentat-ruleset.json" ]; }

good; rc=$(run owner/repo)
check "a ready repository is Setup OK (exit 0)" '[ "$rc" = 0 ] && [ "$(last)" = "Setup OK (7 not checked)" ] && ! grep -q "^PROBLEM\|^REFUSED" "$STUB/out"'
check "lists what it cannot check" '[ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ] && grep -q "NOT CHECKED: the one-time live block test" "$STUB/out"'
check "makes only GET calls to the API" '[ ! -f "$STUB/writes" ] && ! grep -vq -- "-X GET" "$STUB/calls"'
check "writes no ruleset when the rules are complete" '! export_ok'
git init -q "$root/cwd/clone"
for url in https://github.com/owner/repo.git git@github.com:owner/repo.git ssh://git@github.com/owner/repo; do
  good; git init -q "$root/cwd"; git -C "$root/cwd" remote add origin "$url"; rc=$(run)
  check "reads owner/repo from origin $url with GET calls only" '[ "$rc" = 0 ] && grep -q "^api -X GET repos/owner/repo --jq" "$STUB/calls" && [ ! -f "$STUB/writes" ]'
done
for url in https://notgithub.com/owner/repo.git https://example.test/github.com/owner/repo.git https://user@github.com/owner/repo.git; do
  good; git init -q "$root/cwd"; git -C "$root/cwd" remote add origin "$url"; rc=$(run)
  check "origin $url is not taken as GitHub" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not tell which GitHub repository" "$STUB/out" && ! grep -qs "repos/owner/repo" "$STUB/calls"'
done
good; git init -q "$root/cwd"; git -C "$root/cwd" remote add origin https://gitlab.example/owner/repo.git; rc=$(run)
check "a non-GitHub origin is a problem with the checklist" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not tell which GitHub repository" "$STUB/out" && [ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ]'

# Each missing or wrong rule is a problem and writes the ruleset export.
while IFS='|' read -r name filter; do
  good; mut "$RULES" "$filter"; rc=$(run owner/repo)
  check "$name is a problem" '[ "$rc" = 1 ] && [ "$(last)" = "Setup incomplete: 1 problem(s)" ] && export_ok'
done <<'CASES'
no deletion rule|map(select(.type != "deletion"))
no force-push rule|map(select(.type != "non_fast_forward"))
code owner review false|map(if .type == "pull_request" then .parameters.require_code_owner_review = false else . end)
stale dismissal null|map(if .type == "pull_request" then .parameters.dismiss_stale_reviews_on_push = null else . end)
no last-push approval|map(if .type == "pull_request" then del(.parameters.require_last_push_approval) else . end)
merge commits allowed|map(if .type == "pull_request" then .parameters.allowed_merge_methods = ["squash","merge"] else . end)
required check missing|map(select(.type != "required_status_checks"))
required check from another source|map(if .type == "required_status_checks" then .parameters.required_status_checks[0].integration_id = 1 else . end)
required check with another name|map(if .type == "required_status_checks" then .parameters.required_status_checks[0].context = "lint" else . end)
CASES
good; rc=$(run owner/repo --check lint)
check "--check names the required check" '[ "$rc" = 1 ] && grep -q "PROBLEM: missing on trunk: required check" "$STUB/out" && jq -e ".rules[3].parameters.required_status_checks == [{\"context\":\"lint\",\"integration_id\":15368}]" "$root/cwd/mentat-ruleset.json" >/dev/null'
check "the export is an active default-branch ruleset with no bypass" 'jq -e ".enforcement == \"active\" and .target == \"branch\" and .conditions.ref_name.include == [\"~DEFAULT_BRANCH\"] and .bypass_actors == [] and ([.rules[].type] == [\"deletion\",\"non_fast_forward\",\"pull_request\",\"required_status_checks\"]) and .rules[2].parameters.allowed_merge_methods == [\"squash\"] and .rules[2].parameters.require_code_owner_review and .rules[2].parameters.dismiss_stale_reviews_on_push and .rules[2].parameters.require_last_push_approval" "$root/cwd/mentat-ruleset.json" >/dev/null'
check "prints the import path" 'grep -q "Settings > Rules > Rulesets > New ruleset > Import a ruleset" "$STUB/out"'
good; mut "$RULES" 'map(select(.type != "deletion"))'; echo keep >"$root/cwd/mentat-ruleset.json"; rc=$(run owner/repo)
check "an existing export is not overwritten" '[ "$rc" = 1 ] && [ "$(cat "$root/cwd/mentat-ruleset.json")" = keep ] && grep -q "already exists here; not overwritten" "$STUB/out"'
good; mut "$RULES" 'map(select(.type != "deletion"))'; chmod a-w "$root/cwd"; rc=$(run owner/repo); chmod u+w "$root/cwd"
check "a failed export write is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not write mentat-ruleset.json" "$STUB/out" && [ "$(last)" = "Setup incomplete: 2 problem(s)" ]'

good; put "$R/rulesets/1" '{"current_user_can_bypass":"always"}'; rc=$(run owner/repo)
check "an agent that can bypass is refused" '[ "$rc" = 1 ] && [ "$(last)" = "Setup refused: the agent account can bypass ruleset 1 (always)" ]'
good; put "$R/rulesets/1" '{"current_user_can_bypass":"pull_requests_only"}'; rc=$(run owner/repo)
check "bypass through pull requests only is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: .*pull_requests_only"'
for v in '{}' '{"current_user_can_bypass":null}' '{"current_user_can_bypass":false}'; do
  good; put "$R/rulesets/1" "$v"; rc=$(run owner/repo)
  check "bypass field $v is a problem, not a pass" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read whether the agent account can bypass ruleset 1" "$STUB/out"'
done
good; put "$R/rulesets/2" '{"current_user_can_bypass":"always"}'; rc=$(run owner/repo)
check "a ruleset that does not apply to the default branch is ignored" '[ "$rc" = 0 ] && ! grep -q "rulesets/2" "$STUB/calls"'
good; put "$RULES" '[]'; rc=$(run owner/repo)
check "no rules at all is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: no ruleset applies to trunk" "$STUB/out" && export_ok'

good; put "$R" '{"owner":{"login":"owner","type":"Organization"},"default_branch":"trunk","permissions":{"admin":false,"push":true}}'; rc=$(run owner/repo)
check "an organization repository is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: owner/repo is owned by an organization"'
good; put user '{"login":"owner"}'; rc=$(run owner/repo)
check "the owner's own account is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: the agent account owner is the owner"'
good; mut "$R" '.permissions.admin = true'; rc=$(run owner/repo)
check "an agent with admin is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: the agent account has admin"'
good; mut "$R" 'del(.permissions)'; rc=$(run owner/repo)
check "unreadable permissions are a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read the agent account.s permissions" "$STUB/out"'
good; put "$R/actions/secrets" '{"total_count":2,"secrets":[{"name":"A"}]}'; rc=$(run owner/repo)
check "a repository Actions secret is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: owner/repo has 2 actions secret"'
good; put "$R/dependabot/secrets" '{"total_count":1}'; rc=$(run owner/repo)
check "a Dependabot secret is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: owner/repo has 1 dependabot secret"'
good; put "$R/environments" '{"environments":[{"name":"prod env","deployment_branch_policy":null}]}'; put "$R/environments/prod%20env/secrets" '{"total_count":1}'; rc=$(run owner/repo)
check "an environment secret is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: environment prod%20env has 1 secret"'
good; put "$R/environments" '{"environments":[{"name":"prod","deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}]}'; put "$R/environments/prod/secrets" '{"total_count":1}'; rc=$(run owner/repo)
check "an environment secret limited to protected branches is still refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: environment prod has 1 secret"'
good; put "$R/environments" '{"environments":[{"name":"preview"}]}'; put "$R/environments/preview/secrets" '{"total_count":0}'
printf '%s\n' '{"environments":[{"name":"prod"}]}' >"$A/repos_owner_repo_environments.json.page2"; put "$R/environments/prod/secrets" '{"total_count":3}'; rc=$(run owner/repo)
check "an environment secret on the second page is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: environment prod has 3 secret"'
good; put "$R/environments" '{"environments":[{"name":""}]}'; rc=$(run owner/repo)
check "an empty environment name is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read environments" "$STUB/out"'
good; printf 'null\n' >"$A/repos_owner_repo_rules_branches_trunk.json.page2"; rc=$(run owner/repo)
check "a rules page that is not a list is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read the rules on trunk" "$STUB/out"'
good; put "$R/environments" ''; rc=$(run owner/repo)
check "an empty environments response is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read environments" "$STUB/out"'
good; put "$R/environments" '{"environments":[{"name":"preview","deployment_branch_policy":null}]}'; put "$R/environments/preview/secrets" '{"total_count":0}'; rc=$(run owner/repo)
check "an environment without secrets is allowed" '[ "$rc" = 0 ]'
good; put "$R/environments" '{"environments":[{"name":"preview","deployment_branch_policy":null}]}'; rc=$(run owner/repo)
check "an unreadable environment secret list is a problem with no OK line" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read secrets of environment preview" "$STUB/out" && ! grep -q "OK: no environment secrets" "$STUB/out"'
good; mut "$R" '.default_branch = "rel#1"'
for f in "$A"/*trunk*; do mv "$f" "${f//trunk/rel%231}"; done; rc=$(run owner/repo)
check "a default branch with # is encoded, not cut short" '[ "$rc" = 0 ] && grep -q "rules/branches/rel%231" "$STUB/calls" && ! grep -q "rel#1" "$STUB/calls"'
good; mut "$R" '.permissions.admin = true'; mut "$RULES" 'map(select(.type != "deletion"))'; rc=$(run owner/repo)
check "a refusal wins over problems found alongside it" '[ "$rc" = 1 ] && last | grep -q "^Setup refused:" && grep -q "^PROBLEM:" "$STUB/out"'

while IFS='|' read -r name text; do
  good; codeowners "$text"; rc=$(run owner/repo)
  check "CODEOWNERS with $name is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: .github/CODEOWNERS must give every path to @owner alone" "$STUB/out"'
done <<'CASES'
a second owner|* @owner @someone\n
a later override|* @owner\n/docs/ @someone\n
an ownerless pattern|* @owner\n/.github/\n
no * rule|/src/ @owner\n
another owner only|* @someone\n
CASES
good; codeowners '* @owner\r\n/docs/ @owner\r\n'; rc=$(run owner/repo)
check "CODEOWNERS with CRLF line endings is accepted" '[ "$rc" = 0 ]'
good; codeowners '*   @Owner   # comment\n\n/docs/ @owner\n'; rc=$(run owner/repo)
check "CODEOWNERS spacing, case and comments are accepted" '[ "$rc" = 0 ]'
good; put "$R/codeowners/errors?ref=trunk" '{"errors":[{"line":1}]}'; rc=$(run owner/repo)
check "CODEOWNERS errors are a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: GitHub reports CODEOWNERS errors" "$STUB/out"'

# API failures and malformed answers are named problems, never passes.
while IFS='|' read -r name path; do
  good; rm -f "$A/$(printf '%s' "$path" | tr '/?=&' '____').json"; rc=$(run owner/repo)
  check "an unreadable $name is a problem" '[ "$rc" = 1 ] && grep -q "^PROBLEM:" "$STUB/out" && last | grep -q "^Setup incomplete:"'
done <<'CASES'
repository|repos/owner/repo
user|user
rule list|repos/owner/repo/rules/branches/trunk
ruleset|repos/owner/repo/rulesets/1
CODEOWNERS|repos/owner/repo/contents/.github/CODEOWNERS?ref=trunk
CODEOWNERS error list|repos/owner/repo/codeowners/errors?ref=trunk
Actions secret list|repos/owner/repo/actions/secrets
Dependabot secret list|repos/owner/repo/dependabot/secrets
environment list|repos/owner/repo/environments
CASES
while IFS='|' read -r name path body; do
  good; put "$path" "$body"; rc=$(run owner/repo)
  check "a malformed $name is a problem" '[ "$rc" = 1 ] && grep -q "^PROBLEM:" "$STUB/out" && last | grep -q "^Setup incomplete:"'
done <<'CASES'
user without a login|user|{"name":"x"}
CODEOWNERS error list|repos/owner/repo/codeowners/errors?ref=trunk|{"errors":null}
environment list|repos/owner/repo/environments|{"environments":null}
repository without a default branch|repos/owner/repo|{"owner":{"login":"owner","type":"User"},"permissions":{"admin":false,"push":true}}
CODEOWNERS without content|repos/owner/repo/contents/.github/CODEOWNERS?ref=trunk|{}
CASES
# Complete rules whose ruleset ids are bad: only the id is wrong.
for f in '.[0].ruleset_id = "1/../2"' '.[1] |= del(.ruleset_id)' '.[2].ruleset_id = null'; do
  good; mut "$RULES" "$f"; rc=$(run owner/repo)
  check "complete rules with a bad ruleset id ($f) are a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: a rule on trunk names no valid ruleset" "$STUB/out" && ! grep -q "rulesets/" "$STUB/calls"'
done
good; rm "$A/repos_owner_repo.json"; rc=$(run owner/repo)
check "an early failure still lists what was not checked" '[ "$rc" = 1 ] && [ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ]'
good; put "$RULES" '{"message":"oops"}'; rc=$(run owner/repo)
check "a rule list that is not a list is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read the rules on trunk" "$STUB/out"'
good; put "$R/actions/secrets" 'not json'; rc=$(run owner/repo)
check "malformed JSON is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read actions secrets" "$STUB/out"'
good; put "$R/actions/secrets" '{"total_count":"many"}'; rc=$(run owner/repo)
check "a non-numeric count is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read actions secrets" "$STUB/out"'

# PATHs holding only what each case needs, so a real codex or jq cannot leak in.
mkdir -p "$root/nocodex" "$root/nojq"
for t in bash jq tr base64 tail cat; do ln -s "$(command -v "$t")" "$root/nocodex/$t"; done
ln -s "$root/bin/gh" "$root/nocodex/gh"
good; rc=$(PATH="$root/nocodex" run owner/repo)
check "a missing codex is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: codex is not installed" "$STUB/out" && [ "$(last)" = "Setup incomplete: 1 problem(s)" ]'
ln -s "$root/bin/gh" "$root/nojq/gh"; ln -s "$(command -v bash)" "$root/nojq/bash"
mkdir -p "$root/nogh"; for t in bash jq tail; do ln -s "$(command -v "$t")" "$root/nogh/$t"; done
good; rc=$(PATH="$root/nogh" run owner/repo)
check "a missing gh is a problem with a final line and the checklist" '[ "$rc" = 1 ] && grep -q "PROBLEM: gh is not installed" "$STUB/out" && [ "$(last)" = "Setup incomplete: 1 problem(s)" ] && [ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ]'
good; rc=$(PATH="$root/nojq" run owner/repo)
check "a missing jq is a problem with a final line" '[ "$rc" = 1 ] && grep -q "PROBLEM: jq is not installed" "$STUB/out" && [ "$(last)" = "Setup incomplete: 1 problem(s)" ]'
rc=$(run owner/repo extra/repo); check "two repositories are a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run --check); check "--check without a name is a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run norepo); check "a bare name is a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run "owner/re#po"); check "a repository name with # is a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run a/b/c); check "a path with two slashes is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
