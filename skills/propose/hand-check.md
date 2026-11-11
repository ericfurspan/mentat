# Side-by-side hand check

For a change to what a report or reply shows, the hand check runs the same flow twice, once on the default branch's plugin and once on the branch's, and shows the two outputs side by side.

- The old side loads a detached worktree of the default branch (`git worktree add --detach <temp folder> origin/<default>`), the new side the branch's checkout. Both runs get the same prompt from the same folder, each as `claude -p --no-session-persistence --plugin-dir <folder> "<prompt>"`.
- The prompt makes each run first print the revision of the folder its Mentat skills load from (a skill's base directory), from `git -C <that folder> rev-parse --short HEAD`.
- The prompt tells each run to write nothing: file, record and post nothing, and run no reader's writes. Instead of asking a question, it prints each question it would ask, then the report or reply the change alters.
- Where the flow reads records (an issue tracker, pull requests, a project's comments), Claude Code reads them once. The prompt carries them and any session context the report reads, such as messages a report built from the session would show, and tells each run to use those inputs and read no live source again.
- Each side's label quotes its run's revision statement. The old side's must be the default branch's revision and the new side's the branch's; a run whose statement is missing or names another revision is not used for that side.
- Nothing is kept between runs. Once both outputs are shown, remove the temporary worktree (`git worktree remove <temp folder>`).
