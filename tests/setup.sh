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
# Any call that is not an explicit GET is recorded in $STUB/writes and fails.
cat >"$root/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(printf '%s' "$*" | tr '\n' ' ')" >>"$STUB/calls"
[ "$1" = api ] || { echo "$*" >>"$STUB/writes"; exit 99; }
shift
method="" path="" filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    --paginate) shift ;;
    *) path="$1"; shift ;;
  esac
done
[ "$method" = GET ] || { echo "$path" >>"$STUB/writes"; exit 98; }
f="$STUB/api/$(printf '%s' "$path" | tr '/?=&' '____').json"
[ -f "$f" ] || exit 1
if [ -n "$filter" ]; then jq -r "$filter" "$f" || exit 1; else cat "$f"; fi
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
    {"type":"pull_request","ruleset_id":1,"parameters":{"allowed_merge_methods":["squash"],"dismiss_stale_reviews_on_push":true,"require_code_owner_review":true,"require_last_push_approval":true,"required_approving_review_count":1}},
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
points() { grep -q "imports ruleset.json from the Mentat repository" "$STUB/out"; }

good; rc=$(run owner/repo)
check "a ready repository is Setup OK (exit 0)" '[ "$rc" = 0 ] && [ "$(last)" = "Setup OK (7 not checked)" ] && ! grep -q "^PROBLEM\|^REFUSED" "$STUB/out"'
check "lists what it cannot check" '[ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ] && grep -q "NOT CHECKED: the one-time live block test" "$STUB/out"'
check "makes only GET calls to the API" '[ ! -f "$STUB/writes" ] && ! grep -vq -- "-X GET" "$STUB/calls"'
check "does not point to ruleset.json when the rules are complete" '! points && [ -z "$(ls -A "$root/cwd")" ]'

# Each missing or wrong rule is a problem and points to ruleset.json.
while IFS='|' read -r name filter; do
  good; mut "$RULES" "$filter"; rc=$(run owner/repo)
  check "$name is a problem" '[ "$rc" = 1 ] && [ "$(last)" = "Setup incomplete: 1 problem(s)" ] && points'
done <<'CASES'
no deletion rule|map(select(.type != "deletion"))
no force-push rule|map(select(.type != "non_fast_forward"))
no approval required|map(if .type == "pull_request" then .parameters.required_approving_review_count = 0 else . end)
code owner review false|map(if .type == "pull_request" then .parameters.require_code_owner_review = false else . end)
stale dismissal null|map(if .type == "pull_request" then .parameters.dismiss_stale_reviews_on_push = null else . end)
no last-push approval|map(if .type == "pull_request" then del(.parameters.require_last_push_approval) else . end)
merge commits allowed|map(if .type == "pull_request" then .parameters.allowed_merge_methods = ["squash","merge"] else . end)
required check missing|map(select(.type != "required_status_checks"))
required check from another source|map(if .type == "required_status_checks" then .parameters.required_status_checks[0].integration_id = 1 else . end)
required check with another name|map(if .type == "required_status_checks" then .parameters.required_status_checks[0].context = "lint" else . end)
CASES
good; rc=$(run owner/repo --check lint)
check "--check names the required check, and says ruleset.json uses test" '[ "$rc" = 1 ] && grep -q "PROBLEM: missing on trunk: required check" "$STUB/out" && grep -q "change it to lint" "$STUB/out"'
check "writes nothing locally" '[ -z "$(ls -A "$root/cwd")" ]'
# ruleset.json, imported as is, satisfies every rule setup checks.
good; jq '[.rules[] | . + {ruleset_id: 1}]' "$(dirname "$mentat")/../ruleset.json" >"$A/repos_owner_repo_rules_branches_trunk.json"; rc=$(run owner/repo)
check "ruleset.json passes every rule check" '[ "$rc" = 0 ] && ! grep -q "^PROBLEM" "$STUB/out"'
check "ruleset.json is an active default-branch ruleset with no bypass that requires one approval" 'jq -e ".enforcement == \"active\" and .target == \"branch\" and .conditions.ref_name.include == [\"~DEFAULT_BRANCH\"] and .bypass_actors == [] and (.rules[] | select(.type == \"pull_request\") | .parameters.required_approving_review_count) == 1" "$(dirname "$mentat")/../ruleset.json" >/dev/null'

good; put "$R/rulesets/1" '{"current_user_can_bypass":"always"}'; rc=$(run owner/repo)
check "an agent that can bypass is refused" '[ "$rc" = 1 ] && [ "$(last)" = "Setup refused: the agent account can bypass ruleset 1 (always)" ]'
good; put "$R/rulesets/1" '{"current_user_can_bypass":"pull_requests_only"}'; rc=$(run owner/repo)
check "bypass through pull requests only is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: .*pull_requests_only"'
good; put "$R/rulesets/1" '{}'; rc=$(run owner/repo)
check "a missing bypass field is a problem, not a pass" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read whether the agent account can bypass ruleset 1" "$STUB/out"'
good; put "$R/rulesets/2" '{"current_user_can_bypass":"always"}'; rc=$(run owner/repo)
check "a ruleset that does not apply to the default branch is ignored" '[ "$rc" = 0 ] && ! grep -q "rulesets/2" "$STUB/calls"'
good; put "$RULES" '[]'; rc=$(run owner/repo)
check "no rules at all is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: no ruleset applies to trunk" "$STUB/out" && points'

