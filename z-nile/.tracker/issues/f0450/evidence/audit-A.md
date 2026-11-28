# Audit A: closing f0420, f0421, f0424 and c0435 properly

As of `origin/main` 3e7b197e3 (2026-11-24; the main checkout is at the same sha, so the working-tree paths below are origin/main's). Read-only: nothing recorded, no worktree, no gate, no spec run. Commands run: `./zn capture`, `./zn guesses`, `./zn rounds --kind design|code`, `./zn status`, `./zn find`, `./zn approve <id> --check`, `./zn audit` (under `./zn run`), `./zn lessons --uncovered`, and git reads.

## Facts that hold for all four

- **Tracker state.** All four: `status: new`, `design: draft`, `raft:` empty, `depends_on: []`, no `size:`, no `approval.md` (`./zn approve <id> --check` prints "<id> has no approval" for each), no `harvest.md`, no `results.txt`, no `trace.md`. `./zn audit`: 0 errors, 0 warnings.
- **Risk.** f0421 and c0435 say `risk: risky` (design and code caps 9/9). f0420 and f0424 have no `risk:` (read as normal, 5/5). Both of those changed guards and the gate (f0420: `light.PROTECTED`, the publish exception; f0424: `z-nile/check.sh` stages, `lib/fence.sh`), so by z-design's Risk rule (`z-nile/skills/z-design/SKILL.md:59`) the closing designer should set them `risky`, which raises their caps to 9.
- **None can take the light path.** The light path needs `risk: easy` (zz-rules, the `ready` row; `light.reason`, `z-nile/engine/light.luau:288`), and lowering a risk to get it would be dishonest (and c0435's `easy.raised` makes a raise one-way). Every closing is a raft: design to `ready`, z-raft, `./zn ready`, layer, code review, trace, final review, approval, `./zn done`.
- **What runs in the gate.** Specs in `z-nile/tests/tooling/` run in the gate (each has a `.watch.txt`). A spec in a ticket's `acceptance/` folder is sequestered and never runs in the gate until `./zn done` promotes it (zz-test, `z-nile/skills/zz-test/SKILL.md:54`). Only f0420 has one: `z-nile/.tracker/issues/f0420/acceptance/workers-live.spec.luau` (1,023 lines, 17 cases). It has never run in any gate.
- **The review record is mostly missing.** Refute files exist without the reviews they answer: f0420 `refute-001.md` to `refute-004.md` with no `review-NNN.md`; f0424 `refute-001.md` to `refute-004.md` with no review; f0421 `refute-001.md` to `refute-004.md` with no `review-001.md` to `review-004.md` (only `review-005.md` and `review-006.md` exist); c0435 has no code review file, though its document cites "Code review 2" and "Code review 3" (`c0435.md:69`, `:74`). So `./zn rounds` says "no review yet" for f0420, f0424 and c0435, nothing of those rounds can be harvested or re-read, and lessons from them were filed with `from:` lines instead of `harvest.md` entries (for example `z-nile/skills/zz-arch/lessons/an-unreadable-gate-line-refuses.md:6`).
- **Guesses written in the document, not in `guesses.md`.** The approval covers `guesses.md` and the approval walk shows only those, so these would never reach the owner: f0420 18 inline (`Guess (prep) G1`-`G4`, `G6`-`G11`, `Guess (build) G12`, `G13`-`G19` under Open to the human) beside 5 recorded (whose numbers G1-G5 collide with the inline G1-G5 and mean other things); f0424 13 inline (`Guess (prep) G1`-`G12`, plus the round-2 lead guess at `f0424.md:130`), 0 recorded; c0435 8 inline (`c0435.md:70-75`, `:85-88`), 0 recorded; f0421 6 inline (`G-can1`-`G-can6`, `f0421.md:736-741`) beside 20 recorded.
- **A retroactive raft changes no source file.** The code is already on main, so a closing layer's diff is the ticket's tracker files only. Consequences, all from the engine's own rules:
  - `./zn trace --check` accepts `code` = `none` "when the stack changed no source file" (zz-rules, the `trace` row), and `## Source files` will be empty. The trace's code leg (idea = design = test = code) is then not checked by anything: the final reviewer has to be told to read the code on main (the merge commits listed per ticket below) and cite it in the review text, which `trace --check` cannot verify. The owner should say whether that counts as "closed properly".
  - zz-execute Phase 4's code review would be given `git diff origin/main...HEAD`, which is empty of code. It must be briefed with the merged PRs' diffs instead, or it reviews nothing.
  - `./zn finish` fails with "nothing to finish" when the layer diff is empty (`z-nile/engine/main.luau:4302-4305`); the Verification log commit zz-execute Phase 2 step 4 asks for makes it non-empty. Its `watch.txt` capture then falls back to the promoted spec's requires (`z-nile/engine/watchcmd.luau:120-145`), so f0420's promoted spec would be selected by `--affected` only through its test helpers, not through `workerlive.luau` and the other sources it proves.
- **Overrides made by hand on main.** Promoted specs were edited by these PRs with no override chore: f0420 #703 (`f0399/on.spec.luau`, `pick.spec.luau`) and #758 (`f0399/land.spec.luau`, `pick.spec.luau`); f0421 #695 (`c0119/scope-docs`, `d0415/dispatch`, `d0416/nested-second-review`), #717 (`c0117/control-cli`, `dispatch-cli`, `docs`) and #766 (`c0117/models`). zz-review design mode item 4 asks for each override's chore in `depends_on` unless the issue is itself a chore, and a missing one is **high**. f0420 and f0421 are features and name "this issue as its change" only. The design review will raise this, and only the owner can rule that a past hand override stands.

---

## f0420: Named raft works until landed

Merged PRs (first parent): 680c79ab5 #703 (steps 1-2, +2,636), 8e5fbbbe9 #710 (step 3, +3,062), ca8d1c24d #748 (step 4b, +2,256), 9e0b75761 #758 (steps 9-11, +2,091). Capture: 9b3b313af (#679), no marker: P1, S1-S4.

### 1. Outcomes

| outcome | state | where (code; spec, gate?) |
|---|---|---|
| P1: `./zn work <R>` stops at the first `end`/`wait` before R lands | delivered | `work.decide` with a target (`z-nile/engine/work.luau:1961`, `decideTarget` `:1565`, `work.walk` `:1443`), `depgraph.units`/`order` (`z-nile/engine/depgraph.luau:155`, `:120`); `tests/tooling/work-walk.spec.luau`, `work-walk-owed.spec.luau`, `work-walk-cli.spec.luau` (gate) |
| S1: keeps taking R's next action, stops only at landed or person-only | partly | delivered for a worker whose CLI can do everything (same code and specs). With several CLIs, a `waiting for a worker with ...` wait ENDS the session (`z-nile/skills/z-work/SKILL.md:15`) instead of the Design's `./zn work wait` (`f0420.md:133`), which does not exist (`./zn` usage lists no `work wait`, `work run`, `work release`, `work stop`) |
| S2: a person-only stop is a wait for `./zn approve` or a blocked raft's `questions.md` | delivered | owed items in the walk; `work-walk-owed.spec.luau` (gate) |
| S3: the last message names the raft, the stage and the exact command owed | delivered | Stops message (`work.STOPS`, `z-nile/engine/workgraph.luau`); `work-graph.spec.luau` "the Stops message: where it stopped, what each is owed, how to resume" (line 262) (gate) |
| S4: a wait the session can clear itself is never a stop: it holds, then continues | partly | z-work rule 6 asks again "at most once a minute" (skill text, `z-work/SKILL.md:15`), a model turn per poll; the no-model wait (Design F, AC31-AC34) is not built |
| Scope decision 2026-11-20 (`f0420.md:21`): walk the graph, deliver dependencies from the back | delivered | steps 1-2 above |
| same line: "make branches and branch off of those branches" | partly | one base: `ready --on` (`z-nile/engine/main.luau:6852-6857`, `On: R####` single, `z-nile/engine/layergit.luau:133`). Two or three bases (step 8, AC14-AC17): not built; E3 run (`f0420.md:309`), G17 |
| Decided 2026-11-20 (`:23`): order by what unblocks the most, then rank, then id | partly | `work.order` (`work.luau:1014`) over `depgraph.order`; `tests/tooling/work-order.spec.luau`, `work-order-can.spec.luau` (gate). "Then rank" not built: c0249 is `prepared`, not landed (G14, `f0420.md:321`) |
| Decided 2026-11-20 (`:25`): workers of several CLIs take one activity each from a queue; claims, heartbeat and takeover are needed here | partly | built: the capability filter (`z-nile/engine/workcan.luau:23`, `work.decide`'s `capable`; `tests/tooling/work-can.spec.luau`, gate; built under f0421 step 8b) and one live claim per unit (`z-nile/engine/workerlive.luau:372` register, `:437` join, `:499` decide; `acceptance/workers-live.spec.luau`, NOT in the gate). Not built: release after each activity once pushed (AC23, AC24, AC27), the `draft` split into design/design-review/design-answer, the backstop (AC25), takeover (AC26, c0277 is `active` in R0100, not landed), `gate_slots` (AC28), `Host:` trailer (AC29: no `Host:` anywhere in `z-nile/engine/`), `--cli none` (AC30), "waiting for your approval" (AC36: no such text in the engine), claims between hosts (c0254 `prepared`), R0100's adoption (R0100 `active`) |
| Decided 2026-11-21 (`:27`): the live layer is Go, f0424 | delivered | f0424 (below). This document's own Luau live-layer design is stale (section 2) |
| Decided 2026-11-21 (`:29`): `./zn work <ticket>` takes a ticket and its dependencies | delivered | `decideTarget` over a raftless ticket; `tests/tooling/work-ticket.spec.luau` (gate). How tickets are bundled is open (G16, `f0420.md:323`) |
| Decided 2026-11-21 (`:30`): a step's acceptance spec may be written by the worker but is reviewed apart | partly | the review of step 4b at 4691d2f56 happened (its F1-F7, SA1-SA8 are cited) but no review file is in the folder |
| Owner's statement 2026-11-22 (`:32`): "a theme at a time" | delivered | step 10: `work.inTributary` (`work.luau:1022`), `./zn work [next] <tributary>`; `tests/tooling/work-tributary.spec.luau`, `work-theme-cli`, `work-theme-fix`, `work-theme-gaps`, `tributary-source` (gate). No AC names it |
| (design, not captured) the light path, step 3 | delivered | `light.luau`, `lightgit.luau`, `lightready.luau`, `publish.luau` (`lightClaim`); `tests/tooling/light-path.spec.luau`, `light-publish.spec.luau`, `light-audit.spec.luau` (gate) |

Non-goal "`./zn work` with no raft named does not change" (`f0420.md:35`): the Decided line at `:23` exempts its order only, but step 4b (held units filtered from the unnamed pick: `work-held.spec.luau` F1) and step 8b (the capability filter on the unnamed pick: `work-can.spec.luau` "the unnamed case") also change unnamed answers. The 2026-11-20 multi-worker line can be read to cover it, but no line says so: a design reviewer may call it a high scope finding.

### 2. Design versus what was built

- Stale: "The live layer: a process boundary (B, E, F)" and "Luau now or Go" (`f0420.md:114-123`) describe a Luau store with flock, a `wake` file, `livecmd.luau` and `live.luau`. None exists; the owner chose Go (`:27`) and f0424's contract replaced it. Open bullet G11 (`:318`) is therefore moot.
- Stale: AC20-AC22 (`:252-254`) are f0424's contract now (f0424 AC14-AC16), and AC22 ("keeps its claim with `lost: true`") contradicts what was built (f0424: a dead pid's claim is released, outcome `lost`, `f0424.md:97`).
- Stale: Touched modules (`:160`) lists new `live.luau`, `livecall.luau`, `livecmd.luau`, `workwait.luau`, `workrun.luau`; Test plan (`:190-196`) names `acceptance/bases.spec.luau`, `live.spec.luau`, `turns.spec.luau`, `wait.spec.luau`, `run.spec.luau`, none of which exists.
- Describes unbuilt slices: step 4's own part (carriers.tsv replaced, `Host:`), steps 5 (all but the `can` filter), 6, 7 and 8 (`:286-291`); Design D/F/G and the R0100 paragraph (`:127`, `:131-137`).
- Missing: no AC for step 10 (tributaries) or step 11 (named ticket); AC19's third clause ("a `wait` for a worker is `./zn work wait`") is false against `z-work/SKILL.md:15`.
- Check lines: `check.sh` has lines only for AC40-AC46 (step 4b), all on the sequestered `workers-live.spec.luau` (the spec exists). AC1-AC19 (built) have no check line. AC23-AC36 are not built.
- Rules and mutants (`:198-228`): the `checked` column is empty in every row.
- Reviews: `./zn rounds f0420 --kind design`: "no review yet; run design review round 1 of at most 5"; `--kind code`: "no review yet; run code review round 1 of at most 5". refute-001 to -004 answer reviews that were never committed; none is filed with `./zn lessons --uncovered f0420` ("no reviews").
- Open to the human (`:316-326`), 10 bullets: G8 c0253 absorbed by step 7?; G11 Luau first, Go only if E6/E7 fail? (moot); G12 the light path's 150-line bound; G13 does a quiet holder's claim keep excluding its unit?; G14 the key between unblocks and id is empty (c0249), should tributary order be it?; G15 what a tributary names; G16 a named ticket is bundled by `raft-plan --apply` over every prepared ticket: keep, or plan only the named closure?; G18 the two `f0399` overrides of slice C; G19 a raft's tributary membership; G17 step 8 not built.
- Guesses not approved: 5 recorded (`./zn guesses f0420`: "5 guesses, not approved") plus 18 inline.

### 3. Smallest honest split

Close as f0420: P1, S2, S3; the walk half of the 2026-11-20 scope decision and its one-base case; "unblock the most" with the rank key named as moved; the Go decision; the named ticket; the theme mode; the light path; step 4b's per-unit live claim and the `can` filter. ACs: AC1-AC13, AC18, AC19 (first two clauses), AC40-AC46, plus new ACs for steps 10 and 11.

New ticket, working title **"Workers hand activities to each other: release, wait, run and several bases"** (feature, z-nile, tributary worker), outcomes:
1. A worker releases its activity once its result is on origin, and the next activity goes to any worker that can deliver it (AC23, AC24, AC27); S1 and S4 hold with several CLIs.
2. The design splits into design, design review and design answer activities.
3. A lost activity is taken over from origin's state (AC26, through c0277).
4. At most `gate_slots` held activities run specs on one machine (AC28).
5. A durable claim says its host, and claims across hosts are shown and never taken (AC29, c0254).
6. A `--cli none` worker gets only mechanical actions (AC30).
7. "waiting for a worker with ..." and "waiting for your approval" per unit (AC36).
8. `./zn work wait`: a wait for a worker or a held unit blocks with no model turn (AC31-AC34; f0424's daemon `wait` is the mechanism). AC19's third clause moves here.
9. `./zn work run`: the unattended loop, one session per activity (AC35; c0253 absorbed or not: G8).
10. The live claims replace `.cache/work/carriers.tsv` (step 4; the `f0399/land.spec.luau` override).
11. A raft built on two or three unlanded rafts (AC14-AC17, G17).
12. The rank key between "unblocks" and the id (c0249, G14).
Its `depends_on`: c0249, c0254, R0100's members (c0265, c0274, c0275, c0277). Outcome 11 is independent of the rest and can be its own ticket for parallelism.

Where it does not split cleanly: the Scope decision at `:21` and the Decided line at `:25` are single paragraphs that are half built. Each needs a new `Scope decision (user, YYYY-MM-DD)` line in both tickets saying which half each carries; without it the design review must call the moved half "deferred with no Scope decision" (zz-review design item 11, **high**). Also the backstop (AC25, "never the model the release names") predates the owner's 2026-11-24 ruling that a same-model review is allowed and only not preferred (`f0421.md:32`): the new ticket must restate it, not carry AC25 as written.

### 4. What `done` would refuse today, and the work to get there

Today, in order: there is no raft (`done` takes an R-id; `ready f0420` refuses a raftless issue that is not light, naming z-raft); `design: draft` (ready needs `ready`); no `size:` (`raft-plan` prints `skip f0420: no size`); no `trace.md`, no `final-review-NNN.md`; no approval with 23 unapproved guesses (in guess mode the walk answers `wait` for `./zn approve`).

Work:
- Prep (z-design, `prep-named-raft-works-until-landed`): set `risk:` (risky, as above); remove the stale Luau live-layer text, AC20-AC22 and the stale Touched modules and Test plan rows; move steps 4 (own part), 5-8 and their ACs (AC14-AC17, AC23-AC36) and Design D, F, G, R0100 to the new ticket under the owner's Scope decision lines; rewrite AC19; add ACs for steps 10 and 11; fill the Rules table's `checked` column from the Verification log mutants; record the 18 inline guesses (`./zn guess f0420 --step design|build`); name G18's two overrides in `Overrides:`; record `size:` (the four PRs, about 10,000 lines added).
- `check.sh`: about 20 new lines for AC1-AC13, AC18, AC19 and the step 10/11 ACs, running the gate's tooling specs (`work-walk*`, `work-graph`, `work-order*`, `work-tributary`, `work-theme-*`, `work-ticket`, `light-*`, `work.spec`) as c0435's `check.sh` does; keep AC40-AC46 on the sequestered spec, which `done` promotes to `z-nile/tests/acceptance/f0420/`.
- Capture the new ticket (z-idea, `./zn idea`, up to 3 idea rounds).
- Design review rounds, then z-raft (a feature raft; z-raft's policy will likely fold f0420 with f0424 and f0421, which share `work.luau`, `workerlive.luau` and `models.luau`; f0420's `depends_on` should then name f0424 and f0421, whose contracts it calls), `./zn ready`, one layer, code review, trace, final review, the owner's `./zn approve f0420`, `./zn done`.
- Owner rulings owed before approval: G12, G13, G14, G15, G16, G18, G19 stay with this ticket; G8 and G17 move; G11 is answered by the 2026-11-21 line.

### 5. Estimate and risks

About 250 changed document lines (mostly moved), 30 `check.sh` lines, 60 for the new capture. Review rounds: design 2-4 (cap 5, or 9 if risky), code 1, final 2-3: 5 to 8 rounds.
Risks:
- Promoting `workers-live.spec.luau` pins behaviour the new ticket will change: AC42's "a held wait leaves the holder's carriers row" (`check.sh` lines 56-57) pins `carriers.tsv`, which outcome 10 removes, and the "a quiet worker is not lost" behaviour pins G13, which is open. Each becomes an override the new ticket must name.
- That spec has never run in a gate: its run time (it starts live daemons) is unmeasured, against the owner's fast-gate rule.
- G16 decides how `./zn work <ticket>` bundles: a promoted pin of today's answer (`f0399/pick.spec.luau`, G18) may need changing if the owner picks "only the named closure".

---

## f0421: Risk scaled rounds and models

Merged PRs: f908d5ae7 #698 (design of slice 2), 670e00eea #695 (slice 1, +2,948), 07329ba33 #702 (step 5, +2,095), a420fd5f2 #717 (steps 6-7, +1,643), 18aed7e69 #754 (steps 8 and 8b, +1,139), aa9bab762 #766 (agy, +111), 6b7b2e030 #785 (Neon/Argon, same-model allowed, +1,590), 5cee0dc8b #793 (slice 3 S1a, +4,950). Capture: 70c1aa095 (#685), no marker: P1-P5, S1-S14.

### 1. Outcomes

| outcome | state | where (code; spec, gate?) |
|---|---|---|
| P1-P5 (one round for every ticket; review stuck on "review"; one model per role; only dispatch reads the file; low risk cannot spend less) | delivered | slices 1-2 below |
| S1: a risk level per ticket, set at design, the owner overrules | delivered | `rounds.level`, `audit` `risk` error; `tests/tooling/rounds.spec.luau` (AC4), `rounds-audit.spec.luau` (AC7) (gate) |
| S2: TOML maximum rounds per stage per level, and for the idea stage | delivered | `models.rounds` (`z-nile/engine/models.luau:920`); `rounds.spec.luau` AC1-AC3 (gate) |
| S3: the skills say the numbers are maximums | delivered | `rounds-skills.spec.luau` (AC12) (gate) |
| S4: an answered review counts as settled | delivered | `rounds.next` (`z-nile/engine/rounds.luau:196`), `openlist.unanswered` (`z-nile/engine/openlist.luau:323`); `rounds.spec.luau` AC5-AC6, `rounds-work-next.spec.luau` AC8, `rounds-dispatch.spec.luau` AC10, `rounds-idea.spec.luau` AC11 (gate) |
| S5: aliases xlight..ultra per CLI with model, effort, context | delivered | `[clis.<cli>]` (`.models.toml:123-152`); `models-activities.spec.luau` AC17 (gate) |
| S6: each activity per level takes an alias or a specific model | delivered | `[activities.*]` (`.models.toml:153-194`), `models.resolveActivity` (`models.luau:1734`); `models-activities.spec.luau` AC18 (gate) |
| S7: the seed (easy x/l, normal l/h, risky h/u) | delivered | `.models.toml:159-188`; `models-activities.spec.luau` AC27 first clause (gate) |
| S8: four different models on every CLI | superseded | Decided 2026-11-20 (`f0421.md:26`): a CLI may define only some aliases |
| S9: the final gate uses ultra at every level | delivered | `[activities.final-review] all = "ultra"` (`.models.toml:189-191`) |
| S10: a writer/reviewer pair on one model is refused at load | superseded | Decided 2026-11-24 (`f0421.md:32`); the check is gone (`f0421.md:754`); `models-activities.spec.luau` AC19/AC21 now assert the new rule, `ruling-wording.spec.luau` (gate) |
| S11: refused before any activity starts, and no model is ever quietly replaced | partly | "never quietly replaced" delivered (one CLI, no fallback: `c0117/dispatch-cli.spec.luau` overrides, `models-dispatch.spec.luau` AC25); the refusal half is superseded by S10's ruling |
| S12: a CLI that cannot deliver gives an error telling the person to switch | delivered | `./zn model` exit 1 and the waiting line (`z-nile/engine/modelcmd.luau`), dispatch `undeliverable`; `model-cmd.spec.luau` AC23, `models-dispatch.spec.luau` AC25 (gate) |
| S13: one configuration in a z-work session and under dispatch | delivered | AGENTS.md Subagents, the skills, the dispatcher on `resolveActivity`; `models-skills.spec.luau` AC26, `models-dispatch.spec.luau` AC24 (gate) |
| S14: takes over the round rules of f0417, c0418, c0251, c0306, c0325 and c0166's note | partly | the rules are built, but every one of those tickets is still open: f0417 prepared, c0418 new, c0251 prepared, c0306 prepared, c0325 prepared, c0166 preparing; whether to close c0325 and re-point c0251's AC15 is an open question (`f0421.md:772`) |
| Decided 2026-11-20 (`:26`): a CLI may define only some aliases | delivered | `models-activities.spec.luau` AC17, AC20 (gate) |
| Decided 2026-11-20 (`:28`): a worker takes only what its CLI can deliver | delivered (this ticket's half) | step 8b, `workcan.luau:23`; `work-can.spec.luau` (gate). The hand-back after each activity is f0420's |
| Decided 2026-11-24 (`:30`): agy writes with Neon, reviews with Argon | delivered | `[clis.agy.review]` (`.models.toml:145-152`), `REVIEW_ACTIVITY`; `models-review-table.spec.luau`, `models-activities.spec.luau` (gate). No AC names it |
| Decided 2026-11-24 (`:32`): a same-model review is allowed, recorded, not preferred | partly | allowed and recorded: `models.resolveReview` (`models.luau:1780`), `reviewrec.noteFor`, `same-model=yes|no`; `review-record.spec.luau`, `model-cmd.spec.luau` (gate). "Not preferred" is built nowhere: `models.tries` has no engine caller, and the hand-out preference (F10, `f0421.md:770`) is not built. No AC names it |
| Decided 2026-11-24 (`:34`): a level may hold several models | partly | S1a parses lists and resolves a list as its first entry (`f0421.md:493`); resolution over the lists is S1b, not built |
| Decided 2026-11-24 (`:36`): one catalog, per-CLI overrides, a substitute only with the person's yes, asked up front | partly | parsed and checked only: `[catalog]`, `offers`, `family`, `modelconsent.parse` (`z-nile/engine/modelconsent.luau:35`), `models.identity` (`models.luau:254`), the registration fixing the model (`workerlive.luau:254`, Go `internal/live/ops.go`); `models-catalog.spec.luau` AC29, `models-identity.spec.luau` AC30, `work-can.spec.luau` AC31, `models-pin.spec.luau` AC28 (gate). Not built: S1b (resolution over the catalog, the seed, `MODEL_OF_CLI` removed, AC32), S2 (substitutes and consent, AC33-AC35) |
| Decided 2026-11-24 (`:38`): a session may reorder a level for itself | not built | S4, design only (`f0421.md:466`) |
| Decided 2026-11-24 (`:40`): that preference is the operator's, session only | not built | S4 |
| Decided 2026-11-24 (`:42`): when the session's model is not the preferred one, ask first | not built | S4 |

### 2. Design versus what was built

- Stale: "Slice 1 of 2" (`f0421.md:67`) and "Slice 2 of 2" (`:239`): there is a slice 3. Slice 2's load errors (`:278`) still list the removed same-model refusal; `resolve` returning nil for the author's model (`:271`) is no longer true; the zz-review line to be written (`:293`, "A reviewer never runs on the model that wrote the text") contradicts the 2026-11-24 ruling; the seed tables (`:304-322`) have no agy and say "no pair shares a model", now moot.
- Stale ACs: AC21 (`:663`) asserts the refusal that was removed; AC22 (`:664`) counts canList pairs for a four-CLI seed (agy and its review table added since); AC27's second clause (`:669`, step 9: `[roles]` and `[fallback]` removed) is not built: `.models.toml:19-111` still holds them.
- Missing ACs: nothing names the agy CLI (#766, #785), the same-model ruling as built, or the step 8b capability filter as this ticket's (it sits under f0420's AC23 wording).
- Describes unbuilt slices: step 9 (`:690`); slice 3's S1b, S2, S3c and S4 (`:421-511`, AC32-AC36 at `:552-554`); the F10 hand-out preference (`:770`).
- Check lines: `check.sh` has only AC28-AC31, all on existing gate specs (`models-pin`, `models-catalog`, `models-identity`, `work-can`). AC1-AC27 (built, their specs in the gate) have no check line. AC32's spec `model-cmd-alts.spec.luau` and AC33-AC36's specs do not exist (correctly, no line names them yet).
- Reviews: design, `./zn rounds f0421 --kind design`: "round 1 answered; run design review round 2 of at most 9" (slice 3's `design-review-001.md`, verdict changes, 7 high, answered in `design-refute-001.md`; round 2 is owed before S1b, `f0421.md:727`). Code: "round 6 answered; run code review round 7 of at most 9" (`review-005.md` verdict changes, F1 and F9 high; `review-006.md` verdict changes, F1 medium). `review-005` F9 [high] (the build edited the sequestered `check.sh` and wrote AC29-AC31's specs) is answered "open to the human". `./zn lessons --uncovered f0421` lists 8 unharvested findings: review-005 F8, F9, F10, F11 and review-006 F1, F2, F3, F4.
- Open to the human (`:734-785`): G-can1 action-to-activity map; G-can2 an answer is the writer's activity; G-can3 the filter is off when the table or the CLI cannot be read; G-can5 `ready` maps to code; G-can6 a held unit leads a lacking one; G-can4 the seed as designed; (the owner's two 2026-11-24 rulings, recorded as built); close c0325 and re-point c0251?; slice 3 questions 1 (the whole seed, unranked models, agy exact ids), 2 (a session on an unplaced model), 3 (may a declared-only session deliver the final review; refuse or mark a row on another model), 4 (substitute distance; never the final review?), 5 (exclusive lists?), 6 (Fable through agent, NO ZDR), 7 (drop claude's tables?), 8 (every agent session needs `ZN_MODEL`), the F18 agent split, 9 (refuse a closer file that lowers a review's level?); review-005 F9 (slice check lines written by the builder?).
- Guesses not approved: 20 recorded (`./zn guesses f0421`: "20 guesses, not approved") plus 6 inline G-can.

### 3. Smallest honest split

Close as f0421: P1-P5, S1-S7, S9, S11-S13, S8 and S10 as superseded (cite their Decided lines in the trace's design cell), S14 once its tickets are closed or re-pointed, the 2026-11-20 lines, agy, the same-model ruling's "allowed and recorded" half, and S1a (the catalog, lists, offers and consent record are parsed and checked; the registration fixes the model). ACs AC1-AC20, rewritten AC21-AC22, AC23-AC26, AC27's first clause, AC28-AC31, plus new ACs for agy, the same-model record and the capability filter.

New ticket, working title **"One model catalog: resolution, substitutes with consent, session preference"** (feature, z-nile, tributary reviews-and-models), outcomes:
1. A level holds several models and the engine resolves among them: the catalog, per-CLI lists, the seed (S1b, AC32), with `MODEL_OF_CLI` gone.
2. A CLI missing a level gets a stand-in only with the person's recorded yes, asked up front in z-work, never for the final review (S2, AC33-AC35).
3. A review on the writer's model is not preferred when work is handed out (F10).
4. A session may reorder a level for itself; it is the operator's, session only; a mismatch is asked first (S4, the three lines at `:38-42`).
5. `./zn model --refresh` diagnosis (S3c, AC36; optional by the design's own words).
6. The legacy `[roles]` and `[fallback]` are removed (step 9, AC27's second clause).
It takes design-review round 2 and slice 3's questions 1, 2, 4-9 and F18 with it. Its rollout gates (S1b lands only when no worktree is older than S1a and no agent worker is registered) are already written.

Where it does not split cleanly: question 3 (declared-only sessions) and review-005 F9 bear on S1a, which stays: AC31 pins the `ZN_MODEL` refusal texts and the `(declared)` mark. The owner should rule them before f0421's approval, or S1a moves to the new ticket whole (then AC28-AC31 move too, and f0421 closes on slices 1-2 only). The Decided lines at `:32`, `:34` and `:36` are each half built and need Scope decision lines in both tickets.

### 4. What `done` would refuse today, and the work to get there

Today: no raft; `design: draft`; no `size:`; the design review is not settled (round 2 owed); 8 findings unharvested; review-005 F9 high open with no ruling; no trace or final review; no approval, 26 unapproved guesses.

Work:
- Prep: rewrite the stale slice 1-2 text and AC21, AC22, AC27; add ACs for agy, the same-model record and the filter; move S1b, S2, S3c, S4, step 9 and F10 to the new ticket under Scope decision lines; record G-can1-6; harvest the 8 findings (`harvest.md`, lessons); answer or move the questions; `size:`.
- `check.sh`: about 28 lines for AC1-AC27 on the existing `rounds*`, `models-*`, `model-cmd`, `review-record`, `agentenv`, `ruling-wording` and `work-can` specs.
- S14: `./zn close` (or re-point) f0417, c0418, c0251, c0306, c0325 and c0166's note, each by the owner's word: c0325's and c0251's sequestered specs pin the removed behaviour (`f0421.md:769`).
- Design review round 2 (the engine already counts round 1), then z-raft, ready, layer, code review, trace, final review, approval, done.

### 5. Estimate and risks

About 250 document lines (most moved), 35 `check.sh` lines, 60 for the capture, 10-20 for harvest and lessons. Review rounds: design 2-4 (cap 9), code 1-2, final 2-3: 5 to 9 rounds.
Risks:
- f0421 has no acceptance folder, so nothing is promoted; its pins live in tooling specs. `models-pin.spec.luau` (AC28) pins today's root answers line for line (1,399 lines, `f0421.md:705`) and is designed to be retired by S1b, so the new ticket must name it as changed.
- `work-can.spec.luau` (AC31) pins the `ZN_MODEL` refusal wording and the `(declared)` marks, which question 3 may change.
- The code review counter is per folder: `review-005.md` and `review-006.md` sit in the issue folder (`./zn rounds f0421 --kind code` reads them), while a raft's code review starts at `review-001.md` in the raft's folder. The settled-or-due state of round 7 is lost unless the closing raft's reviewer is told it.

---

## f0424: Live layer daemon

Merged PRs: b63402d09 #694 (design), 56a7da11f #701 (step 1, +4,648), a6723c020 #707 (step 2, +2,803), e49d3d369 #708 (+4), 19de7e2fc #709 (+3), da3a836d2 #715 (steps 3-4, +1,785), c9603d19e #722 (+171), 6acf1afa9 #740 (+65). Capture: 835cf9660 (#692), no marker: P1-P5, S1-S11. The document has no Decided or Scope decision line.

### 1. Outcomes

| outcome | state | where (code; spec, gate?) |
|---|---|---|
| P1: every claim is a commit pushed to main | partly | live claims make no commit (below), but the durable claims are still commits (`ready`, `status <id> preparing`); see S3 |
| P2: `carriers.tsv` does not name the CLI, what it can deliver, or the one activity | delivered | worker and claim records (`z-nile/go/internal/live/types.go`, `ops.go`) |
| P3: c0265's heartbeat says alive, not which CLI | delivered (the record) | the worker record holds the CLI; c0265 itself is unlanded |
| P4: a waiting worker asks again with a model turn | partly | the daemon's `wait` exists (Go `wait` op; `tests/tooling/live-cli.spec.luau` AC15); no worker uses it (f0420's `work wait` is not built; z-work polls) |
| P5: nothing emits an event when a step is recorded | delivered | `z-nile/engine/liveemit.luau:49`, `livecall.luau:212`; `tests/tooling/live-events.spec.luau`, `liveemit.spec.luau` (gate) |
| S1: a small Go daemon and a language-neutral contract | delivered | `z-nile/go/cmd/znlive/`, `internal/{live,store,wire,where}`, `zn`'s `live` case (`zn:33-61`); Go tests in the gate's Go stages, `live-gate.spec.luau` (gate) |
| S2: taking, releasing or beating a claim through the daemon makes no commit or push | delivered | `Core.claim` (`internal/live/ops.go:372`); `live-cli.spec.luau` (gate) |
| S3: a status change that only says "someone holds this" goes through the daemon; outcomes stay commits | not built | `./zn status <id> preparing` and `ready` still publish to main; the design keeps them and adds an event (`f0424.md:113`); f0420 4b says the durable claim "always wins" (`f0420.md:148`). No Scope decision line |
| S4: a claim is atomic | delivered | `internal/live/live_test.go` (AC1), `cmd/znlive/znlive_test.go` (AC10), `live-cli.spec.luau` (AC14) (gate) |
| S5: the daemon records each worker's CLI, can, activity, heartbeats, gone; `work status` reads it in place of `carriers.tsv` | partly | records delivered; `./zn work status` prints the daemon's worker lines after the git lines (`z-nile/engine/main.luau:9208-9239`; `live-readers.spec.luau`, gate). `carriers.tsv` is still written and read by `work next` (`z-nile/engine/workread.luau:754-782`) |
| S6: on one machine the daemon's heartbeat is the liveness record c0265's verdicts read | not built | no heartbeat module on main; R0100 (c0265, c0274, c0275, c0277) is `active`, not landed. No Scope decision line |
| S7: a waiting worker blocks on the daemon, near-zero CPU, woken within about a second | partly | the daemon side is proven (median wake 8.2 ms, idle 0.00 s CPU, `f0424.md:241`; AC6, AC15); no worker blocks on it |
| S8: one event per step forward, with who, what, when, tokens, seconds | delivered | the Who-emits table (`f0424.md:109-119`) as built in `liveemit`; `live-events.spec.luau` AC20-AC21 (gate) |
| S9: a reader follows the stream live; the board's workers panel and a live stats view read it | partly | `events --follow` (`cmd/znlive/opts.go:48`); the board's Workers strip (`z-nile/engine/board.luau:708`, `board.html:300`; `board-flow.spec.luau`, gate). No live stats view (the app's views are Workers and Approvals, f0437) |
| S10: the tracker's files in git stay the contract | delivered | design (`f0424.md:46`) |
| S11: first a spike proving the race, the wake and the idle cost | delivered | Verification log E1, E2 and the benchmark (`f0424.md:239-241`) |

### 2. Design versus what was built

- Unbuilt slice: step 5, rotation and retention (AC9, `f0424.md:236`): `internal/store/store.go` has `Open`, `read`, `Append`, `WriteSnapshot`, `Close` and no segment, rotation or `daily.tsv`; `internal/live/core.go:17` says "step 5: the events are trimmed to the current segment" as a future. `events.jsonl` and the in-memory events grow without bound today. E3, E4 and E5 (step 5's experiments) have no result.
- Missing from the Design: S3 and S6 are not designed at all, and nothing says why (zz-review design item 11, **high**).
- Stale: `Overrides: none` (`f0424.md:169`), but the c0120 `gate-homes.spec.luau` override is recorded under Open to the human (`:254`) and was merged by 18ccca3b8 (#762).
- Check lines: `check.sh` has none (only the template comment and `finish`), against AC1-AC25. The specs exist for all but AC9: Go tests (`internal/live/live_test.go`, `internal/store/store_test.go`: `TestRestartRestoresState`, `TestSnapshotThenEvents`, `TestTornTailRepaired`, `TestBadMiddleLineSkipped`; `cmd/znlive/*_test.go`) and tooling specs (`live-cli`, `live-autostart`, `livecall`, `liveemit`, `live-events`, `live-readers`, `board-flow`, `live-gate`, `live-runner-build`), all in the gate.
- Rules and mutants (`:183-195`): `checked` column empty; two rows name specs that do not exist (`live.spec`, `emit.spec`).
- Reviews: `./zn rounds f0424 --kind design`: "no review yet; run design review round 1 of at most 5"; code the same. refute-001 to -004 answer reviews that were never committed.
- Open to the human (`:251-254`): "G2, G4, G6 and G10 shape what f0420 calls: say so before step 2 if the daemon should be started by hand, if a silent worker should lose its claim, or if f0420's exit codes should differ" (step 2 is long merged, unanswered); the c0120 override note.
- Guesses not approved: 0 recorded, 13 inline.

### 3. Smallest honest split

Close as f0424: P2, P3, P5, S1, S2, S4, S8, S10, S11, S5's records and `work status` reader, S9's follow and board strip. ACs AC1-AC8, AC10-AC25.

New ticket, working title **"Live layer: holds without commits, heartbeat verdicts, retention and stats"** (feature, z-nile, tributary worker), outcomes:
1. A status change that only says "someone holds this" goes through the daemon and makes no commit (S3, and P1's rest).
2. On one machine, c0265's lost and parked verdicts read the daemon's heartbeat (S6; after R0100).
3. `.cache/work/carriers.tsv` is retired for the daemon's records (S5's "in place of"; shared with f0420's outcome 10, so one of the two tickets owns it).
4. A live stats view reads the event stream (S9's rest).
5. Rotation and retention: segments, `daily.tsv`, 90 days, in-memory events trimmed (step 5, AC9, E3-E5).
S7's worker half is f0420's new ticket (`work wait`); f0424 keeps the daemon half, and a Scope decision line says so.

Clean except S5 and S7, whose sentences are half built: each needs a Scope decision line assigning the rest.

### 4. What `done` would refuse today, and the work to get there

Today: no raft; `design: draft`; `check.sh` has no `check` line (`ready` refuses: it needs "a `check.sh` that has a check"); no `size:`; no trace, final review or approval.

Work: prep (Scope decision lines; move S3, S6, the stats view, step 5 and AC9; name the c0120 override; record the 13 guesses; set `risk:`; `size:`, about 9,500 lines added); about 24 `check.sh` lines (Go tests by `go test -run` from `z-nile/go`, the tooling specs by `tests/run`); the owner's answer to G2, G4, G6 and G10; capture the new ticket; design rounds, raft, layer, code review, trace, final review, approval, done.

### 5. Estimate and risks

About 100 document lines, 30 `check.sh` lines, 50 for the capture. Review rounds: design 2-3 (cap 5, or 9 if risky), code 1, final 1-2: 4 to 6 rounds.
Risks: AC5 and its Go test pin G4 (a silent live worker keeps its claim) while the owner has not answered it, and f0420's G13 asks the same question from the worker's side. Without step 5 the event log grows forever; closing f0424 without it needs the owner's Scope decision, not a silent move.

---

## c0435: Slim design for easy tickets

Merged PR: c39e7913c #757 (+1,402, 27 files). Capture: 89e122b4a, no marker, but a one-line stub ("An easy ticket gets a short design and one combined review", `idea: unchallenged`); `./zn idea` later wrote Problem, Non-goals and Solution S1-S10 after three idea rounds (`idea-review-001.md` to `-003.md`, each answered `revised`). The trace derives P1 from the capture and no S claim (the captured Solution is the template), plus AC1-AC3.

### 1. Outcomes

| outcome | state | where (code; spec, gate?) |
|---|---|---|
| P1 (captured): an easy ticket gets a short design and one combined review | delivered | below |
| S1: `risk:` is set first, the owner overrules | delivered | `z-nile/skills/z-design/SKILL.md:59`; `./zn model design --for` reads it (`light-path.spec.luau`, the 2026-11-23 note at `c0435.md:157`) (gate) |
| S2: the design is a short note of five parts | delivered | `easy.note` (`z-nile/engine/easy.luau:29`); `tests/tooling/easy-path.spec.luau` (14 cases) (gate) |
| S3: the test is written with the code, red first, no acceptance script | delivered (skill text) | `z-nile/skills/zz-execute/SKILL.md:32`, `:62`; no case pins it |
| S4: no experiments section, no size record | delivered (skill text) | `z-design/SKILL.md:61`; the engine never required either for a light ticket |
| S5: no separate design review; the light path unchanged | delivered | `light.reason` facts `designReviewed`/`reviews` (`light.luau:288`), `lightready.check`; `easy-path.spec.luau` "an easy ticket with the note and no design review is light" (gate) |
| S6: the light final review is the one review and judges the note | delivered | `zz-review/SKILL.md:137`; `easy-path.spec.luau` "the final review's text says it also judges the short note" (gate) |
| S7: that review keeps its model and the easy code cap (2) | delivered | unchanged rounds; `rounds-skills.spec.luau`, `readycheck.spec.luau` (AC3) (gate) |
| S8: an easy ticket off the light path takes the full design path | delivered | `readycheck.reason` refusal, the walk's `draft`; `easy-path.spec.luau` "c0435 review 3 A" (gate) |
| S9: the final review may raise the level, sending the ticket through the full path | delivered | `easy.raised` (`easy.luau:156`), `lightgit.raisedOf` (`z-nile/engine/lightgit.luau:176`), `publish.raiseEdit` (`z-nile/engine/publish.luau:427`); `light-path.spec.luau` "c0435 review 2 F1" (line 1291) and "review 3 B/C" (line 1372), `light-publish.spec.luau` "c0435 review 3 B" (gate) |
| S10: the gate, the final review on its model and the approval of every guess stay | delivered | unchanged; `risk:` joins the approval contract when not normal (`z-nile/engine/contract.luau:172-175`; `easy-path.spec.luau` "review 2 F5") |

Non-goal "It does not change the light path's conditions" (`c0435.md:30`): code reviews 2 and 3 grew `light.PROTECTED` (`easy.luau`, `rounds.luau`, `models.luau`, `modelcmd.luau`, `.models.toml`, `readycheck`, `readyfacts`, `workread`, `c0435.md:69`, `:74`), which makes fewer tickets light. A reviewer may read that as a breach; the honest fix is a `Decided with the user` line or the owner's ruling, not a code change.

### 2. Design versus what was built

- Stale: "As built" (`c0435.md:148`) says "Not wired: the walk does not name the full path itself", written before code review 2, whose change (1) wired exactly that (the walk answers `release` naming `./zn stop <R>`, `:69`).
- Duplicate empty `### Scalability`, `### Maintainability`, `### Usability` headings (`:90-92`) after the filled ones (`:77-82`).
- Template left unfilled: Touched modules (`:94-104`) misses `publish.luau`, `readycheck.luau`, `readyfacts.luau`, `contract.luau`, `light-publish.spec.luau`, `rounds-skills.spec.luau`, `rounds-work-next.spec.luau` and the seven skill files the PR changed; Affected specs, Unknowns & experiments, Test plan, Rules and mutants (header only; the mutants M1-M6 are in the Verification log, `:151`) and Implementation steps are empty; Regression guard still has the placeholder `Overrides: <promoted specs ...>` (`:118`), which zz-review design item 4 calls **high**. The PR changed no promoted spec, so the line should read `Overrides: none`.
- Check lines: `check.sh` AC1-AC3 run `easy-path.spec.luau`, `light-path.spec.luau`, and `readycheck`, `work-held`, `rounds-skills` (all exist, all in the gate). AC1 bundles six rules into one line; AC3 ("the refusals and rounds that stood before are unchanged") has no rubric a reviewer can fail.
- Reviews: `./zn rounds c0435 --kind design`: "no review yet; run design review round 1 of at most 9"; code the same. The idea rounds (3) are filed and answered.
- Open to the human: "none" plus the 2026-11-23 note.
- Guesses not approved: 0 recorded, 8 inline (G1-G8).

### 3. Smallest honest split

None needed: every outcome, captured and idea-stage, is delivered. c0435 can close whole.

### 4. What `done` would refuse today, and the work to get there

Today: no raft; `design: draft`; no `size:`; no design review; no trace or final review; no approval (G1-G8 not even recorded).

Work: prep (fix As built, remove the duplicate headings, fill Touched modules and the empty sections, `Overrides: none`, the Rules and mutants table from M1-M6, record G1-G8, `size:` about 1,400 lines; optionally split AC1 into its rules); the owner's word on the PROTECTED growth versus the Non-goal; design review rounds (cap 9: `risk: risky` stays, since this ticket changed guards); a chore raft (it cannot share a raft with the three features); ready, layer, code review, trace (4 claims), final review, approval, done.

### 5. Estimate and risks

About 70 document lines, 0-10 `check.sh` lines. Review rounds: design 1-2, code 1, final 1-2: 3 to 5 rounds. Smallest and cleanest of the four, and a good first closing to prove the retroactive-raft procedure.
Risks: no acceptance folder, so nothing is promoted. AC2's spec pins G6 (a raised raft is emptied, not retired) and G7 (a line starting "level" is a Level line), both unapproved guesses.

---

## Summary

| ticket | closable now? | outcomes delivered / partly / not | remainder ticket | blockers | size of closing work |
|---|---|---|---|---|---|
| c0435 | yes, whole, after the paperwork | 11 / 0 / 0 (P1 plus idea-stage S1-S10) | none | design review (none filed); placeholder Overrides line; 8 inline guesses unrecorded; owner's word on PROTECTED growth versus the Non-goal; no raft | about 70 doc lines; 3-5 review rounds |
| f0424 | yes, after a split | 9 / 5 / 2 (S3, S6 not built, no Scope decision) | "Live layer: holds without commits, heartbeat verdicts, retention and stats" (S3, S6, carriers.tsv, stats view, rotation AC9) | `check.sh` has zero checks; `Overrides: none` is false (c0120 gate-homes); G2/G4/G6/G10 unanswered; 13 inline guesses; no review files; owner's Scope decisions | about 100 doc lines, 30 `check.sh` lines, 50 capture lines; 4-6 rounds |
| f0421 | yes, after a split | 18 / 5 / 3, plus 2 superseded (S8, S10) | "One model catalog: resolution, substitutes with consent, session preference" (S1b, S2, S3c, S4, F10, step 9) | design round 2 owed; review-005 F9 high open; 8 findings unharvested; questions 3 and F9 bear on the S1a that stays; S14's six tickets still open; 26 unapproved guesses; owner's Scope decisions | about 250 doc lines, 35 `check.sh`, 60 capture; 5-9 rounds |
| f0420 | yes, after a split | 8 / 6 / 0 (14 rows, the uncaptured light path included; the unbuilt steps sit inside the 6 partly) | "Workers hand activities to each other: release, wait, run and several bases" (steps 4-8, AC14-AC17, AC23-AC36, rank key) | `check.sh` covers only AC40-AC46; stale Luau live-layer design and AC20-AC22; no AC for steps 10-11; 23 unapproved guesses; 10 open bullets; hand overrides with no chore; the promoted spec pins carriers.tsv and G13; owner's Scope decisions | about 250 doc lines, 30 `check.sh`, 60 capture; 5-8 rounds |

For all four: a raft is needed (none is `risk: easy`). The closing layer changes no source file, so `trace.md`'s code column is `none` everywhere, and the code review and final review must be briefed with the merged PRs.
