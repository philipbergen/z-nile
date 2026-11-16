# Review 010: c0165 (design mode)
Inputs: worktree at 86b77d4c plus the uncommitted re-prep (c0165.md blob 6a34e076, check.sh d6fbfc90, acceptance/audited.tsv 96b88afd, digest.spec.luau b8572792, the other specs, gatefix.luau, proof-interim.luau, rehash.py, declared-{pickman,z-nile}.tsv); design-review-009 and design-refute-009; capture 5fa62e59 (`./zn capture c0165`); c0184's `experiments/{tooling.patch,rehash.py,scaffold-homes.sh}`; c0185's sequestered `selector.spec`; c0242 on `origin/main` (a8b76473, which adds only tracker files since the base); `z-nile/tests/tooling/repo-fence.spec.luau`, `z-nile/tests/acceptance/c0172/narrowed.spec.luau`, `z-nile/engine/main.luau` (done's promotion); `./zn lessons --skill zz-review --full`, `./zn lessons --when design`. Runs: `./zn promote-check c0165`; `./zn run --time 900 -- ./zn check c0165`; probes below, each through `./zn run` (scripts in the scratchpad). I did not run the gate.
Round 4 of the re-prep after the user's split (2026-11-03). Dropped from design-review-009: F1, F2, F3, F4, F5 (each fix holds against the artifacts, below).

**Fixes checked against the artifacts (not the refute).**
- 009 F1 holds. `c0172/narrowed` is in the Overrides line, the Checklist, the Modules table, Touched modules and AC11's `OVERRIDES` regex. AC12's second half compares main's file with the gate-cover digest swapped back, requires the digest to differ from main's, and runs `c0172/narrowed` itself. I reproduced the procedure on a scratch copy (`git archive HEAD`, `git apply --include='z-nile/tests/*'` of c0184's `tooling.patch`, stylua, c0184's `rehash.py`, then `--graph-only` in the two helpers, stylua, c0165's `rehash.py`). It printed `c0114 gate-cover.spec.luau b95f71b3 -> 0eddefed`. The resulting blobs are narrowed `f78fc83f`, graph-homes `45d959e7` and gate-cover `a49b482f`, and each equals its pre-keyed line in `audited.tsv`. The c0184-only blobs (`5fbbb6ea`, `9b8c9780`) match too. Diffed against today's file, the result differs in only two hex lines: 67 (c0165's row) and 80 (c0184's `c0120/docs` row). So AC12, which compares against main at merge time, sees only c0165's row. E10's digest search, rerun: `grep -rlE '[0-9a-f]{64}' z-nile/tests pickman/tests` gives 8 files, and of those only `c0172/narrowed` pins an overridden file (line 66). c0185's sequestered specs hold no digest. c0184's `check.sh` and patch hold its own rehash only.
- 009 F2 holds. `declared-pickman.tsv` has `tests/meta/fence.spec.luau\t*`. I recomputed the path-complete sets from the tree: 462 spec files, 216 E9 hits, 132 declared specs and 240 others. `comm` against `audited.tsv`'s `nohit` paths leaves nothing on either side, except c0165's own four (gate-refs, gate-results, plan, select), which are not on the tree before `done`. AC14's new loop fails on any spec file with no line. It accepts `nohit` only with blob `-`, and a `nohit` line never satisfies a hit or a declared spec (`listed` goes through the blob-keyed branch first). AC14 passes on today's tree in the check run. Step 7 lists the 16 wrappers, with what each reads, against `scaffold-homes.sh` lines 59–75 and 150–155.
- 009 F3 holds for c0165's own files. The four names are in the Modules row and the Regression guard. AC16 reads repo-fence's `NAMES` (30, the same count as the table's quoted lines) and requires a literal `["<key>"] = {` entry per file. In the check run it names exactly digest's three names and plan's `sandbox-exec`, and my own case-insensitive grep finds the same four. Repo-fence scans only `.luau`, `.sh` and extensionless files (`files()`, lines 309–331), so the promoted `.tsv` and `.py` files are not scanned. `digest.spec` lines 179–191 wrap both `dbPath` calls in `pcall`, restore the variable and re-raise. F3 below finds a fifth file, one that c0165 writes.
- 009 F4 holds. Scalability, E6 and the Design state the comparison against today. I reran the probe: `lune run z-nile/affected -- --project z-nile pickman/src/shared/Logic/Awareness/init.luau` printed nothing (rc 0). `spec-durations.tsv` now reads `c0120/finished` 131.67 s and `c0116/retired` 72.78 s, inside the stated ranges. c0242 is on `origin/main` and named.
- 009 F5 holds. The `declared/` path wording is right, step 7 has the re-key list, and `docs.spec` has the per-project case: it fails in the check run for want of `inputs.tsv`, as it should.

**Structural question: does anything keep the audit true after `done`?** No. A `check.sh` runs at `./zn check` and at `done` (`runCheck(raft)` before the promotion, main.luau ~4067), and never again. Nothing in the engine or the gate reruns a done item's `check.sh`: `c0120/finished` checks those files' paths and does not run them. zz-review/recommendations-pick-spec-or-check says the same ("a check.sh AC runs at the item's own check and `done`, then never again"). After `done`, three things remain:
- the zz-test Declared-inputs sentence (AC10 pins its wording);
- `docs.spec`'s rule for the two per-project specs;
- the merge's `--full`, which reads no row.

The first spec that lands afterwards with an undeclared read is reused in every affected run until its read changes the outcome at the merge. See F1.

**The pickman fence wrapper's `*` (question 4).** The Design states the consequences and accepts them (Registry-driven specs bullet):
- every affected pickman run selects the wrapper;
- a pickman whole-gate digest holds HEAD, so a pickman whole-gate pass is reused only at the same HEAD;
- per-spec reuse of pickman's other specs is unaffected;
- the rejected alternative is named.

I timed `lune run tests/run -- tests/meta/fence.spec.luau` from `pickman/`: 1.92 s wall, runner start included, 10 cases. z-nile's copy records 1.65 s. So "about a second" is a slight understatement, but the spec is under the rule's 2 s threshold, and `*` is always allowed by the rule. It contradicts no recorded decision. The capture's "a gate that already passed on the exact same code" is met at the same HEAD. The code reviewer runs `--full`, which reuses nothing in c0165 anyway. "Declare the two slow ones" concerns only `c0120/finished` and `c0116/retired`.

**Scope (item 11).** `diff` of the capture's Problem and Solution against today's text shows only the decision lines and the Non-goal's prep note. The kept outcomes each have a Design and Checked criteria:
- Fingerprint: AC1, AC2.
- Reuse: AC3, AC5, AC7.
- Store: AC4; AC5's second worktree; the db path in digest.spec (AC7); `.gitignore` (AC10).
- No forged pass, forced rerun: AC5, AC7, AC13, AC14, `--fresh`, `--full`.
- Solution's "need declared inputs or must always run": AC13, AC14.

Nothing moved to c0238–c0240 is silently relied on. The two interim facts live only in `proof-interim.luau` (AC15, inert after `done`), and the promoted pair case releases the held spec after 3 s, so c0238's wait passes it. The residue decision's backstop, "the merge's full gate always runs fresh", holds in c0165: `--full` reads no row (AC7, gate-full).

**promote-check.** Exit 1. Every error is an unknown require of `fingerprint`, `select`, `resultsdb`, `workspace` or `reuseplan`, an unknown type they export, or the two `GitState` table errors at select.spec 437 and 439. The meta failure lists only those six requires. Acceptable.

### F1 [medium] The audit lapses at `done`: no standing check keeps declarations true for specs that land later, and the Design does not say so
Where: Design `select.luau` (AC14 and the Limit), Checklist "Migration of existing work", check.sh AC14, the zz-test Declared-inputs wording.
Evidence:
- AC14 is the only mechanical check that a spec reading outside its requires is declared. It is a `check.sh` AC, so it runs at `./zn check c0165` and at `done`, then never again. `withPromotedCopies` and done (main.luau 3906–3933, 4067–4083) run the item's own `check.sh` once, and no gate spec runs done items' `check.sh` files.
- After `done`, AC10 pins only the zz-test *wording*, plus the per-project lines of two specs.
- How often this happens: E9's own result says 14 specs with undeclared reads landed in the six days between the first audit and this one (c0153/golden, c0155, c0159, c0164, c0170, d0124, f0109, f0125, c0183 ×3, c0191 ×3), out of 57 new spec files.
- Once reuse exists, such a spec is reused in every affected run until one of its graph inputs changes. Today it would at least rerun whenever the branch's diff touches its closure.

So the captured "no ... different tree or spec can forge a pass" holds on the day of `done` and then wears away silently. It is medium, not high, because the merge's `--full` (which reads no row) still runs every spec, the backstop the user chose on 2026-10-26 ("the full gate at merge runs all for real so we can find out if dependency graph has gaps"). A forged pass therefore never reaches `main`. But every pre-merge gate between such a spec's landing and its first failure at a merge is wrong.
Critique: The tempting fix is to promote AC14 as it is. That pins today's set (`audited.tsv` is sequestered and blob-keyed), and every later spec or edit would redden an unrelated raft's gate with no file it may edit: zz-test/promoted-specs-pin-rules-not-sets. The other temptation is to rely on the zz-test sentence and review. Three rounds of this review missed wrappers, helper reads and registry loops, so review alone is the weakest control on the list.
Consequences: A standing check needs data the later author may edit (committed, unsequestered) and a rule that does not churn:
- A path-keyed rule never sees an existing spec that gains a read: the named Limit, unchanged.
- A blob-keyed rule would make every edit to roughly 230 specs a data edit.
- A rule over every spec file would add a line to every new pickman unit spec. A rule over E9 hits plus wrappers asks for a line from about half of new specs, the ones that read files, which is exactly the decision the Declared-inputs rule already asks their author to make.
- The check reads every registered home's specs, so it is registry-driven and declares `*`. It costs well under a second.
- c0238–c0240's own new specs then need their lines, which their preps must know.
Recommendation: a promoted spec, not a check.sh AC (the rule must outlive `done`):
- Add `acceptance/audit.spec.luau` with one case: for every registered home, every spec file in its `tests/` that matches E9's pattern, or that `require`s a `*.spec` module (a wrapper), has either a line in its home's `tests/inputs.tsv` or a line in a new committed `<home>/tests/audited.tsv` (`<spec>\t<covered|fixture|literal>\t<why>`, path-keyed, editable by any later change).
- Seed the `audited.tsv` files from the 99 excluded lines (path, class and why, without the blob). AC13's pattern can pin that the seed shipped.
- Add one clause to the zz-test Declared-inputs line: "a spec the search names that reads nothing outside its requires has a line in its home's `tests/audited.tsv`". AC10 pins it.
- Declare `audit.spec` `*` in `declared-z-nile.tsv` and key it in `audited.tsv`.
- Rules and mutants rows: a new E9-hit spec with no line fails; a new wrapper with no line fails; a line in another home's file does not count.
- Say in the Design what still stays unseen: a spec that later gains a read without matching the search.
- AC14 stays as the blob-keyed one-time migration check.

If the author judges a new promoted spec too much, the only other option is to escalate to the user. Options: (a) the spec above; (b) accept that after `done` declarations are kept only by the zz-test rule and review, with the merge's `--full` (and later c0240's learning) as the backstop, recorded as a `Decided with the user` line and stated in the Design. (b) costs pre-merge gates that pass on stale reuse until a merge fails.
Lesson: zz-review/recommendations-pick-spec-or-check, zz-test/promoted-specs-pin-rules-not-sets, z-design/declare-what-full-runs-covered

### F2 [low] The 16 wrappers' declarations are stated in the Design but checked nowhere, while pickman's identical fence wrapper is pinned `*` in the sequestered list
Where: Design, c0184 paragraph ("The 16 wrappers"); step 7; AC13 and AC14.
Evidence:
- Pickman's `tests/meta/fence.spec` is `*` in the sequestered `declared-pickman.tsv`, so AC13 requires it.
- The five identical `<home>/tests/meta/fence.spec.luau` wrappers, and the six `home` and five `architecture` wrappers, get their lines only from step 7, in the executor-written `declared/added-*.tsv`.
- AC14 is satisfied by a `nohit` line for any of them, and AC13 by no line at all. So a step 7 that classes snake's architecture wrapper `nohit` passes `check.sh`, and only the code reviewer's reading of `added-*.tsv` stands between it and `main`.
- Their text is known now: `scaffold-homes.sh` writes them with `$h` substituted, so paths and blobs are computable.
- The same holds for c0184's four and c0185's six sequestered specs. All but `c0185/crosshome` are E9 hits (`grep -cE` on each: 2, 5, 4, 1, 2; 2, 3, 5, 2; crosshome 0), and promotion keeps their blobs.
- Impact is small: the fence wrappers' scan duplicates the `*` copies in z-nile and pickman, so the gap shows only in a `--project <new home>` gate.
Recommendation: put the 16 wrappers' lines in the sequestered `declared-<home>.tsv` files (AC13 already reads any home's list, and `[[ -f ]]` skips a spec that does not exist yet). Pre-key their blobs, and those of the ten sequestered c0184 and c0185 specs, in `audited.tsv`. A c0184 result that differs then shows as "edited since its audit" and step 7 re-keys it, the same path the twelve rewritten specs already take. Consequence: if c0184 renames a wrapper, AC13 asks for a line for a spec that does not exist. Step 7 should say to escalate that for a re-prep rather than edit the list.

### F3 [medium] `workspace.luau` must name `PICKMAN_TEST_FENCE`, and the design lists no `ALLOWED` entry for it and says "no other banned name" (repeat of design-review-009 F3's mechanism)
Where: Design `workspace.luau` ("`dbPath(root)` ... With `PICKMAN_TEST_FENCE` set it also refuses a result without a `/.cache/` segment"); Modules row for `repo-fence.spec` (entries for `specs.luau`, `reuseplan.luau`, `c0165/digest.spec`, `c0165/plan.spec`); Regression guard ("... and no other banned name"); `acceptance/digest.spec.luau` lines 179–191.
Evidence:
- `digest.spec` sets `process.env.PICKMAN_TEST_FENCE = "1"` and calls `workspace.dbPath(root)` directly, with one argument, and expects `nil` with a `.cache` reason. So `dbPath` itself must read the variable, which means `z-nile/lib/workspace.luau` contains the string `PICKMAN_TEST_FENCE`.
- Repo-fence's `sources()` walks `files("z-nile")`, which includes `z-nile/lib/`. Its only `z-nile/lib` exemption is `EXEMPT_DIRS = { "z-nile/lib/git-hooks/" }` plus `z-nile/lib/fence.sh` (lines 239–241). `bannedIn` matches case-insensitively.
- So repo-fence goes red on `workspace.luau` until an entry exists, and the design names four entries and forbids more. Today the only `z-nile/` files outside tests that name the variable are the guard's own (`git grep -ln PICKMAN_TEST_FENCE -- z-nile scripts zn`: `z-nile/lib/fence.sh`, `tests/lib/fence.luau`, `tests/lib/cachepaths.luau`, the rest specs).
- The refute's search ran over c0165's sequestered `.luau` files only, not over the modules the Design specifies.
Critique: The executor meets a red gate and must either add an unplanned fifth entry, against the Regression guard, or spell the name by concatenation, which the Modules row forbids and which is a guard evasion in code review. AC16 cannot see this: it checks only `acceptance/*.luau`.
Consequences: An entry for a library file (not a spec) that reads the guard marker is reviewed as a guard-adjacent change (zz-test, "Caught only by review"). Its reason must say that it only makes `dbPath` stricter (it never clears or sets the variable). The `specs.luau` entry's reason may also be wrong once `dbPath` does the check: say what `specs.luau` itself does with the name, or drop that entry if `specs.luau` never names it.
Recommendation:
- Add `z-nile/lib/workspace.luau` (`PICKMAN_TEST_FENCE`: "read only: a nested orchestrator's db must lie under `.cache`; never set or cleared") to the Modules row and the Regression guard.
- Re-derive the whole entry list by searching every module the Design specifies for each `NAMES` entry. Paste that search (zz-review/lists-paste-their-search): `specs.luau`, `workspace.luau`, `resultsdb.luau`, `reuseplan.luau`, `select.luau`, `context.luau`, `fingerprint.luau`, the `check.sh` lines and `setup.sh`, each against what its Design paragraph says it reads or sets.
- Add a Rules row: repo-fence passes with exactly those entries (a step 5 check the executor runs). AC16 can stay for the promoted copies.
Lesson: zz-review/lists-paste-their-search, zz-test/narrow-guard-allowances

## Check run
`./zn run --time 900 -- ./zn check c0165`: exit 1, 2/15 criteria passed, no bash error (`grep -ciE 'syntax error|command not found|unbound variable'` → 0). Every failure is expected before implementation:
- AC1, AC2, AC9: `@znile/lib/fingerprint` unresolved.
- AC3, AC4: missing modules.
- AC5, AC7: orchestrator and gate calls; prune, gate-full, gate-refs and gate-whole cases.
- AC6: no results file.
- AC10: the three docs cases.
- AC12: "gate-cover.spec.luau does not pass --graph-only exactly once".
- AC13: "no pickman/tests/inputs.tsv".
- AC15: `proof-interim:21`.
- AC16: the four names without entries.

AC11 and AC14 pass, as they should on today's tree.

Lesson candidates (for the lead):
- An audit that a rule must keep true after the item is done needs a promoted, rule-level check over editable data. A `check.sh` AC that freezes the audit expires at `done`. Check: once this item is done, which check fails when the next spec breaks the rule? (A note on z-design/rerun-shipped-audits-at-execution.)
- An allow-list fix searches the modules the design will create, not only the files that exist. Check: for every module the Design specifies, which banned names will its described behaviour force it to spell? (A note on zz-test/narrow-guard-allowances.)

Verdict: changes