good; put "$R" '{"owner":{"login":"owner","type":"Organization"},"default_branch":"trunk","permissions":{"admin":false,"push":true}}'; rc=$(run owner/repo)
check "an organization repository is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: owner/repo is owned by an organization"'
good; put user '{"login":"owner"}'; rc=$(run owner/repo)
check "the owner's own account is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: the agent account owner is the owner"'
good; mut "$R" '.permissions.admin = true'; rc=$(run owner/repo)
check "an agent with admin is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: the agent account has admin"'
good; put "$R/actions/secrets" '{"total_count":2,"secrets":[{"name":"A"}]}'; rc=$(run owner/repo)
check "a repository Actions secret is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: owner/repo has 2 actions secret"'
good; put "$R/dependabot/secrets" '{"total_count":1}'; rc=$(run owner/repo)
check "a Dependabot secret is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: owner/repo has 1 dependabot secret"'
good; put "$R/environments" '{"environments":[{"name":"prod env","deployment_branch_policy":null}]}'; put "$R/environments/prod%20env/secrets" '{"total_count":1}'; rc=$(run owner/repo)
check "an environment secret is refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: environment prod%20env has 1 secret"'
good; put "$R/environments" '{"environments":[{"name":"prod","deployment_branch_policy":{"protected_branches":true,"custom_branch_policies":false}}]}'; put "$R/environments/prod/secrets" '{"total_count":1}'; rc=$(run owner/repo)
check "an environment secret limited to protected branches is still refused" '[ "$rc" = 1 ] && last | grep -q "^Setup refused: environment prod has 1 secret"'
good; put "$R/environments" '{"environments":[{"name":"preview","deployment_branch_policy":null}]}'; put "$R/environments/preview/secrets" '{"total_count":0}'; rc=$(run owner/repo)
check "an environment without secrets is allowed" '[ "$rc" = 0 ]'
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
good; codeowners '*   @Owner   # comment\n\n/docs/ @owner\n'; rc=$(run owner/repo)
check "CODEOWNERS spacing, case and comments are accepted" '[ "$rc" = 0 ]'
good; put "$R/codeowners/errors?ref=trunk" '{"errors":[{"line":1}]}'; rc=$(run owner/repo)
check "CODEOWNERS errors are a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: GitHub reports CODEOWNERS errors" "$STUB/out"'

# API failures and malformed answers are named problems, never passes. One
# representative each; every call shares the same handling.
good; rm "$A/repos_owner_repo.json"; rc=$(run owner/repo)
check "an unreadable repository is a problem that still lists what was not checked" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read repos/owner/repo" "$STUB/out" && [ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ]'
good; rm "$A/repos_owner_repo_rules_branches_trunk.json"; rc=$(run owner/repo)
check "an unreadable rule list is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read the rules on trunk" "$STUB/out"'
good; put "$R/actions/secrets" 'not json'; rc=$(run owner/repo)
check "malformed JSON is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: could not read actions secrets" "$STUB/out"'
good; mut "$RULES" '.[1] |= del(.ruleset_id)'; rc=$(run owner/repo)
check "a rule without a ruleset id is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: a rule on trunk names no valid ruleset" "$STUB/out"'

# PATHs holding only what each case needs, so a real codex or gh cannot leak in.
mkdir -p "$root/nocodex"
for t in bash jq tr base64 tail cat; do ln -s "$(command -v "$t")" "$root/nocodex/$t"; done
ln -s "$root/bin/gh" "$root/nocodex/gh"
good; rc=$(PATH="$root/nocodex" run owner/repo)
check "a missing codex is a problem" '[ "$rc" = 1 ] && grep -q "PROBLEM: codex is not installed" "$STUB/out" && [ "$(last)" = "Setup incomplete: 1 problem(s)" ]'
mkdir -p "$root/nogh"; for t in bash jq tail; do ln -s "$(command -v "$t")" "$root/nogh/$t"; done
good; rc=$(PATH="$root/nogh" run owner/repo)
check "a missing gh is a problem with a final line and the checklist" '[ "$rc" = 1 ] && grep -q "PROBLEM: gh is not installed" "$STUB/out" && [ "$(last)" = "Setup incomplete: 1 problem(s)" ] && [ "$(grep -c "^NOT CHECKED:" "$STUB/out")" = 7 ]'
rc=$(run owner/repo extra/repo); check "two repositories are a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run --check); check "--check without a name is a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run norepo); check "a bare name is a usage error (exit 64)" '[ "$rc" = 64 ]'
rc=$(run); check "no repository is a usage error (exit 64)" '[ "$rc" = 64 ]'

[ "$failures" -eq 0 ]
