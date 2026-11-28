# Setup

Extra setup for the optional Codex outside reviewer (`mentat-reviewers`) and the git hooks (`git-hooks/`).

## Codex outside the home folder

The Codex reviewer needs a Codex CLI whose `codex exec` accepts `--ignore-rules`, such as 0.172.0, the version CI tests. With a Codex whose `codex exec --help` does not list the flag, every Codex run fails, so upgrade it.

Install the Codex CLI into a prefix outside `$HOME`, such as Homebrew's:

```bash
npm install -g --prefix "$(brew --prefix)" @openai/codex
```

`node` needs an install prefix outside `$HOME` too, because Mentat's Codex profile cannot read it inside `$HOME`. Without Homebrew, replace `$(brew --prefix)` with any absolute prefix that is outside `$HOME` and does not contain it, such as `/usr/local`.

Check that the executables selected from `PATH` resolve to the intended Codex and Node installations:

```bash
codex_bin=$(command -v codex) && node_bin=$(command -v node) && realpath "$codex_bin" "$node_bin"
```

Sign in with `codex login`.

## Git hooks

The hooks in `git-hooks/` refuse likely secrets (in staged changes, outgoing commits and commit or tag messages) and non-local default-branch pushes (and the first branch pushed to a remote with none), then run the repository's own hooks except `reference-transaction` and `post-index-change`.

The hooks are nets for mistakes by agents' `git` only, not a security boundary, and your own `git` outside Claude Code is unchanged. For agents' `git`, your global `core.hooksPath` no longer runs; after Mentat's checks, only the repository's own hooks run (its local `core.hooksPath`, else `.git/hooks`).

1. Install `gitleaks` and `jq`:

   ```bash
   brew install gitleaks jq
   ```

2. Find the installed plugin's `git-hooks/` folder beside its `bin/` and copy it to a new absolute path outside any repository. Run this in the Claude Code session using the plugin's `mentat` on `PATH`; it prints the folder it copies from:

   ```bash
   dest="$HOME/.config/mentat/git-hooks"
   src=$(mentat_bin=$(command -v mentat) && CDPATH='' cd -P "${mentat_bin%/*}/.." && pwd -P)/git-hooks &&
     printf '%s\n' "$src" && mkdir -p "${dest%/*}" && cp -Rp "$src" "$dest"
   ```

3. Add the Git entries to the existing `"env"` block in Claude Code's user settings (`~/.claude/settings.json`) or its git-ignored local settings (`.claude/settings.local.json`). Keep the machine-specific path out of committed project settings (`.claude/settings.json`). Keep existing entries, set `GIT_CONFIG_KEY_<n>` to `core.hooksPath` and `GIT_CONFIG_VALUE_<n>` to the absolute `<copy>/hooks` path, and raise `GIT_CONFIG_COUNT` from `<n>` to `<n> + 1`. With no existing entries, use index `0` and a count of `"1"`. Mentat's entry must be the last `core.hooksPath` among the `GIT_CONFIG_*` entries (the highest index), which adding it at index `<n>` and raising the count gives. This example keeps an existing index-`0` entry and adds index `1`:

   ```json
   {
     "env": {
       "GIT_CONFIG_COUNT": "2",
       "GIT_CONFIG_KEY_0": "core.hooksPath",
       "GIT_CONFIG_VALUE_0": "/Users/you/.config/other-tool/hooks",
       "GIT_CONFIG_KEY_1": "core.hooksPath",
       "GIT_CONFIG_VALUE_1": "/Users/you/.config/mentat/git-hooks/hooks"
     }
   }
   ```

4. Start a new Claude Code session, where agents' `git` runs with these entries, and run in it:

   ```bash
   git config core.hooksPath
   mentat check
   ```

   `git config` prints the path git uses, which should be the copy's `hooks` path. `mentat check` reports the guards' state, including that the git hooks in `<copy>` are installed and current.

5. After updating the Mentat plugin, remove the old copy before repeating step 2. Use the same destination for both commands so `cp` does not nest a new `git-hooks/` inside the old copy:

   ```bash
   rm -rf "$HOME/.config/mentat/git-hooks"
   ```

   Then repeat the copy command from step 2 in a new Claude Code session started after the update, since a running session's `mentat` still points at the old version.
