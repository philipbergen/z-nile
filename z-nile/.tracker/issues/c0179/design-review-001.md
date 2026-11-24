# c0179 design review 001 (the lead's transcription)

Transcribed by the lead from the reviewer's findings, which were relayed in summary; it is not the reviewer's own text. The review
judged the ticket and its check file at c50cb1a72, with a narrow verification of the code round before it. **Verdict for the design:
build after these changes.** The reviewer's own mutants (looseObject dropped from `isPayload`; `--template=` removed) are red; a create
in the shared engine cache fails in the test that makes it; the watch-net failures of the gate are the machine's, not this branch's.

## Design and check file
- **F1** No criterion measures what the owner asked about, a full gate. Add AC5: the file events of one full gate, metered over the
  home's `.cache` and the run's `$TMPDIR`, recorded as the baseline the Lune-fixture work is judged against.
- **F2** (process) The ticket's sequestered `check.sh` was edited on a build branch; the design is a draft and the branch carries it, so
  `check.sh` is part of the design, with real lines for AC1 to AC4, judged by a design review before the merge.
- **F3** A wrong implementation can pass AC2: fewer events from fewer or skipped tests, or fixtures moved out of `$TMPDIR`. The check must
  warm the build, run `go test -json`, fail unless the passed tests are those of the merge base (list kept in the ticket folder) and no
  test is newly skipped, add roots for the home and `/private/tmp`, and record the line's own number.
- **F4** 60,000 was never derived: record it as a guess with the measured breakdown of the remainder. The question stays with the owner,
  with the advice: set AC2 at about 75,000 with the test-count guard, and spend the effort on the Lune fixtures.
- **F5** AC3 as written almost never measures (it needs a load under 4). Use a form that works on a busy machine: both test binaries
  (merge base and HEAD) interleaved A B A B A B, CPU-seconds, median HEAD/base at most 1.10.
- **F6** AC4 must wrap the AC2 run itself: `mount` and `hdiutil info` identical, no `zn-*template*` folder left in its `$TMPDIR`, no
  process still using it.
- **F7** The Verdict overreaches: say "these volume settings do not cut `fseventsd`'s cost; detaching a volume instead of removing its
  files, and where the folder sits, are untested", and run the two cheap experiments (remove versus detach; location).
- **F8** The Rules and mutants table and the Test plan are stale: rebuild them from what is built, marking each mutant `run` or `reasoned`.
- **F9, F10, F11** Bookkeeping: `depends_on: [c0178]` is no longer needed (the lead changes frontmatter, not the build); record G1 to G7
  and the 60,000 guess with `./zn guess`; fix G5's order and G7's "15-line"; fill Affected specs; add the section "Next slice: the Lune
  fixtures (c0178)": a packed read-only seed image per content key; one whole-tree clone per case into `.cache/<name>` after
  `fixture.check`; the rewrite of every file naming the image's absolute path, guarded by an "any file naming the build folder must be
  on the rewrite list" check; cleanup cost (no tree-by-tree removal during a run: a graveyard the launcher sweeps, or a per-run volume
  if detaching is free); the Linux fallback measured by file count; how the jail, the fence, the sentinel, the tripwire and cache-paths
  keep holding; and that c0178's "Interface for c0179" section assumes a volume and must be replaced.
- **F12** `check.sh` wrote outside `.cache` (`mktemp -d $TMPDIR/...`, a predictable name): use the home's `.cache` and remove it in the
  last check.
- Off macOS, AC1's macOS half, AC2, AC3 and AC4 passed without measuring anything: a criterion that cannot be measured on a host must not
  read as met.

## Code (narrow verification)
- **C1** `cmd/zn/main_test.go`: a failed `MkdirTemp` was discarded by the next assignment, and the next lines would create folders in the
  working folder (the real checkout). Check the error first; look for the same shape elsewhere.
- **C2** Killed test runs leave undeletable template folders (read-only cache folders; `zn-gittemplate-*`; stale host templates): both
  `TestMain`s sweep their own `zn-*template*` folders older than an hour, without following links, never a younger one.
- **C3** The shared engine cache's files stay writable (an append succeeds): make them refuse a write; reword the claim to "a write is
  refused, or detected by the next real-engine test that ends".
- **C4** The front-door template's host config still names `upstream` and `fork` remotes whose folders were removed: point them at an
  obviously missing path.
- **C5** The reviewed-list entry for the meter said "as the live daemon's binary is" and "never outside the checkout", neither true:
  refuse a `FSEVENTS_METER_CACHE` outside the checkout, and correct the entry.
