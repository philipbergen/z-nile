# Review 002: R0113 (code mode)
Inputs: `git diff origin/main...HEAD` at HEAD 5d3657ff907ad5c74985a3aa50b6f1475f01436c (one layer, R0113/1/c0322, now one commit replayed onto main) against origin/main ce2c39c9def149b5b49b282bd078971eeaabd126, which is also the merge base (after `./zn sync --fetch`); review-001.md and refute-001.md; c0322.md, its check.sh and acceptance/; R0113.md; harvest.md; z-nile/engine/ledger.luau, main.luau (`recordAndCommit`, `cmd.commit`, `modelOption`, `cmd.done`'s call), spend.luau; z-nile/tests/tooling/commit-rows-pairing.spec.luau and its `.watch.txt`; z-nile/tests/lib/trackerfix.luau and fixture.luau; z-nile/engine/sessionread.luau (`running`).

What was checked:
- F1's answer holds. In a throwaway clone of the worktree in my scratchpad (not under this worktree), run from its `z-nile/` with `./zn run --time 300 -- lune run tests/run -- tests/tooling/commit-rows-pairing.spec.luau`:
  - Unchanged HEAD: 3 passed, 0 failed, 3.8 s wall.
  - `kept,` → `shares,` in the `ledger.commitRows(` call (main.luau:4799): the third case fails, because `./zn commit` stops with `commitTrailers: 2 rows for 1 shares`. The fixture's idle member really does get a 0-line share, so the mutant is live in this fixture.
  - The same mutant with the guard switched off (`if false then`): the first case fails (the guard case), and the third case fails at line 91 (`added(B)` is not `{ 5 }`). The row assertion kills the mutant without the guard's help, and the trailer assertion alone would not have killed it, as round 1 predicted.
  - Round 1's other gap, the pairing loop: I ran `rows[i]` → `rows[1]` at main.luau:4810 against the new spec, c0322's bind-subject and wiring, c0118/model, d0333/commit-land, c0278/close-cli, c0084/commit-phase, c0084/spend-command, c0117/ledger and c0001/tracker-lifecycle. Result: 77 passed, 2 failed. The failures were `c0001/tracker-lifecycle` "commit records spend whose lines equal the diff, split by Touched modules" (a gate spec, not in slow.tsv) and `c0084/commit-phase` "splits tokens over the issues exactly". So the order and pairing of two kept shares is already pinned in the gate. The new spec only needs to pin the filter, and it does.
- The new spec is repository-safe:
  - `trackerfix.new("commit-rows-pairing", …)` builds its seed, bare origin and clones under `<cwd>/.cache/commit-rows-pairing`. That is `z-nile/.cache/…`, since the runner runs from `z-nile/`.
  - Every git and `./zn` call goes through `fixture.git` and `fixture.exec`, which check the folder and refuse an environment that points git elsewhere.
  - Identities are `commit-rows-pairing@example.invalid`, and `./zn commit`'s push goes to the fixture's own bare origin.
  - The fixture name is used by no other spec.
- The spec is deterministic:
  - `cmd.commit` passes no session reading (only `done` calls `sessionread.running`).
  - Its model comes only from `--model` (`modelOption`), so the exact trailer `Issue: c0020 +5/-0 0.0m` does not depend on the caller's environment.
  - It is fast (about 4 s), so it stays out of `slow.tsv` and remains a gate guard.
- The watch file selects the spec. `lune run z-nile/affected -- <path>` lists `tests/tooling/commit-rows-pairing.spec.luau` for `engine/ledger.luau`, `engine/main.luau`, `engine/spend.luau` and `tests/lib/trackerfix.luau`. It is `./zn finish`'s generated watch, and it is recorded green with its three cases in c0322's `results.txt`.
- The guard: `ledger.commitTrailers` raises on `#rows ~= #shares`, in the same style as ledger's other `error(...)` calls.
  - It runs after the extraRows loop but before `costrow.writeFiles` and `git commit`, so it writes no row and makes no commit.
  - Under `done` it is inside the `pcall` that rolls back.
  - `commitRows` and `commitTrailers` have one engine caller each.
  - The guard case pins both sides: a mismatched call raises, and a matched call of two returns two lines.
- F2's answer holds as far as it can now. The Verification log records three more 3/3 runs, and I ran `./zn check c0322` again: 3/3, 24 s. Round 1 also asked whether another suite was running in this checkout at the time of the first failure. The log does not say. That can no longer be established, and the runner refuses a second suite per checkout anyway, so I raise no finding. A recurrence would be caught with its output at `done`.
- Sequestration: the name-status diff lists only `A z-nile/.tracker/issues/active/c0322/acceptance/watch.txt`, which is finish's generated watch. No `check.sh` or acceptance spec changed.
- Gate and static checks:
  - `z-nile/check.sh --affected`: GATE PASSED (110.5 s).
  - `stylua --check` is clean on ledger.luau, main.luau and the new spec, and `selene` reports 0 errors and 0 warnings on ledger.luau and the new spec.
- The rest of the diff, read again for anything round 1 missed: the `rows` and `kept` pairing, `keptAny = #kept > 0` feeding the existing `could not write the measured row` check, and the `Session:` trailer that is added even when nothing was kept. All of it is as round 1 described, and I found nothing new.
- Lessons:
  - harvest.md files F1 under `zz-test/pin-call-site-arguments`, whose existing note from c0322's own design review (F3, F4: "pass the unguarded name that is in scope") is exactly this mutant. So pointing the harvest at that lesson with no new note is right.
  - F2 is filed as a one-off.
  - `./zn lessons --uncovered R0113` reports every finding covered, and `./zn lessons --check` passes.
- Bounded commands: every probe above ran through `./zn run --time`, and the diff starts no process.

## Judged criteria (code mode only)
The issue has no Judged criterion, and R0113's check.sh has only RC0 and RC1.

Verdict: approve
