# Review 005: f0265 (design mode)
Inputs: prep head 7bf88c3cb9f179936a71af41f307a04ca4d7d8fa (`tracker: prep f0265 answer review round 4`), origin/main 7202e8ea; f0265.md, check.sh, acceptance/{heartbeat,beat,lost}.spec.luau, proofs/{dispatch,race}.spec.luau, experiments/heartbeat.proto.luau, design-review-001..004.md, design-refute-001..004.md, harvest.md, the two lessons added in round 4; `./zn capture f0265` (5208b315, a real `tracker: new` commit, no marker); `./zn lessons --when design`; z-nile/engine/main.luau (guarded, checking, rememberClaim/rememberedClaim, setStatus, cmd.status, cmd.sync, cmd.release, cmd.check/runCheck, new raft/fold/unfold/recombine claim sites, READ_ONLY), z-nile/lib/fence.sh (pickman_fence_env, pickman_guarded, pickman_checking), z-nile/lib/git-hooks/pre-push, z-nile/tests/lib/{fixture,fence}.luau, tests/lib/trackerfix.stub, z-nile/specs.luau (discovery), z-nile/skills/{z-design,z-raft,zz-test}/SKILL.md.
Replays (from z-nile, prototype copied to `engine/heartbeat.luau`, deleted afterwards, `git status` clean): `../zn run --time 600 -- lune run tests/run -- …`: heartbeat 16/16; beat 2/10 (setup, and the nested-checkout case, which passes today only because nothing beats); lost 2/11 (setup, the taker's carried move), every other case failing on a missing command or an assertion, not on setup; `./zn promote-check f0265` OK. A probe of `pickman_guarded` (`./zn run --time 30 -- bash g.sh`, a scratch repo and worktree in the scratchpad): with `PICKMAN_FENCE_REAL_GIT=<common>/.` it prints `unguarded`; with `<common>` it prints `guarded` (F1).
The c0265 rename on origin/capture-workers, the c0114/classified failure it explains, Q6's branch handling and the ref-vs-"pushed to main" wording are the user's (Assumptions) and are not judged here.

Round-4 answers verified in the documents: F1 (the notice is asserted on the old claimant's `sync`; I walked it: `sync`'s autobeat sees S1′ for c0010 and S3′ for the raft, drops both entries with the notice, and beats c0020; the carried move is local only (`setStatus` returns `{}` for a carried move), so origin still holds the taker's stamp S1′ when `status c0010 prepared` is refused; the later `lessons --tags` replaces c0020's beat, so the count holds and no S1′ beat appears); F2 (own file, E8 37/37, the rafting taker's `release` refused) except for the claim paths in F2 below; F3 (`guarded(true)`, `autoAllowed` gone, zz-test touched) except for the case itself (F1 below); F4, F6, F8 (case and check.sh label), F9, F10 (destination match; E1's `refs/heads/main:refs/zn/hb/…` form now reaches the beat arm, because it contains no `:refs/heads/main`). F5 is answered by moving the real-time cases to `proofs/` (consequence in F3). F7 is answered except for the signature block (F6).

Walk summary. I traced every case: which checkout runs the command, the clock it uses (ZN_NOW or real), each worktree's `.cache/tracker-beats` entries, `since` (the real commit time, at or after T0), each beat's epoch and what each `plan` deletes.
- beat.spec: the cases at lines 90-187 and 213 pass for a correct implementation, and the mutants listed for them fail. The case at line 189 fails for a correct implementation (F1).
- lost.spec: every case passes for a correct implementation, and the listed mutants fail. The `>=` mutant is caught by the revive case at line 181, not by the "inclusive" case at line 129: `since` there is later than T0.
- proofs/dispatch.spec: passes for a correct implementation, and fails for a dispatcher that beats only before or after the step.
- proofs/race.spec: every case passes for a correct implementation. Two details matter:
  - The race at line 152: the shim's restamp is written with `$REAL_GIT`, which bypasses the shim, the lease rejects the push, and the retry's callback sees `preparing-sunny-heron-lynx`.
  - `check c0090`: `runCheck` runs the check.sh with plain `bash`, outside any fence, so the outer process's tick is the only thing that beats. A mutant that beats only at the start writes an epoch before `start+2`, and the check fails.

### F1 [high] beat.spec's nested-checkout case fails for the implementation the Design prescribes: `pickman_guarded` compares the canonical checkout against the fence list's raw entries, so `<common>/.git/.` reads as unguarded
Where: beat.spec:189-211 (`local common = \`{h.f.main}/.git/.\` -- the fixture's git directory, spelled another way`); Design, Automatic beats ("the engine's own `guarded(true)` answers"); z-nile/lib/fence.sh:244-253 (`c=$(cd "$c" && pwd -P)`, then `case ":${PICKMAN_FENCE_REAL_GIT:-}:" in *":$c:"*)`); round-4 F3's Recommendation (the spelling was its suggestion).
Evidence: `pickman_guarded` resolves the checkout's common directory physically and looks for it verbatim among the list's entries. The entries themselves are never canonicalized. The fence always builds the list from `rev-parse --path-format=absolute --git-common-dir` (fence.sh:97), so real lists are canonical, and the spec's `…/.git/.` matches nothing. Probe: a scratch repo and worktree, `PICKMAN_FENCE_REAL_GIT=<common>/.` prints `unguarded`, and `PICKMAN_FENCE_REAL_GIT=<common>` prints `guarded`. So `guarded(true)` answers "unguarded" in this case. At T0+9000 wt's entries are due: c0010 was last beaten from wt at T0+1300 by `new raft`'s autobeat, and the new raft's entry is from T0+1300 too. The correct implementation beats c0010, and line 209 (`after == newest`) fails. The mutants "autobeat ignoring `guarded()`" and "comparing path strings" fail too, so the case tells nothing apart.
There are two more defects in the same case:
- The child's `PICKMAN_FENCE_REAL_GIT` *replaces* the runner's value, so for that child the real repository's git directory leaves the fence list. Under the macOS jail the kernel still protects the repository; on Linux only the hooks do, and they read this variable.
- On Linux the hooks then treat the fixture as real, so a mutant's autobeat fetch is refused by reference-transaction. The mutant then pushes nothing and passes. It fails only under the jail.
Critique: the Design's mechanism is right; the case was written to a property the fence does not have. The tempting fix is to make `pickman_guarded` canonicalize the list's entries. That changes a guard (review-only territory, zz-test "Caught only by review") for a spelling no fence ever writes.
Consequences: with the canonical spelling the case tests what happens in a real nested run. Appending keeps the real repository in the list. An assertion that does not depend on the push being allowed kills the mutant on both platforms.
Recommendation: in beat.spec:198-200:
- Compute the fixture's common directory as the fence does: `git rev-parse --path-format=absolute --git-common-dir` in `h.f.main`, then `pwd -P`.
- Pass `PICKMAN_FENCE_REAL_GIT = \`{process.env.PICKMAN_FENCE_REAL_GIT or ""}:{common}\``, appended, never replaced.
- Add an assertion that `{wt}/.cache/tracker-beats/c0010` is byte-identical before and after. The Design advances the epoch on a failed attempt too, so a mutant whose push the hooks refuse still fails this assertion.
- Drop "spelled another way" from the case and the Rules row, or move it to the checkout side (run from a symlinked path to wt), which `pickman_guarded` does canonicalize.
- Run the case with the prototype in place and a two-line autobeat stub, to see it fail for the mutant and pass for `guarded(true)`.
Lesson: zz-arch/compare-canonical-spellings, z-design/prove-specs-pass-on-a-prototype

### F2 [high] The stamp record that the user's "refuse" depends on is written only by `status <id|R-id> preparing`; z-raft's claims (`new raft`, `fold`, `unfold`, `recombine`) never write it, so the old rafting claimant's carried `status <R-id> prepared` passes after a takeover (repeat of review-003 F1's mechanism)
Where: Design, Takeover ("Every claim publish (`status <id|R-id> preparing`, the takeover included; `setStatus` today writes the memory for issues only, so it gains the raft case) records the new stamp in `.cache/tracker-stamp-<id>` … refuses only when this checkout **remembers** a stamp and it differs from origin's (a checkout with no record passes, as today)"); E8 (the prototype edits `setStatus` only); main.luau:1313, 1767, 1874, 1999-2000 (`new raft`, `fold`, `unfold`, `recombine` publish their claim outside `setStatus` and write only c0116's `tracker-claim-<id>`); z-raft SKILL.md:22-28 (z-raft claims only through those commands, never `status <R-id> preparing`); Problem, "refuse"; round-4 F2's Recommendation, which listed `new raft`, `fold` and `recombine`.
Evidence: lost.spec's own fixture shows the path. wt claims the raft with `new raft … c0030` (line 118), and that writes `tracker-claim-<R>` but no `tracker-stamp-<R>`. wt2 takes it over: S3 becomes S3′, and c0030 follows. Now wt runs z-raft's last step, the carried `status <R> prepared`. `setStatus` finds no stamp record for the raft, which "passes, as today". The member check (`tf.status ~= front.status`) compares origin's member and raft stamps, which are both S3′, so it passes. `canMove(preparing, prepared)` holds. The carried move edits wt's documents and the prep PR goes out: the second, silent prep the user's "refuse" forbids. No case runs this flow: lost.spec only takes over the raft and checks the taker's `release`. `unfold` is also missing from "First beats": an unfold claim gets no beat and no worktree entry, so it is flatlined from the moment it lands and nothing in the worktree keeps it alive.
Critique: the user decided "refuse" for "the old claimant's carried `status prepared`", with no exception for rafts. The design meets it for issues only, and z-raft's ordinary claim paths are exactly the ones left out. The refute answered round-4 F2 by splitting the file, but the claim-path list it was told to cover did not make it into the Design. The tempting fix is to read c0116's `tracker-claim-<id>` in the refusal as well. That is the mixing of facts the round-4 lesson forbids, and it would still leave `status <R-id> preparing` claims split across two files.
Consequences: writing the record in five more commands could change c0116 flows where a checkout's own resumed claim meets its carried move: a `fold` or `unfold` resume (`resumed`, no new stamp), and `recombine`'s two rafts sharing one stamp. The record must be written with the stamp the publish actually landed. A resumed `fold` keeps the old record, which still equals origin's stamp. The c0116 suite has to be run on that.
Recommendation:
- In the Design, list every claim publish and what it writes:
  - `status <id|R-id> preparing` (the takeover included) and `new raft`: write `tracker-stamp-<id>` (raft and members as published), a first beat and an entry.
  - `fold`, `unfold`, `recombine` (both rafts): the same.
  - `ready` and the legacy `start`: an `active-` stamp, a first beat and an entry. There is no carried move to refuse for them.
  - Add `unfold` to "First beats".
- Extend E8's prototype to those commands. Run c0116 (all specs) and c0053/commands-{claim,prep,start} on it, and record the result. Keep `Overrides: none` only if they stay green.
- Add a lost.spec case after the rafting takeover: wt sets `design: ready` on the raft and c0030, runs the carried `status <R> prepared`, and is refused with `taken over` and the new stamp. Add a Rules row, "the old rafting claimant (claimed by `new raft`) is refused", with the mutant "record written only by `setStatus`".
Lesson: z-design/claim-memory-rules-list-every-claim-path, z-design/confirm-overrides-with-a-suite-run

### F3 [medium] Moving the real-time cases to `proofs/` also took instant rules out of the permanent suite: after `done`, nothing guards fold's beat, the takeover race, or the no-retry-inside-the-interval rule
Where: proofs/race.spec.luau (cases at lines 152, 198 and 205-245); check.sh AC4/AC5 (`$HERE/proofs/…`, run whenever check.sh runs, not gated on the sequestered folder); Affected specs ("never promoted"); zz-test/specs-never-burn-real-resources ("with the suite keeping the same rules through a stand-in … plus one unmocked cheap observation").
Evidence:
- The race case (ZN_NOW plus a one-push shim) and `fold beats` wait for nothing.
- The second half of the hung-remote case (one failed attempt, then none inside the interval) needs no hang: `lsfail` makes the attempt fail at once, the same way lost.spec:196 does.
- Only `--watch`'s ticks, the outer-command tick, the dispatcher tick and the hung `status` need real seconds.
- After `done`, `acceptance/` is promoted and `proofs/` stays in the done folder, so the race refusal, fold's first beat and the throttle of failed attempts have no regression guard in the gate. A later change that drops `canTakeOver` from `publish.commit`'s callback, or fold's beat, stays green.
- check.sh runs the proofs unconditionally, so `./zn check f0265` on the done item still spends about 40 s of real waits.
Critique: the user's rule is that promoted specs wait for nothing, not that every case of an AC leaves the suite.
Consequences: three instant cases move back to acceptance/ (lost.spec or beat.spec, which already have the fixtures and fakes). The proofs then keep only the timed ones. AC5's label splits between them.
Recommendation:
- Move the race refusal, `fold beats`, and a `lsfail` version of the one-attempt-per-interval case into the promoted specs, each with its Rules row.
- Keep the `--watch` ticks, the long `check`, the dispatcher and the hung `status` in `proofs/`, gated in check.sh on `[[ -d $HERE/acceptance ]]`, as the lesson says.
- Rename AC4 and AC5's labels to match.
Lesson: zz-test/specs-never-burn-real-resources

### F4 [medium] The `git` shims match `ls-remote` only as the first argument; the Design never fixes the call's form, and the engine's own idiom (`git -C <root> …`) bypasses them
Where: lost.spec:87-93 and race.spec:71-75 (`if [ "$1" = ls-remote ]`); Design, Engine edge (it says "one `ls-remote`" and never gives the command's form); main.luau:514, 517, 555, 557, 2666, 3775 (`git -C root …`); dispatcher.luau:148-149 (cwd form).
Evidence: an executor who writes `sh.run("git", { "-C", mainRoot(), "ls-remote", "origin", "refs/zn/hb/*" })` is correct by the Design. This is a natural choice, since the takeover runs in a worktree and the Design already reads the run state from `mainRoot()`. With that form `lsfail`, `lshang` and `lscalls` never fire: lost.spec:197-204 and 222-225 and race.spec:208-242 then fail, and the hung `status` waits for nothing to hang. The same holds for `git --no-optional-locks ls-remote` or any `-c` option in front. Round-4 F10 was the same class of defect for push.
Critique: zz-test/stand-ins-answer-only-named-arguments. The shim should recognize the subcommand, not its position.
Consequences: none.
Recommendation: either state in the Design that the beat reads run `git ls-remote origin <pattern>` with the checkout as cwd and no options before the subcommand, or have the shims find the first non-option argument (skip `-C <dir>`, `-c <kv>` and `--*`) before comparing it with `ls-remote`. The second is more robust.
Lesson: zz-test/stand-ins-answer-only-named-arguments

### F5 [medium] "The skills say to take lost work first" (the user's "ok") reaches z-design only; z-raft and z-run, which pick rafts, say nothing, and AC6 checks only z-design
Where: Problem ("ok": "the skills say to take lost work first"); Design, The skills (z-design: "Candidates: take `./zn lost` first"; z-raft, z-run and zz-execute get only the loop bullet); check.sh AC6 (`g "./zn lost"` for z-design only).
Evidence: a lost rafting claim (a `preparing-…` raft) is picked up by whoever runs z-raft, and a lost active raft by whoever runs `/z-run`. Neither skill is told to look at `./zn lost` first. "z-run of a lost raft re-adopts it" says what happens once someone picks it, not that it is picked first.
Critique: a captured outcome ("lost work is picked first") that is met by a list and the README but not by every skill that picks work.
Consequences: none beyond text. `./zn work` (c0253) will read `heartbeat.order` later.
Recommendation: give z-raft (before raft-plan's policy) and z-run (before choosing a raft) a "take `./zn lost` first" bullet, and add both to AC6's `./zn lost` loop.

### F6 [low] Text that drifted in round 4
Where and evidence:
- Doc AC2 still says "never deletes a young beat of an unfetched claim" and omits "never beats from a protected (fenced) checkout", while check.sh AC2 says "keeps another terminal's fresh beat …, never beats from a protected (fenced) checkout".
- Doc AC3 still lists "a hung remote is bounded", which moved to race.spec (AC5), and check.sh AC3 reads "malformed beat refs and a malformed beat ref".
- Test plan, lost.spec: still lists "hung remote".
- Rules rows "unknown is never lost …" and "a malformed beat ref …" cite `lost :: … a hung remote is bounded`, which is now race.spec's case.
- The signature block omits `heartbeat.setting`, which the prose calls and heartbeat.spec tests (round-4 F7 asked for it).
- lost.spec:127's case is named "the stale limit is inclusive", but `since` there is later than T0, so the edge is never reached. The revive case at line 181 pins it.
Critique: z-design/restated-rules-move-together.
Consequences: none.
Recommendation: make the doc's AC2 and AC3 match check.sh word for word, fix the Test plan and the two rows, add `heartbeat.setting(env, name, default): number` to the block, and rename lost.spec:127's case (or note that the revive case pins the edge).
Lesson: z-design/restated-rules-move-together

### F7 [low] An unreadable `since` has no representation in the pure API
Where: Design, Kinds ("an unreadable one makes the claim unknown: `stale`, never lost"); `Claim.since: number`; `judge`/`settle` (prototype: `settle` turns every `stale` into `lost` once the parked table is read).
Evidence: the edge has no way to hand `judge` an unknown `since`. If it passes `0`, the claim is stale, and `settle` with a read PR list makes it `lost`, the opposite of the rule. No case covers it.
Critique: zz-arch/guard-no-is-explicit. The rule lives only in prose.
Consequences: an optional field changes `judge`'s type and one pure case.
Recommendation: make `since: number?` and have `judge` give an unknown `since` with no usable beat the kind `stale` plus a flag `settle` keeps (or a kind `unknown` shown `[stale?]`). Add a pure case and a row with the mutant "`since = 0` for an empty `git log -S`".

## Candidate lessons (for the lead)
- zz-test: **a spec that seeds a guard's input spells it the way the guard's producer writes it, and appends to the inherited value instead of replacing it**, because f0265 review 005 F1 found `…/.git/.` in `PICKMAN_FENCE_REAL_GIT`, which `pickman_guarded` (canonical checkout, raw list) reads as unguarded. The replacement also dropped the real repository from the child's fence list. Check: does the guard canonicalize this side of the comparison, and does the case keep the runner's own entries?
- zz-test: **moving real-time cases to one-time proofs moves only the cases that wait**, because f0265 review 005 F3 found instant rules (the takeover race, fold's beat, the retry throttle) left without a promoted guard. Check: for each case in `proofs/`, does it actually wait for a real limit, and if not, why is it not in `acceptance/`?

Verdict: changes
