# Changelog

## 2026-11-08

- `/mentat:plan` splits its ready items into build groups by shared files and gives one `/mentat:work-tickets` line per group, each extra line for its own session in its own worktree.
- The README recommends installing Mentat per repository, with user scope as an option, names the builder's Opus cost, and stays at most 500 words.
- Mentat works the same without personal instructions and says what your own instructions may change; `mentat check` no longer warns when you keep no private word list, and warns about kept head branches only when `~/.config/mentat/warn-kept-branches` exists.
- `/mentat:setup` is shorter and has a first run that covers install scope, GitHub sign-in and review tools; moving planning from GitHub issues to Linear is now `/mentat:linear`.
- When the maintainer corrects the same point twice, Claude Code restates the correction and follows it, and offers a grill only if one of their decisions is still open.
