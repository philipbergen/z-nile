# Review 001: c0069 (stream mode)
Inputs: `git diff R0025-ready-raft...ws-c0069`; c0069.md, its check.sh and acceptance/prompt.spec.luau; R0025.md and RC1, RC4, RC6; the tracker, testing and review skills.

Run in the stream worktree: `scripts/tracker.sh check c0069` is 6/6. RC1 (no `make-prompt` / `tracker.sh launch` hits), RC4 (usage lists ready, stop, `prompt <R-id> [--path]`, no "launch") and RC6 (both c0053 replacement copies equal the promoted c0005 and c0015 specs; ready-raft runs the merging sync) all pass by hand. None of the 12 banned phrases appears in .claude, tracker/templates, AGENTS.md, SETUP.md or main.luau (the grep matches only the raft doc's own list). The diff stays inside the Touched modules plus the authorized c0053 replacement renames and the ticket-prep wording change; ready-raft and execute-raft are listed as Touched but needed no edit (`/launch-raft` was already there, "Before launching" is about reviewers).

Checked and found sound:
- `cmd.prompt` decides only from `origin/main` (`fetch`, `originTree`, `git show origin/main:<doc>`, state `active` and effective status `active`). No origin fails with the not-readied text. A stale local `prompt.md` or local `active/` directory cannot change the answer.
- Output is `stdio.write(fs.readFile(path))` with no added newline; `--path` uses `print`. Nothing is written. Non-raft ids, extra positionals and a missing prompt fail with the Design's texts.
- `--stdout` is gone from `flags()` and USAGE. `READ_ONLY` is unchanged, so the repository guard still runs for `prompt`.
- `scripts/tracker.sh` is a single `exec`; no `launch` code is left in `scripts/`. `renderPrompt` stays, used by `ready`.
- The c0046 and c0045 spec edits remove only the listed cases (six `launch` cases plus their now-unused helpers; two `prompt ... --stdout` cases). The worktree-prune case stays.
- The launch-raft skill's four steps match the Design. The tracker skill, AGENTS.md and SETUP.md updates match the Design. No other doc describes the old launch flow: the remaining "launch" hits in .claude, AGENTS.md and scripts are about reviewers, `launchctl`, or the new skill.

### F1 [low] Two promoted specs still pass the dead `--stdout` flag
Where: tests/acceptance/c0005/worktree.spec.luau:220; tests/acceptance/c0053/commands.spec.luau:450
Evidence: `tr(main, { "prompt", "f0050", "--stdout" })` and `{ "prompt", "c0010", "--stdout" }`. With the new `flags()`, `--stdout` is a generic value flag: `prompt R0010 --stdout` is silently accepted and prints the prompt, and `prompt --stdout R0010` swallows the id.
Critique: Both cases still pass, because they expect a refusal, which now comes from the raft-id rule or the repository guard. They no longer exercise what they claim. The tempting fix is to edit both promoted specs. c0005's was narrowed in prep, and c0053's is outside c0069's Touched modules.
Consequences: Editing either spec adds it to the Overrides and Touched lists. Rejecting unknown flags would be a new CLI rule affecting every command.
Recommendation: Leave as is; optionally record it in the Verification log so a later chore can drop the flag from those two calls. No spec change in this stream.

Verdict: approve
