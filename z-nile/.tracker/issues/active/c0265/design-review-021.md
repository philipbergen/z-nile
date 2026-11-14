# Review 021: c0265 (design mode)
Inputs: prep commit 0afe581d (branch prep-work-heartbeat): c0265.md, check.sh, acceptance/{heartbeat,beat,edge,lost}.spec.luau, proofs/race.spec.luau (`git hash-object` 2840a4db…, matches AC4's pin), experiments/envelope.patch (`git hash-object` 024d62c1…, matches E16; its +/- lines equal `git diff 02dc8645 d7466492` on proto-c0265-env), harvest.md, design-review-019/020 and design-refute-019/020; prototype b809d79c (proto-c0265-raft, equal to origin/proto-c0265-raft) and d7466492 (proto-c0265-env); the siblings c0274–c0277 (their captured Problems, through `./zn find`; experiments/split not judged); z-nile/engine/raftplan.luau, main.luau (`start`, `ready`, `done`'s promotion, `promote-check`'s copy), tests/run.luau, tests/lib/trackerfix.luau; `./zn lessons --when design`, `./zn lessons --skill zz-review --full`.
Dropped from design-review-020: none. Verified fixed: design-review-019 F1–F11; design-review-020 F2, F3, F6, F7 and F8, each read against the prototype (lost.spec passed 13 of 13 on the envelope in my run). Repeated: design-review-020 F1's last bullet (as F3) and design-review-020 F5 (as F4). design-review-020 F4 is only partly fixed (F2).
Capture: `./zn capture c0265` prints `(no capture commit: first add)`, so it is not a confirmed capture; I judged it from the item's history, as rounds 019 and 020 did. Every captured outcome has an owner, here or in c0274–c0277 (the `Scope decision (user, 2026-11-08)` line). The new `nobeat` rule rests on a `Decided with the user (2026-11-08)` line. No scope finding.
Runs: in a scratch clone `$TMPDIR/rv3` of proto-c0265-raft, its origin repointed to a scratch bare clone. Every command went through `./zn run --time …`, one spec at a time, and each stub was reverted with `git checkout` afterwards. They were: the pushed prototype's own committed lost.spec (F2); race.spec on the envelope with one stub (F3); the issue's lost.spec on the envelope (13 passed, 0 failed); and two git probes in scratch repositories, `probe/merge.sh` and `probe/edges.sh`, for the landing read (F1, F5). No whole-suite run (the coordinator's load rule).

### F1 [medium] The landing read follows a merge-commit PR into its branch, so claims made while the raft runs read as "made after the landing" and turn lost at once
Where: c0265.md:72 (Assumptions to veto: "the commit time of the commit that first added `z-nile/engine/heartbeat.luau` to `origin/main` (`git log --diff-filter=A --format=%ct origin/main -- z-nile/engine/heartbeat.luau`, the oldest line) … survives a squash merge"); c0265.md:117 (Kinds); prototype main.luau:1542-1554 (`landingEpoch`).
Evidence: a scratch repository (`./zn run --time 30 -- bash probe/merge.sh`). The base is at …0000; the raft branch adds heartbeat.luau at …2000 (the executor's commit); a claim lands on main at …3000; the PR is merged with a merge commit at …4000. Output:
```
proto's read (no --first-parent):
1000002000
with --first-parent:
1000004000
claim since:
1000003000
```
The claim's `since` (…3000) is later than the landing the engine reads (…2000), so the claim is flatlined, not `nobeat`.

This is not hypothetical. `git log --merges --first-parent origin/main` lists five PRs merged with a merge commit between 2026-10-26 and 2026-11-01, four of them raft PRs: `Merge pull request #206 from philipbergen/R0053-risky-wall-picks`, #143 R0056, #159 R0059, #152 R0058 and #190 raft-pickman-chores. This raft's PR is the `run` gate, which zz-rules says is always a human's. The rule `gh pr merge --squash` has been broken at that gate within the week.
Critique: the user decided that claims made before the heartbeat raft landed never read lost until they beat once. The read that applies the decision succeeds with the wrong answer, so it fails open. Every claim made while this five-layer raft runs, never beaten and older than 900 s at the merge, is listed lost, and listed first, the minute the PR merges. With c0274 in the same PR it can be taken over, and with c0277 its worktree is discarded. All this while its owner still runs the old engine and the old skills, which never beat. No spec can see it: the fixture's single seed commit both adds the file and is the first parent. The tempting fix is a sentence telling the human to squash.
Consequences: with `--first-parent`, a squash and a merge commit read the same: the merge's time (the probe). It cost 55 ms over this repository's 2,032 first-parent commits (measured).

A second rule has no killing case: "the oldest line" (the fixture adds the file once). After a revert and a re-land, the oldest add flatlines every claim made while the heartbeat was reverted, which is exactly when no engine could beat them. `probe/edges.sh` printed `oldest add=1000002000 newest add=1000007000 since(mid)=1000006000`. The newest first-parent add holds those claims (`nobeat`) and fails safe for every other claim.
Recommendation: read the landing as the newest commit on main's first-parent line that adds the file: `git log --first-parent --diff-filter=A --format=%ct origin/main -- z-nile/engine/heartbeat.luau`, first line. Say so in Assumptions and in Kinds, and replace "survives a squash merge" with "any merge shape".

Make the read killable without rewriting the fixture:
- Put its arguments in the pure module, for example `heartbeat.LANDING = { "log", "--first-parent", "--diff-filter=A", "--format=%ct" }` and a pure `heartbeat.landing(stdout)` that returns the first number, or nil.
- Have `landingEpoch` run exactly those arguments.
- Add a heartbeat.spec or lost.spec case that builds a scratch repository under `.cache/c0265-landing` (fixture.git with `GIT_COMMITTER_DATE`): the file added on a side branch, a claim on main, a `--no-ff` merge, then a revert and a re-land. The case expects the merge's time, then the re-land's.
- Add Rules rows for the mutants "no `--first-parent`" and "the oldest line", and run them (E14).
Lesson: zz-arch/history-tests-survive-squash, z-design/new-rules-migrate-existing-work

### F2 [medium] The pushed prototype, which the executor starts from and the siblings stack on, commits stale round-1 specs, and its own lost.spec is red on its own code
Where: c0265.md:257 (Implementation step 2: "start from the prototype branch `origin/proto-c0265-raft` … rebase it on `origin/main` first"); c0265.md:58 (Delivery: "Each sibling's prep applies the patch to its own prototype, swaps in the real code of its layer and reruns these five files"); E13 and E16 ("All five spec files pass on it"); origin/proto-c0265-raft (b809d79c): z-nile/tests/acceptance/c0265/{beat,edge,heartbeat,lost}.spec.luau and proofs/race.spec.luau; tests/run.luau:51-58 (`collect` recurses into every folder); main.luau, `done` (`sh.git({ "mv", acc, dest })`) and `withPromotedCopies` (`if fs.isDir(acc) and not fs.isDir(dest)`).
Evidence:
- `git log origin/proto-c0265-raft -- z-nile/tests/acceptance/c0265` lists only `d9b64df4 proto c0265: no dead retired test`, a round-1 commit.
- Each of the four committed specs differs from the issue's (`git show … | cmp` gives DIFF). The committed lost.spec:137 still expects `c0050 preparing` in `lost`, and beat.spec:130, 155 and 171 still count every branch (`toBe(1)`).
- The five files pass in the local worktree only through uncommitted copies (`git status` there shows ` M z-nile/tests/acceptance/c0265/*.spec.luau`).
- Run in my clone at the pushed tip, unmodified: `../zn run --time 900 -- lune run tests/run -- tests/acceptance/c0265/lost.spec.luau` gives `FAIL … lost.spec:137: expected true, got false` and `10 passed, 1 failed`. c0050 is `[no beat]` under the same branch's 02dc8645.
- Review-020 F4 also asked to "record its tip sha in E13 and step 2". Neither names one.
Critique: an executor who follows step 2 literally brings these copies into `z-nile/tests/acceptance/c0265/`, and every z-nile gate collects them:
- The gate goes red on lost.spec:137, and on beat.spec's counts once c0275 lands.
- The real-time proof becomes a promoted spec with tens of seconds of real waits in every gate, against the user's standing rule ("real-work proofs are one-time check.sh-only scripts, never promoted").
- At `done`, `git mv acceptance tests/acceptance/c0265` moves the sequestered specs into the existing folder, as `tests/acceptance/c0265/acceptance/` (read). `promote-check`'s copy is skipped because the folder exists, so it checks the stale copies.
- The confused path is to "fix" the code until the stale lost.spec passes. That brings flatline back for c0050 and turns the sequestered lost.spec red at RC0.
- A sibling prep that "reruns these five files" on the pushed base without copying runs the round-1 files, so the Delivery rule checks the wrong cases.
Consequences: none beyond the text, once the prototype stops carrying spec copies.
Recommendation:
- Remove `z-nile/tests/acceptance/c0265/` from the pushed prototype (a commit `proto c0265: specs live in the issue folder`), and record the new tip sha in E13, E16 and step 2.
- In step 2, say what to take from the prototype: heartbeat.luau, the main.luau edge, dispatcher.luau, the skills, README and SETUP. Also say what never to take: any `tests/acceptance/c0265/` file. The sequestered specs run from the issue folder and `done` promotes them; the proof is never promoted.
- In Delivery, say where "these five files" come from: the issue folder at the landed prep commit, with `proofs/race.spec.luau` checked against AC4's hash. That is how a sibling prep runs them on its stacked prototype.
Lesson: z-design/in-flight-bases-pin-their-source, z-design/prove-specs-pass-on-a-prototype

### F3 [medium] (repeat of design-review-020 F1, its last bullet) The proof pins that `beat` does nothing before its own first look, a constraint on c0275 that the "kept by every layer" list does not name; three cases go red under a literal "every ./zn command in a worktree"
Where: proofs/race.spec.luau:134 (`pushfail` "2"), :153 (`restamp`, fired by the first push to any `hb/` branch) and :194 (`mainfail` "1 1": "the command's own first look passes, the first tick's look fails"); c0265.md:56-57 (the two lists); experiments/envelope.patch (`and name ~= "beat"`); c0275's captured Problem ("claim paths, every ./zn command in a worktree, long commands and the dispatcher beat").
Evidence: on proto-c0265-env (d7466492), with the issue's five files copied in, I changed one line to `and true -- STUB: autobeat in beat too`, so the autobeat also runs before a `beat` command, for the other claims the worktree holds. Then `../zn run --time 900 -- lune run tests/run -- tests/acceptance/c0265/proofs/race.spec.luau`:
```
FAIL … beat --watch says a failed tick and keeps beating … race.spec:143: expected 2, got 1
FAIL … beat --watch stops, saying why, when its claim is restamped … race.spec:160: expected true, got false
FAIL … one failed fetch of main inside a --watch tick is said and the loop beats at the next tick … race.spec:202: expected true, got false
3 passed, 3 failed
```
The stub was reverted afterwards. The autobeat's fetches and pushes use up the one-shot markers before the command's own reads. Review-020 F1 asked to "name it in the 'kept by every layer' list, or arm the failure from inside the tick", and refute-020 does not mention it.
Critique: the envelope passes because it hard-codes the one choice c0265's proof needs, and the Delivery list does not tell c0275's designer that the choice is no longer free. Reading the cases against the envelope finds four more constraints the cases impose and the list omits:
- (a) A refused first beat never fails its claim. lost.spec:118-120 and edge.spec:130-132 run `must(…status … preparing)` with every `hb/` push refused.
- (b) `beat`'s not-a-claim refusals come before any claim-memory refusal. beat.spec:176-177 expect "no claim" and "done" from a worktree that holds neither claim. The envelope was changed to fit, in d7466492 "refuse only a real claim".
- (c) After a takeover, the old owner's commands on its other claims still run. Its notices go to stderr; `beat` exits 1 saying `<id>'s claim was taken over (now <stamp>)`; `--watch` exits 0. See edge.spec:154-155 and the third case of edge.spec, in the same `wt`; and race.spec:159-161, followed by three more cases in the same `wt`, with `lost`'s stdout expected empty at :173. The envelope has no form of c0274's captured "its old owner is refused and told". Its autobeat beats the stamp `main` shows, not the remembered one. So after race.spec's restamp it beats the taker's claim from the old owner's worktree, and those beats fail only because that case hangs the read (read).
- (d) The main checkout's commands never beat. lost.spec:124 readies R0010 in the main checkout, and :156 expects it lost after `lost` and `status` run there.
Consequences: once listed, each constraint is a design input for c0274 and c0275 instead of a discovery at their prototype runs. Moving the markers into the tick would change race.spec, and AC4's hash with it.
Recommendation:
- Add (a) to (d), and "the `beat` command makes no other beat and fetches `main` once before its first tick", to the "kept by every layer" list.
- In the envelope, add the plainest form of c0274's "refused and told": a checkout whose remembered stamp for an item differs from `main` refuses `beat <id>` and `status <id> prepared` for that item, and says so on stderr for its other commands.
- Also add the first beat on `new raft`, `fold` and `recombine` (c0275's "claim paths"), and make the autobeat beat a remembered stamp only while `main` still shows it.
- Rerun the five files on the new envelope and record the run in E16 with the patch's new hash. Keep race.spec as it is.
Lesson: z-design/bottom-layer-pins-only-what-upper-layers-keep, z-design/mutation-runner-runs-correct-variants

### F4 [medium] (repeat of design-review-020 F5) The siblings' `depends_on` orders the layers but cannot keep c0265 in their raft; with those edges, a c0265 rafted on its own must land first
Where: c0265.md:59 ("Order is enforced by the siblings' `depends_on` … until it lands z-raft groups the five by argument"); c0265.md:55 and :43 ("lands only in its raft's one PR"); z-nile/engine/raftplan.luau; main.luau `start` (:3823-3838) and `ready` (:5127-5136); zz-rules, Dispatch ("a prepared raftless issue gets `raft-plan --apply` in `raft-<id>`").
Evidence: `grep -n depend z-nile/engine/raftplan.luau` gives no hit. The no-argument policy never reads `depends_on`. It folds a prepared raftless chore into "the lowest open prepared chore raft that still fits under the cap", or makes it a raft by itself when it is over the cap.

`start` and `ready` accept a dependency inside the raft and refuse one outside it until it is `done` ("a dependency outside the raft must already be done: nothing else orders rafts"). So once the capture lands, a c0265 in another raft is the one that must land first. That is the unsafe interim Delivery rules out (review-019 F3): a dispatched prep, told "the dispatcher beats for its steps", reads lost after 15 minutes, and "take ./zn lost first" has no takeover command behind it.

Meanwhile, this prep PR makes c0265 the only prepared, raftless member. Any session's `raft-plan --apply` can raft it before the four drafts are prepared, including the dispatcher's run for any other prepared raftless issue. Refute-020 F5 answers "fixed (stated)", but what it states is the mechanism review-020 showed does not hold.
Critique: what the edges enforce is the order, not the grouping. The Design calls it enforcement, and the coordinator's intent ("group by argument") is a habit, not a check.
Consequences: a raftplan rule ("skip an issue that a backlog issue not yet prepared depends on") is an engine change and needs its own capture. Holding the prep PR needs no code.
Recommendation: correct line 59 to say that `depends_on` orders the layers, and that a c0265 rafted apart from them lands first. Then make the grouping mechanical, one of two ways, and record which in Delivery:
- Do not merge this prep PR until c0274 to c0277 are prepared. Then land their preps and one rafting PR (`z-raft c0265 c0274 c0275 c0276 c0277`) together.
- Or land it now, together with a capture that makes `raft-plan` skip an issue named in the `depends_on` of an unprepared backlog issue. That capture needs its own spec case: raft-plan leaves c0265 out while c0274 is a draft.
This is a choice of delivery mechanics, not of scope.
Lesson: z-design/design-the-execution-window

### F5 [low] Smaller `nobeat` edges and sentences
Where and Evidence (`./zn run --time 60 -- bash probe/edges.sh`, a scratch repository):
- A claimed doc moved after the landing (a compaction or a `renumber`: a `git mv` that keeps the stamp) gets the move's time as `since`: `landing=1000002000 since(moved doc)=1000004000`. A claim that read `[no beat]` is then flatlined and reads lost 15 minutes after the move. The cause: `claimsOf` (main.luau) reads `since` from the doc's current path only (`git log -1 -S… -- <p>`). Before `nobeat`, a move only made a claim look younger, which was fail-safe. Now it removes the user's protection. `compact` refuses only while branches change a project root, and not at all under `--force`.
- c0265.md:72 says a shallow clone's landing is "infinite". In a depth-1 clone the read succeeds with the boundary commit (`landing=1000003000 (exit 0)  since=1000003000`), so every beatless claim reads `nobeat`. That is safe, but not for the reason stated.
- c0265.md:64 (Existing work) and the zz-rules bullet say the owner of a pre-landing claim "runs `./zn beat <id>`". On the raft's final tree, c0274 refuses a bare beat from a checkout with no claim memory (so does the envelope), and no pre-landing claim has a memory. The owner's command is `./zn beat <id> --adopt`, after `./zn sync`.
- c0265.md:173 (Lessons pass) still says "day one: every beatless claim older than 900 s reads lost on landing; the executor lists them in the PR". That contradicts Existing work and step 1 ("no migration list is needed").
- lost.spec:152 needs c0075's claim commit to fall in a later second than the seed commit, which is the fixture's "landing" (`trackerfix.new` makes one seed commit), and nothing checks it. If both fall in the same second, c0075 reads `[no beat]` and the case fails with no hint why.
Recommendation:
- In Kinds, say that a move resets `since`, so a pre-landing claim moved by a compaction loses `nobeat`. Alternatively, read `since` across the move from the compaction map (`idsLib.MAP_FILE`), with a case.
- Fix the shallow-clone sentence, the `--adopt` sentence and the Lessons pass line.
- Give c0075's claim a fixed second (`GIT_COMMITTER_DATE` set to the seed's time + 60 in that `zn` call), or assert the premise before line 152.
Lesson: zz-rules/item-history-spans-moves-and-compaction, z-design/restated-rules-move-together

### F6 [low] Labels and records left behind by round 2
Where and Evidence:
- AC2 (c0265.md:244 and check.sh:13) still says "keeps another terminal's fresh beat of a claim it has not fetched". The Test plan (c0265.md:185) says "keeps a young unfetched branch", and the Rules row (c0265.md:204) names the case "beat :: a beat keeps another terminal's fresh beat…". No such case is left: it is now "a beat leaves another claim's branch alone" (beat.spec:196), and the prune case checks that a young unclaimed branch survives (`preparing-fresh-fresh-fresh`, beat.spec:213 and 225).
- check.sh lines 22-25 are the same line four times.
- Refute-020 F1 says "lesson extended (bottom-layer-pins-only-what-upper-layers-keep)". But `git diff 1e1d2d58 0afe581d --stat` lists no skills path, and the lesson says nothing about absolute counts or the envelope. The round-2 candidate exists only as a harvest note.
Recommendation:
- Relabel AC2 (both copies), the Test plan line and the Rules row.
- Drop three of the four repeated lines.
- Extend the lesson with the note (an absolute count of a shared resource is an absence assertion; prove the early layer on an executable envelope of the later layers' captured effects), or correct the refute's wording.
Lesson: z-design/restated-rules-move-together

Candidate lessons (for the lead to place):
- zz-arch, a note on history-tests-survive-squash: a rule that dates an event by "the commit that added X to main" reads `--first-parent`, because on a merge commit the default history simplification follows the PR branch and returns the branch commit's time (F1). Check: what does the read return when the PR is merged by a merge commit, by a squash, by a rebase, and after a revert and a re-land?
- z-design, a note on in-flight-bases-pin-their-source: a pushed prototype carries no copies of the sequestered specs. Its committed copies lag the issue folder, the gate collects them, and `done`'s `git mv` nests the real specs under them (F2). Check: does `git ls-tree -r <proto> -- '*/tests/acceptance/<id>'` list anything?

Verdict: changes
