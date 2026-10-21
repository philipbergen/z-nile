# Review 005: R0042 (design mode)
Inputs: branch `prep-z-nile` at 59ed0a9 plus the uncommitted prep tree: `tracker/rafts/R0042/{R0042.md,check.sh,design-review-00{3,4}.md,design-refute-00{3,4}.md}`, `tracker/issues/c0114..c0118/{<id>.md,check.sh,acceptance/*,experiments/*}`. `scripts/tracker/main.luau` is byte-equal to 59ed0a9 (`git diff --quiet` exit 0). Compared with `main.luau` (`cmd.new` raft branch 769-863, `setStatus` 920-1004, `cmd.list` 1233-1288, `cmd.commit` 2282-2309, `cmd.spend` 3013-3185), `scripts/tracker/status.luau` (`ALLOWED`, `carriedByPr`, `canClaim`, the claim-stamp comment at 58-59), `scripts/tracker/ledger.luau`, `tests/acceptance/c0084/ledger.spec.luau`, `tests/acceptance/c0053/commands-{prep,claim,start}.spec.luau`, and the review, architecture, testing and tracker skills. Run during this review: a scratch Lune file in `/tmp` (removed) that calls today's `ledger.appendOnly(nine, nine, "c0001")`, which returned `no row was appended`; a grep of `tests/` for `appendOnly` and for `"status", …` callers.
Dropped from review-004: F2, F4, F5, F6. Their refutations fix what each finding named. I checked F2 (the `spend --model` case runs on backlog `c0003`, and the active refusal stays), F4 (the list case matches `^R0001%s`), F5 (the "members move" case asserts one commit, a shared `preparing-` stamp, unchanged member statuses and a refused `ready`) and F6 (`tab.spec.luau` is in c0118's `acceptance/` and requires a `pickman` view). F1's table is now in c0116, but the table itself has two holes. This is the fifth round on the hold mechanism, so F1 and F2 question the mechanism. F3's literal-replacement fix is right, but review-004 F3 also asked for each spec to be run against a prototype. That was not done for c0117 "model cell", and that case cannot pass, which is F3 below.

### F1 [high] c0116: after `recombine`, the keeper can never reach `prepared`, because the retired raft still holds the moved member on origin
Where: c0116 Design, hold paragraph ("`new raft`, `status <issue> preparing`, and the carried skip each refuse an issue a different raft holds") and table row "a listed member is held by a different raft | `status <raft> prepared` | refused"; recombine paragraph; `recombine.spec.luau` "members move" (56-96)
Evidence:
- Take the "members move" fixture after a successful `recombine R0001 R0002`. On origin, R0001 is `preparing-S` with `issues: [c0001]`, and R0002 is `preparing-S` with `issues: [c0002]`: recombine publishes status lines only, and the list edit and the removal of R0002 are worktree changes that land with the PR. In the worktree, R0001 lists `[c0001, c0002]`.
- z-raft's next step is the one c0116 gives for every raft: set `design: ready` and run the carried `status R0001 prepared`. The carried move reads the local list, so it checks c0002. c0002 is `prepared`, and origin's R0002 is `preparing` and lists it, so R0002 holds it. R0002 is "a different raft", so the table refuses the move and names R0002.
- Nothing can release that hold before the PR lands. R0002's origin document only goes away when the PR merges, and the PR can't carry R0001 as `prepared`. A recombined raft therefore lands as `preparing`, and `ready` refuses it. Getting it to `prepared` takes a second worktree and a second PR.
- No case checks this. "members move" stops at "`ready` is refused while the raft is `preparing`". "foreign hold refused" pins the refusal that blocks it. Every spec passes, and z-raft's main use of `recombine` fails at its next step.
- This is the fifth round with a hole in "who holds an issue while it is being rafted" (review-001 F7, review-002 F4, review-003 F1, review-004 F1). The hold is computed from origin `issues:` lists. Membership changes only in the worktree until the PR lands (`new raft` writes `raft:` locally; `recombine` edits `issues:` locally). So the origin lists are stale during exactly the window the hold exists to protect.

Critique: The tempting fix is "`recombine` also publishes the edited `issues:` lists". Publish accepts only `status:` edits to an existing document, and removing R0002 is a deletion, which publish does not do.
Consequences: Any fix has to say which holder counts as "the same claim". The repo already answers this: `status.luau:58-59` says "A claim stamp names the raft's claimed set" (R0025). `recombine` already gives both rafts one shared fresh stamp.
Recommendation: Key "a different raft" on the claim stamp, not on the raft id: a holder whose origin status is the same `preparing-` stamp as the raft being moved is the same claim and does not block. State it in the hold paragraph and as a table row. Then add to "members move", after the existing assertions: set `design: ready` on R0001 in the worktree, run `status R0001 prepared` (exits 0), commit, push to `main`, and assert that `ready R0001` succeeds and that origin has no `tracker/rafts/R0002/`. Keep "foreign hold refused" as it is: its two rafts have different stamps, so it still refuses. Prototype this one-line change on the same scratch patch as E1 and record the outcome. If that cannot be done in prep, take `recombine` out of c0116 and into a follow-up chore. The `new raft` and give-back half was run (E1) and can ship without it. Then update c0117's script-skill list and z-raft's text to match.

### F2 [high] c0116: the hold table has no row for claiming an existing raft, which z-raft's fold flow needs. Today that claim restamps prepared members, its give-back turns them `new`, and a given-back raft can take a member another raft holds
Where: c0116 Design ("Prepared members are never restamped"; "Folding one prepared issue into an open raft ... is `status <issue> preparing` ..., then the worktree edit, then `status <raft> prepared`"; the table row "members are `preparing` ... | `status <raft> new` | the raft and the members become `new`"); `main.luau:939-981` (`setStatus` adds every listed member and publishes `prepared>preparing` for each); `main.luau:811-814` (`new raft` refuses an issue whose origin `raft:` is set); `status.luau:6-13`
Evidence:
- **The fold path restamps.** z-raft folds into "one open prepared ... raft". The carried `status <raft> prepared` starts from `preparing` (`carriedByPr`), so z-raft must first run `status <raft> preparing` on that prepared raft. The design does not say so, and the table has no row for it. Today `setStatus` adds the raft's origin members and publishes `prepared>preparing` for each. So the landed, prepared members are restamped, which contradicts "never restamped". The fold step `status <issue> preparing` restamps the folded issue the same way, and the design prescribes that step.
- **The give-back then loses the designs.** After that claim, the members are `preparing`. The table row for `status <raft> new` with `preparing` members makes them `new`. Origin then shows `status: new-…` with `design: ready`, which is the loss review-003 F1 named. Those issues are also refused by `new raft`'s mixed-status rule next to any `prepared` issue.
- **A given-back raft can take a held member.** After "prepared give-back", raft R stays on origin at `new` with `issues: [c0001, c0002]`, and the case then creates R2 over c0001. `status R preparing` is `new>preparing`. `setStatus` adds c0001 and c0002 and publishes `prepared>preparing` for both, while R2 holds c0001. None of the three checking commands in the table is that command, so nothing refuses it.
- **A landed raft can't be given back cleanly.** A raft whose prep PR landed has `raft: R` on each member's origin document. With "a raft at `new` holds nothing", `new raft` of that member is still refused by today's owner check, "already belongs to R". The design does not say whether that check stays.

Critique: The tempting fix is one more row: "`status <raft> preparing` skips `prepared` members".
Consequences: That row makes the claim, the give-back and the hold agree only if the same "different raft" test from F1 runs on it. The owner check also has to agree with "a `new` raft holds nothing".
Recommendation: Give claiming an existing raft its own rows, using the stamp-keyed hold from F1:
- `status <raft> preparing` of a `prepared` or `new` raft stamps the raft only. A `prepared` member keeps its stamp. A listed member that a raft with a different stamp holds is refused, and the error names that raft. A `new` member is still stamped `preparing`, as in the c0053 abandon.
- The fold step for a raftless prepared issue edits only the worktree, with no `status <issue> preparing`. The carried move to `prepared` checks that no other claim holds the issue.
- `new raft`'s owner check ignores an origin `raft:` that names a raft at `new`.

Spec cases, each run through the real commands:
- A landed prepared raft R over prepared c0001: `status R preparing` leaves c0001's origin status byte-equal. `status R new` then publishes only R's document, and `new raft` over c0001 succeeds.
- After "prepared give-back" and a second `new raft` R2 over c0001: `status R preparing` exits non-zero, names R2, and leaves the origin tip unchanged.
- Fold: a raftless prepared c0003 is added to R's list in the worktree, and the carried `status R prepared` leaves c0003's origin status unchanged.

Run them on the E1 scratch patch, with `c0053/commands-{prep,claim,start}`, `c0067`, `c0068`, `c0070/board-refresh` and `c0081/remap`, and record the outcome.

### F3 [high] (repeat of review-004 F3, the "prove each spec can pass" part) c0117 "model cell" asserts `appendOnly(nine, nine) == nil`, which a promoted c0084 spec forbids, and its changed-model assertion cannot fail
Where: `c0117/acceptance/models.spec.luau:120-122`; `ledger.luau:271-273` ("no row was appended"); `tests/acceptance/c0084/ledger.spec.luau:178` (`refused(OLD, "no new row")`), `:202` (the comment: "each change below appends a row too, so only the field rule refuses it"); c0117 Rules row "a changed model fails appendOnly"; c0117 `Overrides: none`
Evidence:
- `ledger.appendOnly(nine, nine, "c0001")` returns `no row was appended`. I ran it on today's `ledger.luau`. c0084's promoted ledger spec requires exactly that refusal for an unchanged file. The c0117 case expects `nil`. No implementation passes both, and AC5 is sequestered, so the executor has to stop. Getting AC5 green means deleting the append rule, which reopens c0084 and is not named on any Overrides line.
- `appendOnly(ten, changed, "c0001")`: `changed` has the same two rows as `ten`, so it is refused with "no row was appended" whether or not `same` compares `model`. The mutant the Rules table lists ("drop the model", that is, `same` ignores `model`) passes. c0084 already shows the right shape: every rewritten field also appends a row, so that only the field rule can refuse it.
- c0117's Unknowns says "model cell stays red until the cell exists". It stays red after the cell exists too. Review-004 F3 asked for every sequestered spec to be run against a scratch prototype before this round. This case needed a ten-line `parse`/`render`/`same` patch. This is the fourth round for "a sequestered spec no correct implementation passes" (review-002 F1, review-003 F9, review-004 F3).

Critique: The tempting fix is to flip line 122 to `~= nil`.
Consequences: Flipping it is right but does not fix line 121. The class keeps coming back because the specs are checked by reading, and reading has missed it four rounds running.
Recommendation:
- Line 122: assert `appendOnly(nine, nine, "c0001") ~= nil`, or delete it, since c0084 owns that rule.
- Line 120: build `changed` from `ten`'s parsed rows with row 2's `model` set to `"other-model"`, plus a third appended row, rendered through `ledger.render`. Then only `same` can refuse it.
- Also add a positive case: `appendOnly(ten, ledger.append(ten, …, row("build", "grok-4.7")), "c0001") == nil`.
- Before sequestering, run `models.spec.luau` "model cell" against a scratch ten-cell ledger in `.cache`. It must pass, and the mutant "`same` ignores `model`" must fail it. Record both in E2.
- Do the same for every case whose module already exists: each case that drives today's `main.luau` or `ledger.luau`. Record which cases were run and which stay reasoned because their module is missing.

### F4 [low] Smaller gaps
Where: c0116 Rules and mutants table and E1; c0116 recombine paragraph; c0117 Design (`dispatch.plan`); c0118 Design (`view -O`)
Evidence:
- c0116 E1 says "The hold rows were run", but every row in the table is `reasoned`, and E1 records no mutant that failed. A passing prototype is half of a mutation run.
- E1 ran `c0053/commands-prep`, `c0067` and `c0068`. `c0053/commands-claim`, `c0053/commands-start`, `c0070/board-refresh` and `c0081/remap` also call `status` against `setStatus`. `affected` prints `ALL`, so the full gate catches a break, but only during execution.
- `recombine` moves review files onto the keeper. Nothing says what happens when both rafts have a `design-review-001.md`.
- `dispatch.plan` treats every skill other than the four script skills as a model skill. The root `.models.toml` has no row for `zz-rules`, `zz-arch`, `zz-test` or `zz-stats`, so `dispatch zz-test …` is an error. That may be intended, but it is not stated.
- `view [-O]`: `-O` "does not run `open`", and nothing says what `view` does without `-O`. Every case passes `-O`.

Critique: Each is a question an executor would ask.
Consequences: none
Recommendation: Mark the hold rows `run` and name the mutant each one killed, or keep them `reasoned`. Add the four spec files to the E1 run. State the collision rule: refuse the recombine, or renumber the moved file after the keeper's highest round. State that a skill with no row is an error from `dispatch`, or give the `zz-` skills `kind=script`. State what `view` does without `-O`.

Verdict: changes
