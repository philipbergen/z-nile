# c0343's prep work, handed to d0333

c0343 duplicates d0333 (Commit after finish unfinishes the layer). The user's decision, 2026-11-14: "Hand my work to
d0333". Nothing here is reviewed. Take what helps; the ids and fixture names say c0343 and need renaming.

## What was found
- Two separate lists say which files a commit may touch after a layer's finish commit, and both leave out the
  raft's `spend.md`, which `./zn commit` rewrites in every commit (`spend.writeRaft`, z-nile/engine/spend.luau):
  - `layergit.isPostFinishPath` (z-nile/engine/layergit.luau:118): read by `./zn work next` and `./zn finish` to
    call a layer finished. Without the ledger, `work next` asks for another finish after any `./zn commit`.
  - `isTrackerFileOf` and `isAllowedAfterTrace` (z-nile/engine/trace.luau:437, 463): read by `./zn trace --check`
    and `./zn done`. Without the ledger, the table is "stale".
- `tests/tooling/trace-land.spec.luau` commits the table and the final review with plain `git commit`
  (lines 353-354 and 368-369), which is why no spec met the ledger.
- R0101 (pickman) is held on this at d4a3b81e8: its top layer is the finish commit 37c3be1be plus one
  `./zn commit` of trace.md, the ledger and a spend.d row. With the fix that state passes as it is.

## The prototype (experiments/prototype.patch, or prototype.py <clone>)
Three added lines: `or name == "spend.md"` in each of the three lists. On a clone under `$TMPDIR` of origin/main
bc35f7c41 with the patch:
- `acceptance/commit-land.spec.luau` (30 s; set-up copied from trace-land.spec): finish, the table and the final
  review by the real `./zn commit`, `trace --check` ok, `work next` says final review and then done (never finish),
  a late source commit is stale and unfinishes the layer, then R0101's own path (a harvest commit, finish again, the
  table names the old commit, re-point it with `./zn commit`, check ok, done lands). 1 passed. On unpatched main it
  fails at its first `trace --check` with R0101's message ("touches non-tracker file …/spend.md after finish").
- `acceptance/postfinish.spec.luau` (fast, pure): 4 passed with the patch; 3 of 4 fail on main, on assertions.
- `experiments/mutants.py`: M1 to M7 and M9 turn postfinish.spec red (M1 to M3 also commit-land, at lines 376, 373
  and 392). M8 (harvest.md added to `isAllowedAfterTrace` only) is green and is equivalent: every commit after the
  table is checked against `isTrackerFileOf` first, so the after-the-table list can only narrow.
- The whole fast tier with both specs copied to `tests/acceptance/c0343/` and a `slow.tsv` row for commit-land:
  917 passed, 5 failed. Three are the copies having no watch file (`c0114/layout`, `c0185/selector` twice), which
  `./zn finish` writes. One is `tooling/slow-tier.spec`, which pins 99 rows and that each row's file exists. One is
  `c0120/check-paths` ("every unfinished item's check.sh names only paths that exist"), not looked into.
  `tests/tooling/trace-land.spec.luau` still passes.

## Open points for d0333's design
- **The slow tier.** A 30 s end-to-end spec cannot stay in the fast tier, and `tooling/slow-tier.spec` requires
  every `slow.tsv` row's file to exist, so a row for a sequestered spec is red on the layer until `done` promotes
  it. Changing `tests/tooling/trace-land.spec.luau` to commit with `./zn commit` (it is already in the slow tier and
  is not a promoted spec) avoids both, but is then not sequestered.
- `./zn commit` after the final review may also carry `harvest.md` and lesson files (a final review with
  findings). Those are not in the set, by d0333's Non-goal; the path that works is finish again, re-point the
  table's `Commit:` line, commit. commit-land.spec covers that path.
- `workread` sets `traceOk = trace and final == "approved"` without running the check, so `work next` can say
  "done" while `done` will refuse a stale table.
