#!/usr/bin/env bash
# Exercise the published Git hook setup and update on a scratch installation.
set -euo pipefail

root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
doc="$root/docs/setup.md"
fail() { printf 'FAIL: setup %s\n' "$1"; exit 1; }
pass() { printf 'PASS: setup %s\n' "$1"; }

base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
tmp="$(cd "$base" && pwd -P)/with space"
plugin="$tmp/installed plugin"
export HOME="$tmp/home dir" TMPDIR="$tmp/temp"
dest="$HOME/.config/mentat/git-hooks"
old_hooks="$HOME/.config/other-tool/hooks"
mkdir -p "$plugin/bin" "$tmp/bin" "$HOME" "$TMPDIR" "$old_hooks"
cp -p "$root/bin/mentat" "$plugin/bin/"
cp -Rp "$root/git-hooks" "$plugin/"
export PATH="$plugin/bin:$tmp/bin:$PATH"

# Strip only Markdown list indentation and require one closed, matching fence.
extract_block() {
  awk -v lang="$1" -v pattern="$2" '
    /^## Git hooks$/ { section = 1; next }
    section && !fenced && /^## / { exit }
    !section { next }
    !fenced && $0 == "   ```" lang { fenced = 1; block = ""; next }
    fenced && $0 == "   ```" {
      if (block ~ pattern) { printf "%s", block; count++ }
      fenced = 0
      next
    }
    fenced { sub(/^   /, ""); block = block $0 "\n" }
    END { if (fenced || count != 1) exit 1 }
  ' "$doc"
}
extract_block bash 'cp -Rp' >"$tmp/copy" || fail "expected one fenced bash copy block"
extract_block bash 'rm -rf' >"$tmp/remove" || fail "expected one fenced bash removal block"
extract_block json '' >"$tmp/settings.json" || fail "expected one fenced JSON settings block"

# Mark only a scan of the staged addition, so a commit-message hook alone cannot pass.
export SETUP_SCAN_MARKER="$tmp/scanned"
cat >"$tmp/bin/gitleaks" <<'GITLEAKS'
#!/usr/bin/env bash
if grep -Fx '+mentat setup test' >/dev/null; then
  : >"$SETUP_SCAN_MARKER"
else
  [ "$?" -eq 1 ] || exit 2
fi
GITLEAKS
chmod +x "$tmp/bin/gitleaks"

# shellcheck source=/dev/null
. "$root/lib/git-hooks.sh"
bash "$tmp/copy" || fail "the documented copy command failed"
git_hooks_problems "$plugin" "$dest" || fail "lib/git-hooks.sh rejected the initial copy"
pass "documented copy works with spaces in the source and destination"

printf '# old version\n' >>"$dest/scan"
: >"$dest/hooks/stale-hook"
bash "$tmp/remove" || fail "the documented removal command failed"
[ ! -e "$dest" ] || fail "the documented removal left the old copy in place"
bash "$tmp/copy" || fail "the documented copy command failed on update"
git_hooks_problems "$plugin" "$dest" || fail "lib/git-hooks.sh rejected the updated copy"
[ ! -e "$dest/git-hooks" ] && [ ! -e "$dest/hooks/stale-hook" ] || fail "the update left stale or nested hooks"
pass "documented removal and re-copy install current hooks"

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/gitconfig"
unset XDG_CONFIG_HOME GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
unset MENTAT_GIT_HOOKS_DIR MENTAT_OWN_HOOK
printf '[user]\n\tname = Mentat setup test\n\temail = test@example.invalid\n' >"$GIT_CONFIG_GLOBAL"
cat >"$old_hooks/pre-commit" <<'OLD_HOOK'
#!/bin/sh
: >"$SETUP_OLD_HOOK_MARKER"
exit 1
OLD_HOOK
chmod +x "$old_hooks/pre-commit"
export SETUP_OLD_HOOK_MARKER="$tmp/old-hook-ran"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$old_hooks"
git init -q "$tmp/repo"
printf 'mentat setup test\n' >"$tmp/repo/staged.txt"
git -C "$tmp/repo" add staged.txt
if git -C "$tmp/repo" commit -qm "setup smoke test" || [ ! -f "$SETUP_OLD_HOOK_MARKER" ]; then
  fail "the existing index-0 hook did not reject the control commit"
fi
rm "$SETUP_OLD_HOOK_MARKER"

# Apply the example as written, substituting only the sample home directory.
settings=$(jq -er --arg home "$HOME" '
  .env | select(has("GIT_CONFIG_KEY_0") and has("GIT_CONFIG_VALUE_0")) |
  to_entries[] | select(.key | test("^GIT_CONFIG_(COUNT|(KEY|VALUE)_[0-9]+)$")) |
  .key + "=" + (.value | sub("^/Users/you/"; $home + "/"))
' "$tmp/settings.json") || fail "the documented settings block could not be read"
while IFS= read -r entry; do
  export "${entry%%=*}=${entry#*=}"
done <<<"$settings"
[ "$GIT_CONFIG_COUNT" = 2 ] &&
  [ "$GIT_CONFIG_KEY_0" = core.hooksPath ] &&
  [ "$GIT_CONFIG_VALUE_0" = "$old_hooks" ] || fail "the settings did not preserve index 0 and raise the count"
dir=$(git_hooks_dir) && [ "$dir" = "$dest" ] || fail "the settings did not select the copied hooks"
git_hooks_problems "$plugin" "$dir" || fail "lib/git-hooks.sh rejected the configured copy"
pass "documented settings preserve index 0 and select the current copy"

git -C "$tmp/repo" commit -qm "setup smoke test" || fail "git failed to commit with the documented settings"
[ -f "$SETUP_SCAN_MARKER" ] && [ ! -e "$SETUP_OLD_HOOK_MARKER" ] || fail "git did not scan the staged change with the copied hook"
pass "git runs the copied pre-commit hook"
