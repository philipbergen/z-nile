# Review 023: c0265 (design mode)
Inputs: prep commit 62218a9b (branch prep-work-heartbeat): c0265.md, check.sh, acceptance/{heartbeat,beat,edge,lost}.spec.luau, proofs/race.spec.luau (`git hash-object` 2c5aca61…, matches AC4's pin), experiments/envelope.patch (`git hash-object` e9a06fff…, matches E16; `git diff c3129cff c04880c4` on proto-c0265-env equals it line for line), harvest.md, design-review-019 to 022 and design-refute-019 to 022. Prototype c3129cff (proto-c0265-raft, equal to the local `origin/proto-c0265-raft`; `git ls-tree -r` lists no `tests/acceptance/c0265`). Today's origin/main f30d1d85, 21 commits past the prototype's base, none of them under `z-nile/engine`, `z-nile/lib`, `z-nile/tests/lib`, `z-nile/tests/run.luau`, `zn` or `z-nile/skills`, so a run on the prototype is a run on today's main for every file the specs load. The siblings' captured Problems (c0274 to c0277, read from the prep worktree); experiments/split/c0274, c0275 and c0277 design.md read only to see which choices their preps start from (not judged). `./zn lessons --skill zz-review --full`, `./zn lessons --when design`.
Dropped from design-review-022: none. Verified fixed: design-review-022 F1 (by reading: every case that restamps or takes over a claim does it in a checkout that runs nothing afterwards: edge.spec `wt3` and `wt2`, race.spec `wtB`, lost.spec `wt3`, so variants A and B pass by construction; the not-a-claim-first constraint is stated), F2 (the `landingpin` stand-in, lost.spec:81 and :363), F3 (`lockonce` and `movemain`; edge.spec and lost.spec green in my runs), F4 (`pushhang`, `ghhang`; race.spec green), F5 (the `--watch` bounds), F6 (59 cases: 21 + 10 + 5 + 15 + 8; the envelope's base; `landingArgs` in the interface; Scalability's fetch count; `35m` from 2130 s; c0040's own line; the first-parent note moved). Repeated: design-review-019 F8, its case part, as F2 below.
Capture: `./zn capture c0265` prints `(no capture commit: first add)`, so it is not a confirmed capture; I judged it from the history, as rounds 019 to 022 did. Every captured outcome has an owner, here or in c0274 to c0277 by the `Scope decision (user, 2026-11-08)` line, and each kept here has a Checked criterion. No scope finding.
The envelope, judged against the siblings' captured Problems: faithful and sufficient for what the five files exercise. c0274 ("taken over as a normal claim, recorded, and its old owner is refused and told"): no case runs a takeover command (the shims restamp), and no checkout runs anything after its claim changes, so where the notice goes and what is refused cannot reach a case; the bare-beat refusal and the claim memory are modelled. c0275 ("claim paths, every ./zn command in a worktree, long commands and the dispatcher beat"): the claim-path beat and the unthrottled autobeat are modelled; no case runs a long command or the dispatcher; the claim paths it leaves out (`new raft`, `fold`, `recombine`) change nothing a case reads (lost.spec's `new raft` claims c0030 at ZN_NOW = T0, and its `since`, a later real second, already wins `max`; read, not run). c0276 ("the board shows lost, parked and stale claims"): a verdict read after a publish is modelled; no case counts reads across a publish. c0277 ("a takeover discards the old worker's worktree and a numbered copy recovers its work"): no case discards; its discard guard is variant B. My lost.spec run on the envelope: 15 passed.
Runs: in a scratch clone `$TMPDIR/rv5` of proto-c0265-raft, origin repointed to a scratch bare clone, the issue's five files copied in as the brief says. Every command through `./zn run --time …`, one spec file at a time, each mutant and the envelope reverted with `git checkout` after its runs; probe specs in a scratch folder `tests/acceptance/c0265t/` of the clone, with their own fixture names.
- race.spec on the prototype: 8 passed (96 s, load 17 on 18 cores). A timing copy (prints added before each limit): hung push 10 s, hung fetch of main 3 s, hung gh 3 s.
- lost.spec on the envelope: 15 passed. c0116/docs 4/4, c0117/docs 9/9, c0114/layout 7/7 on the prototype (skill and usage text changed after E15's whole-suite run).
- luau-lsp analyze, stylua --check and selene on the five files: the four acceptance specs are clean; race.spec is not (F5).
- check.sh's AC5 block on the prototype: passes. Today's origin/main z-design names no `./zn lost`, so it fails there.
- Mutants: S23, S10, S16, S1 and `stamp(to)` survive (F1 to F4). S2 (the lock retry taken on any failure) is killed: race.spec 7/8, FAIL :204.
- Probes: the three cases recommended in F1 to F3, each run on the prototype (green), on its mutant (red) and on the envelope (green).
No whole-suite run (the coordinator's load rule).

### F1 [medium] The pull requests are read "lazily, only when some claim is stale", and no case fails when they are read on every call
Where: c0265.md Design, Parked ("The source is one `gh pr list …`, made **lazily**, only when some claim is stale (the common `status` costs nothing extra); a failing `gh` makes the list unknown"); Chore checklist ("and one `gh pr list` only when a claim is stale"); Scalability; prototype main.luau:1578 (`if not anyStale or #problems > 0 then`); Rules and mutants: no row.
Evidence: mutant S10, `if #problems > 0 then` (the list read whatever the verdicts), gave lost.spec `15 passed, 0 failed`. No case lets `gh` fail while nothing is stale. `ghfail` is armed at LATE + 5 × STALE (lost.spec:302) and `ghhang` at now + 20 × STALE (race.spec:234), and both have stale claims. I made a probe copy of lost.spec that adds one step to "nothing is lost while the claims are fresh": arm `ghfail`, run `lost` at T0 + 60, expect `ok` and an empty stdout.
- Prototype: 15/15, `PROBE lost ok=true stderr=`.
- S10: 14/15, `PROBE lost ok=false stderr=lost: pull requests unreadable: gh: fake failure`, FAIL lostg.spec:163.
- Envelope: 15/15.
Critique: an eager read is the obvious simplification, and nothing catches it. Once it is in:
- Every caller that runs `./zn lost` first fails whenever `gh` cannot answer (offline, logged out, rate limited), though nothing could be lost. That is z-design's Candidates, z-raft, z-run step 0 and c0253's worker.
- Every `status` makes a GitHub call. c0276's board read after each publish, and R0084's live board, multiply it.
- The Chore checklist's "every existing `./zn` command behaves as it did" rests on this rule.
Consequences: the case runs `lost` and `status` in the main checkout, with fresh claims, where no later layer beats, so it holds on the final tree (the probe is green on the envelope). It also becomes a constraint on c0276: a board that wants pull requests reads them itself, not through an eager `judgeAll`.
Recommendation:
- In lost.spec, "nothing is lost while the claims are fresh": arm `ghfail`, then run `lost` at T0 + 60 (expect `ok`, stdout `""`, and no "pull requests" in stderr) and `status` at T0 + 60 (expect `ok` and no `[stale?]`). Remove `ghfail` afterwards.
- Add the row: "the pull requests are read only when some claim is stale: a failing gh changes nothing while every claim is fresh | lost :: nothing is lost while the claims are fresh | S10 the list read on every call | run". Run it and record it in E14.
- Add "the pull requests are read only when a claim is stale" to Delivery's "kept by every layer" list.
Lesson: zz-test/pin-fail-safes-where-they-act, z-design/spec-design-correspondence

### F2 [medium] (repeat of design-review-019 F8, its case) The fresh-stamp row's reason is false: a git stand-in observes the claim path's `hb/` check, and the row's own mutant passes every spec file
Where: Rules and mutants, "a `preparing` claim draws a stamp new on origin/main and without an `hb/` branch | (none) | `stamp(to)` kept | reasoned: a collision cannot be observed (1 in 13,824)"; Assumptions to veto, third bullet; prototype main.luau:1847 (`freshStamp(to)`) and :607 (the `ls-remote --heads origin refs/heads/hb/<v>` inside `freshStamp`).
Evidence: the row's mutant, `local value = stamp(to)`, gave beat 10/10, edge 5/5 and lost 15/15. heartbeat.spec is pure, and race.spec asserts nothing about a stamp (read). I wrote a probe spec with a fakecli fixture holding one new issue and a worktree. Its git stand-in answers the first `ls-remote` naming `refs/heads/hb/` with `0000… <ref>` and records the arguments; then the probe claims the issue.
- Prototype: 1 passed, `PROBE refused=preparing-plucky-copper-mellow stamp=preparing-crimson-brisk-mellow`.
- Mutant: FAIL freshp.spec:48. The claim never asked about an `hb/` branch, so the record file was never written.
- Envelope: 1 passed.
Critique: the stamp is the lease's identity (Design, The lease). If two claims share one:
- one claim's beats keep the other alive, so a lost claim is never listed;
- a PR that names one parks both;
- c0274's swap deletes a live branch.

The mutant is the line as it was before review 019, and a rebase conflict in `setStatus` (a hot function on main) would bring it back. Refute-019 F8 dropped the case review 019 asked for because "a collision cannot be observed". But no case has to wait for a collision: a stand-in can answer the check as if one happened.
Consequences: the case pins only the `hb/` half. The origin/main half goes through `claimsLib.taken`, the same path `new raft` and `ready` use (status-fresh.spec pins the retry). Under c0275 the claim's first beat runs after the publish, through fetch and push rather than `ls-remote`, so the case holds on the final tree (the envelope run).
Recommendation:
- Add a case, either to beat.spec's shim or to lost.spec's, which already arms one failure per marker. A marker makes the first `ls-remote … refs/heads/hb/…` answer with a line and record the value. Claim a newly seeded issue from a worktree of its own (c0020 and c0030 are used by other cases), and expect the published stamp to start with `preparing-` and differ from the recorded value.
- Make the row `run`, with that case and the `stamp(to)` mutant.
Lesson: z-design/reasoned-rows-claim-testable-reasons

### F3 [low] The rule "the beats are read before main" has no row, and its mutant passes every file
Where: c0265.md The lease ("The beats are read **before** `main`, so a branch a taker created after the beat read its list is never judged unclaimed by the beat's own pruning"); E13 (3); prototype main.luau:1651-1658.
Evidence: mutant S23, `beatPaths()` before `readBeats()`, gave edge 5/5 and beat 10/10. Every takeover in edge.spec and race.spec is armed on a push, which comes after both reads. I made a probe copy of edge.spec with one more case. A marker runs the shim's own `takeover` on the beat's first `fetch … hb-seen`. The claim (c0074) is made and first beaten in a worktree of its own, and the race beat runs at now + 1000.
- Prototype: 6/6.
- S23: 5/6, FAIL at :174 (`tipOf(new) ~= ""`): the taker's epoch-1 branch was pruned as unclaimed.
- Envelope: 6/6.
Critique: low. A real taker's branch carries the taker's own clock, so the 900 s grace keeps it whichever read comes first, unless clocks differ by more than the limit. But the Design states the rule as one that running found, and nothing pins it.
Recommendation: add the case (a marker `takeoverread` in edge.spec's shim) with the row "the beats are read before main | edge :: a takeover between a beat's branch read and its main read … | S23 main read first | run". Alternatively, keep the row `reasoned` and give the grace as its reason, saying the order is observable only with a branch dated older than the limit.
Lesson: zz-arch/read-paired-facts-at-one-moment

### F4 [low] Three more stated details have no killing case, and one stand-in answers more than it names
Where and Evidence:
- **The parser's shape.** Name: "`parse` accepts a branch `hb/(preparing|active)-<word>-<word>-<word>` … any other branch under the prefix is a problem". Mutant S16 (the shape test dropped, only the subject match kept) gave heartbeat.spec 21/21. lost.spec's `hb/garbage` has a commit subject that is not a beat's, so it stays a problem under the mutant too. Under it, `hb/prepared-a-b-c` with subject `hb prepared-a-b-c <n>` becomes a beat of no claim instead of a named problem.
- **The exit code with a malformed branch.** `./zn lost`: "lost then lists nothing it cannot confirm and exits 0". Mutant S1 (exit 1 after the problems are printed) gave lost 15/15: the malformed-branch case never reads `still.ok`.
- **The lock retry on the fetch of main.** Shared state: "the heartbeat's fetches retry once … on `cannot lock ref`". `lockonce` arms only the `hb-seen` fetch (lost.spec:90), so a `beatPaths` that calls `netRun` instead of `netRetry` (main.luau:1624) passes. That is read, not run. S2 is killed, so the retry's condition is pinned; only its use on the fetch of main is not.
- **`nolog` answers more than it names.** `nolog` (lost.spec:83) fails every `git log`, not only the claim's `since` read it is meant for. A later layer that adds a `git log` to `status` or `lost` and lets its failure raise would turn that case red for a reason it is not about (read). An example is c0274's takeover record, which it keeps in the claim commit's subject.
Recommendation:
- Add `hb/prepared-a-b-c` (subject `hb prepared-a-b-c 1`) and a two-word `hb/preparing-a-b` to heartbeat.spec's problem case.
- Assert `still.ok` in lost.spec's malformed case.
- Arm a lock failure once on a beat's `fetch … origin main`. Arm it only inside `beat`: `lost`'s own fetch of main is the shared, unbounded one. Or say in a row why the main fetch's retry is `reasoned`.
- Narrow `nolog` to the `-S` read (`*-Sstatus:*`).
- Add a row for each.
Lesson: zz-test/stand-ins-answer-only-named-arguments, z-design/spec-design-correspondence

### F5 [low] The proof's three hang cases sit close to their limits, and the proof uses an undeclared global
Where: proofs/race.spec.luau:67, :76 and :87 (`sleep 30` for `ghhang`, `mainhang` and `pushhang`); :216, :226 and :239 (`< 25`); :128 (`wtB = …`, while line 14 declares only `wt`).
Evidence:
- Timing copy at load 17: the hung push took 10 s. That is four 2 s bounds (a prune of c0085's old branch, which ZN_NOW = now + 2000 ages past the limit, and the write, each tried twice) plus the overhead. The limit is 25 s and the hang 30 s, so the margin is whatever the host's overhead leaves; review 022 ran at load 68 to 185.
- `luau-lsp analyze … proofs/race.spec.luau` gives `TypeError: Unknown global 'wtB'`, and selene gives 2 errors and 1 warning. The gate ignores `**/.tracker/**` and the proof is never promoted, so nothing fails today.
Recommendation: make the three hang markers `sleep 120` and the three limits `< 60`. The bound kills the group, so a correct run costs the same, and an unbounded mutant still waits 120 s and fails. Declare `local wt, wtB = "", ""`. Then update AC4's hash and rerun race.spec on the prototype and on the envelope (E16).

### F6 [low] Text and records
Where and Evidence:
- **`nobeat` before the limit.** Kinds says a claim made at or before the landing is `nobeat` "while it has never beaten". `judge` makes `nobeat` only of a claim that would otherwise be stale (heartbeat.luau:102). So a pre-landing claim less than 900 s old reads live, unmarked, during the first 15 minutes after the landing.
- **Variants A and B are prose.** E16's two variants exist only as text, so a reader cannot rerun that record. They pass by construction (see Inputs), so the claim holds.
- **A property written where a constraint belongs.** Delivery says "no case beats from the main checkout", which describes the cases. The constraint the cases impose is that `lost` and `status` in the main checkout never beat: lost.spec:173 expects R0010, readied there, to be lost after both have run there. c0275's capture says "in a worktree", so it holds.
Recommendation: say in Kinds and in zz-rules' bullet "a stale claim made at or before the landing that has never beaten is `nobeat`". Either keep A and B as hashed patches beside envelope.patch, or say in E16 that the cases make every form pass by construction. Write the main-checkout line in Delivery as the constraint.

Candidate lessons (for the lead to place):
- zz-test, a note on pin-fail-safes-where-they-act (F1). A read the design makes lazy ("only when X") is a fail-safe too. Pin it with a case where X is false and the source it skips fails, so an eager read turns into a spurious "unreadable" and a failed command. Check: for each "read only when" rule, does a case make the skipped source fail while the condition is false?
- z-design, a note on reasoned-rows-claim-testable-reasons (F2). "A collision cannot be observed" is rarely true: a stand-in can answer the collision check, so no case has to wait for a real collision. Check: can a stand-in answer, as taken, the check the row says cannot fire?

Verdict: changes
