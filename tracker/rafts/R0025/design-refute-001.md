# Refute 001: R0025 design review 001

- F1: fixed: all four member `check.sh` files match case names with lines joined (`tr -d '\n\t' < "$spec" | grep -qF "it(\"$c"`). I extracted every one of the 38 `cases_pass` names and checked each against its spec: none miss. consequences: a name could now match across a line break inside one case's body, which is harmless.
- F2: fixed: c0067 adds `sweepPrompts()`, run in the main checkout after every pull there (`ready`, `stop`, `sync`, c0070's refresh). It removes each `tracker/rafts/active/<dir>` whose document is no longer tracked, and everything left in it. c0068 uses it instead of its own empty-directory removal, and c0070 runs it after its fast-forward. New ready.spec case "sync in the main checkout sweeps the prompt of a raft that left active/": a merged R0004 with a stale prompt.md and a `.DS_Store` is swept, the readied R0001 and R0006 prompts survive, and `list` and `board` work (AC12). `prompt` now decides from origin/main's tree only, and c0069's not-readied case plants a stale prompt.md, which also kills the "reads any file" mutant (F10). consequences: a main checkout that is never synced keeps the stale directory until its next sync (raft Risks).
- F3: fixed: the two c0045 prompt cases are named in c0069's Overrides (removed in execution). c0045's check.sh AC4 is removed in prep. Their pins moved to ready.spec "prompt.md embeds the workstreams plan, or the error when it can't be built", which uses a new raft R0006 with an internal dependency cycle. Test plan and Rules rows were added. consequences: R0006 is readied in the fixture, so later cases run with three active rafts, which strengthens F7.
- F4: fixed: the c0005 prompt case is narrowed **in prep** to "fails and changes nothing", which holds before and after R0025 (it passes now: 29/29). c0053's `replacements/c0005-worktree.spec.luau` was rewritten byte-identical in prep, and c0069's AC6 and the raft's RC6 `cmp` them. consequences: c0069's prompt.spec pins the new refusal wording ("raft id").
- F5: fixed: every done `check.sh` edit was made in this prep PR. That is `make-prompt` → `ready-raft` in c0005, c0045, c0046, c0047 and c0053; c0046's launch checks; and c0045's AC4. They are out of the Touched modules, and each Overrides line says "done in prep". Run now, the only failures are the missing ready-raft skill (c0005 AC5, c0045 AC6, c0046 AC6). The raft's RC5 and RC6 run them after implementation (F9). The promoted specs (c0047, c0046, c0045) are edited in execution, outside the `tracker/**` pattern.
- F6: fixed: c0067's move validation now has 8 rules:
  - neither side under `done/`;
  - a `from` that isn't an itemPath is refused;
  - `check.sh` must equal `paths.rewrite(old, this publish's moves)` (`paths.normalize` dropped);
  - unique `path`/`from`, and no other change inside a moved source directory or at a move target;
  - moved files are exempt from the `\r` rule.

  publish-move.spec gained these cases: "a move into or out of done/" (otherwise consistent), "a from outside an item directory… that file stays on origin", "a second change at a moved path" (source status edit, target overwrite, double move), an unmoved id's segment change in check.sh, and a CRLF file carried byte-exact. consequences: a future published "undo done" would need a design decision (noted under the rule).
- F7: fixed: the done case asserts that R0004's `spend.md` exists on R0004's branch and that R0001's and R0006's do not. The mutant "first or lowest active raft" was added to the row.
- F8: fixed: the exact tokens were added to c0067's Regression guard (c0050's start row, c0053's `only tracker.sh start`, c0048/c0057's board row, c0047's `3. ` step) and to c0070's (the board row). c0067's status design keeps `only tracker.sh start`.
- F9: fixed: the raft's Wording rule lists all 13 phrases, and c0067 AC10 scans all 13. RC5 runs the done `check.sh` of c0005, c0045, c0046 and c0047. RC6 checks c0053's replacement `cmp`s and ready-raft's merging sync: c0053's whole check reruns every acceptance spec, so this is the targeted part.
- F10: fixed:
  - ready off `main` (in the dirty case);
  - a member `prepared` but `design: reviewed` (R0007/c0110, in the no-check case);
  - stop with a member in `done/` (a new case, AC1);
  - `status` to `prepared`, `preparing` and `new` on readied items (AC5);
  - c0069's stale-prompt case (F2).
- F11: fixed:
  - stop names the PR on a GitHub origin (`gh pr list --head`); its Rules row is `reasoned`, since the fixtures have no GitHub;
  - the AGENTS.md Non-negotiable sentence gets the ready/stop/sync exception (c0067);
  - c0070's fallback builds the board in-process (`board.luau`), never touching `tests/run.luau`;
  - `start` on a pre-ready worktree says "run tracker.sh sync first" (c0067).
