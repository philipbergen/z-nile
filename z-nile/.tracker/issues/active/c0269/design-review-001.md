# Review 001: c0269 (design mode)
Inputs: worktree `prep-rename-done-gate-spec-titles` at 81c74fae (origin/main d338575e, merge base 81c74fae), with the uncommitted `c0269.md`, `check.sh`, `acceptance/titles.spec.luau` and `acceptance/narrow.py`; `./zn capture c0269` (abdfacb3, a confirmed capture with no markers); R0086 review-001 F2; c0180 (`narrowings.luau`, `narrowed.spec.luau`, `inputs.spec.luau`, c0180.md), c0241.md, c0178 (active: `overrides.spec`, `check.sh`, `prototype.patch`), c0123 (`check.sh`, `prototype.patch`), c0083 `check.sh`, c0174 `check.sh`, c0136, c0179 (prep worktree `prep-fixture-volume-no-fseventsd`, uncommitted); `git worktree list`; `./zn lessons --skill zz-review --full`, `./zn lessons --when design --full`; the z-raft policy (z-raft SKILL.md, `./zn raft-plan`).

Runs (all through `./zn run --time …`, in a scratch clone `c0269rev` under my session scratchpad, at d338575e, removed after; the real worktree was only read):
- `./zn check c0269` in the worktree: 1/4. AC1 and AC2 fail on their assertions (old titles stand, the scan names exactly the two files, the `inputs.tsv` row is missing), AC4 says both files differ from base+substitutions, and AC3 passes. These are the right reasons. `./zn promote-check c0269`: OK (2 passed). It runs only the type check and the meta check, not the format check.
- Prototype (the five substitutions, the `inputs.tsv` row, the issue's files copied in): `./zn check c0269` gives 4/4. `narrow.py` prints `5f4bdbc4…` and `fbda5f28…`, which match E2.
- Promotion simulated (acceptance files copied to `z-nile/tests/acceptance/c0269/`), then `z-nile/check.sh --affected` exits 1 at **format (stylua --check)** (F1). After a scratch `stylua` of the two `titles.spec` copies, the same gate exits 0: 736 passed in 102 z-nile spec files, plus the other homes green.

### F1 [high] The sequestered `titles.spec.luau` is not stylua-formatted, so the prep commit and every gate after it fail the format stage
Where: `acceptance/titles.spec.luau:60-61`; E2 ("`stylua` on the specs"); Implementation step 3.
Evidence: `stylua --check z-nile/.tracker/issues/c0269/acceptance/titles.spec.luau` in the worktree exits 1, wanting lines 60 and 61 (the two long `t.expect(has(d, 'it("…"')).toBe(true)` lines) split before `.toBe(true)`. On the scratch promoted tree, `z-nile/check.sh --affected` stops with `== format (stylua --check) (2.9s, FAILED)` and names both copies: `z-nile/tests/acceptance/c0269/titles.spec.luau` and `z-nile/.tracker/issues/c0269/acceptance/titles.spec.luau`. The gate's `stylua --check "${LUAU_DIRS[@]}"` covers the tracker folders. E2 ran stylua only on the two edited specs and ran titles.spec through `tests/run`, which never checks formatting. promote-check doesn't either.
Critique: the prep PR is red as soon as it is pushed. The executor may not edit a sequestered spec, so after the prep lands nobody can turn the raft's gate green without a re-prep.
Consequences: reformatting moves the spec's line numbers. Nothing pins them: no row cites a titles.spec line, and the `line 213` row is done-gate's own line, which doesn't move.
Recommendation: run `stylua` on `acceptance/titles.spec.luau` and commit it formatted. Rerun E2 with the formatted file: `./zn check c0269` and `z-nile/check.sh --affected` on the prototype with the spec promoted, and record that the format stage passed. Add "`stylua --check` of every acceptance file" to the step that closes the prep.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F2 [high] The hand-off to c0241 hands over the wrong digest, and the order it depends on is written only in c0269
Where: Design "The pin on the files" ("prints the SHA-256 of each file … for the Verification log: c0241 needs them"); Existing work, c0180 ("c0241 takes the digest of the file after this chore (the Verification log records it), so this chore lands before c0241's re-prep is executed"); Implementation step 6; `narrow.py:4-5,23-26,39`; c0241.md frontmatter `depends_on: []`.
Evidence:
1. **The wrong quantity.** c0180's `narrowings.luau:4-5` says ``digest` is the sha256 of the *narrowed* file``. `narrowed.spec.luau:29-33` hashes the file that holds c0180's own `new` text. `narrow.py` hashes the file c0269 delivers, before c0180's narrowing. I measured both on the scratch tree with a Lune probe that applies c0180's `old`→`new` from `narrowings.luau` and hashes it the way `narrowed.spec` does:
   - main today: c0180's narrowed digest is `fa862628`, against the pinned `f3a3b469` (stale already, as the design says);
   - after the five substitutions: `narrow.py` prints `5f4bdbc4`, but the value c0180's `narrowings.luau` must hold is `bc5d901c`.

   The Verification log would record a number that c0241 cannot use. c0180 doesn't pin `c0080/consequences.spec` at all (`git grep -n consequences z-nile/.tracker/issues/c0180/acceptance` finds nothing), so the second printed digest has no reader. The normalisers also differ: `narrow.py` masks `(?<![A-Za-z0-9_])[fdcR]\d+(?![A-Za-z0-9_])`, while `narrowed.spec` masks `[cdfR]%d%d%d%d` with no word boundary. They agree on this file today, but not in general.
2. **The order is not where c0241's author reads it.** `grep -n 'c0269' z-nile/.tracker/issues/c0241/c0241.md z-nile/.tracker/issues/c0180/c0180.md` finds nothing. c0241 has `depends_on: []`, and c0180 has `depends_on: [c0165]`. Nothing stops c0241 from re-prepping c0180 against today's file before c0269 lands. c0269 would then silently stale c0180's sequestered digest: `narrow.py` watches only `*/tests/acceptance/`, never another item's `acceptance/` folder. If c0180 then lands first, its promoted `narrowed.spec` pins done-gate.spec, c0269's rename turns it red, and c0269's AC4 forbids touching it, so c0269 can no longer be executed.
Critique: the captured outcome "carry with c0241's requote of the c0074/done-gate digest" (R0086 review 001 F2: "it should ride with the next chore that already overrides it") rests entirely on this hand-off. As designed, the hand-off has no criterion and delivers the wrong value. The fix the author will be tempted to make is to print the right digest instead.
Consequences: a digest c0269 prints is "what the spec prints now", which zz-test/narrowing-pins-the-whole-file (Also, c0118 design review 012 F1) forbids as a pinned value. c0241 must compute its digest from c0180's reviewed narrowing applied to main's file at c0241's own execution. So the useful hand-off is the order, not a number. An edge c0241 → c0269 makes c0241's `ready` wait for c0269's `done`. That costs nothing: c0241 is a draft, and c0269 is a small chore.
Recommendation:
1. Stop printing the digests for c0241. Make `narrow.py` print nothing on success, or only `ok`, and drop Implementation step 6 and the "c0241 needs them" sentences. The other option is to print the value computed exactly as `narrowed.spec` does (c0180's narrowing applied, the Luau mask) and say plainly that c0241 must recompute it.
2. In this prep commit, add `c0269` to c0241's `depends_on`. Add a dated line to c0241's Problem: "c0269 renames four lines of `c0074/done-gate.spec`; c0180's `narrowings.luau` digest for that file is computed after c0269 is done". Add a matching line to c0180's Existing work.
3. Pin the edge with a check.sh-only line: AC5, "c0241's `depends_on` names c0269", read through `./zn find c0241`. It is a claim about today's tree, so not a spec (zz-review/recommendations-pick-spec-or-check).
4. Add a refusal: when c0180's `narrowings.luau` digest for done-gate already equals the post-rename narrowed digest, or c0180 is done, AC4 names the conflict and exits red, so an execution after c0241 escalates instead of passing. If the author reads "carry with" as "in the same raft" rather than "before", that reading is the user's to confirm (`Decided with the user`).
Lesson: z-design/pins-name-who-reprep-goes-first; z-ticket/carry-the-plan-order-into-depends-on; zz-test/narrowing-pins-the-whole-file

### F3 [medium] AC4 is red by construction in a shared raft, and the fixed rafting policy folds chores together
Where: Design "The pin on the files" ("fails when any other file under any `*/tests/acceptance/` differs from `origin/main`"); `narrow.py:41-45`; Existing work, c0123 ("a different set of lines; a text merge").
Evidence: z-raft's policy says "defects fold into one open prepared defect raft (the lowest id that still fits), and chores fold the same way". Today's `./zn raft-plan` prints `./zn fold R0077 c0123`, `./zn fold R0072 c0189` and `./zn fold R0069 c0247`. c0269 will be folded into one of these z-nile chore rafts. R0077's members change promoted specs: c0160 (Overrides `c0120/checkpaths.luau`, `c0120/rewrites.luau`) and c0123 (Overrides `c0008/done-order`, `c0058/fence`, `c0058/lock`, `c0074/done-gate`, …). In the scratch prototype I committed c0123's `prototype.patch` hunks for `c0074/done-gate.spec.luau` and `c0058/fence.spec.luau` on top of c0269. `narrow.py` then exits 1 with `c0074/done-gate.spec.luau: differs from the base with its named substitutions applied` and `promoted specs changed: z-nile/tests/acceptance/c0058/fence.spec.luau`. "A text merge" holds only when the two land one after the other, not when they share a raft. Today the lowest open chore raft (R0069: c0112, c0247, both `Overrides: none`) would be harmless. That changes as soon as R0069 is readied.
Critique: a raft holding c0269 and any item with Overrides cannot pass `./zn done`, and nothing in the design or the frontmatter keeps them apart.
Consequences: `solo: true` keeps it apart mechanically, but per the policy a solo flag "records a user decision". Dropping the "no other promoted spec" clause leaves the per-file pin, which still fails beside c0123, c0180 or c0179: all three edit `c0074/done-gate.spec` (c0179's inventory lists both files among its codemod's 124).
Recommendation: escalate to the user. The options:
- (a) `solo: true`: c0269 is a raft by itself. This costs one extra small raft and needs the user's decision line.
- (b) drop the whole-branch `promoted_unchanged` clause, keeping the per-file pin (code review's sequestration diff and each raftmate's own pins cover the other files). Add a Design line naming c0123, c0179 and c0180 as items c0269 must not share a raft with, and make the check's refusal say "c0269 shares a raft with an item that changes these files: split the raft". This needs no user decision, but it relies on z-raft reading the line.

Whichever is chosen, add the "raftmate with an Override" mutant to Rules and mutants (run, red with the message above).
Lesson: z-design/dependent-specs-sequence-the-preps

### F4 [medium] The `inputs.tsv` change is not pinned: an executor who rewrites other rows passes all four checks
Where: Design ("adds one line to `z-nile/tests/inputs.tsv`"); Checklist "No behaviour change"; `titles.spec.luau:104-107`; Rules and mutants (no row for "inputs.tsv gains exactly one row").
Evidence: on the scratch prototype I deleted every `tests/acceptance/c0034/` and `c0042/` row (`1 file changed, 20 deletions(-)`) and committed. `./zn check c0269` still gave 4/4 PASS. `titles.spec` checks only that its own row is present, and `narrow.py` never reads `inputs.tsv`. Those rows keep the affected selector running `c0034/locator` and `c0042/cli` when tracker folders change. Dropping them is a silent selection regression, and nothing else pins most rows (`git grep -n 'inputs.tsv' -- 'z-nile/tests/**/*.luau'` shows only c0165/docs AC10 and c0239/docs pinning their own rows).
Critique: the design says the change is exactly one line, but no check enforces it. It is the same gap AC4 closes for the two specs.
Consequences: an exact pin must tolerate main adding rows during the raft. Comparing against the merge base, as `narrow.py` already does, handles that.
Recommendation: extend `narrow.py`. `inputs.tsv` on HEAD must equal its merge-base text with exactly the one line `tests/acceptance/c0269/titles.spec.luau\tz-nile/tests/` added (any position, and say whether order matters), and nothing removed or changed. Add the "a row deleted" mutant to Rules and mutants (run).
Lesson: zz-test/narrowing-pins-the-whole-file

### F5 [medium] The promoted `titles.spec` pins today's exact case titles of another item's spec forever
Where: `titles.spec.luau:56-63` ("AC1: the five new texts stand"); Test plan row AC1; Design "The pin on the words".
Evidence: after `done`, `z-nile/tests/acceptance/c0269/titles.spec.luau` runs in every gate whose change set touches `z-nile/tests/`, because of its own `inputs.tsv` folder row. It asserts byte-exact titles such as `it("the gate decision: affected, unless inside a spec run without the switch"`. Any later reword of those titles or of the c0080 comment, even one that keeps the rule, turns the gate red and must name `c0269/titles.spec` as an Override. Two in-flight items already restructure this file: c0180 moves the doneGate assertions to `cmd/done.luau`, and c0179 runs its codemod over it. At `done`, `narrow.py` already proves these texts byte for byte, so the promoted case adds no done-time strength, only future friction. The lasting rule here is the absence of the stale phrases (AC2's scan), which belongs in a spec.
Critique: this is the "rule, not today's text" split. Exact text is a check.sh claim; the rule the change restores is the spec's job.
Consequences: AC1 moves to a check.sh-only line, for example a `grep -cF` per new text, or a check-only Luau script in `acceptance/` not named `.spec.luau`, run only by `check.sh`. The promoted spec keeps the AC2 cases: the scan, the planted forms and the `inputs.tsv` row. The old-texts-gone case is already covered by the scan.
Recommendation: make AC1 check.sh-only as above, keep AC2 in the promoted spec, and update the Test plan and the check labels to match.
Lesson: zz-test/promoted-specs-pin-rules-not-sets; zz-review/recommendations-pick-spec-or-check

### F6 [low] `narrow.py` is red after the landing and blind to line endings, and the design states neither window
Where: Design "The pin on the files" ("byte for byte"); `narrow.py:29-39`.
Evidence:
- With `refs/remotes/origin/main` set to the prototype's HEAD (the landed state, where the merge base equals HEAD), `narrow.py` exits 1 with five `expected one … at the base, found 0` lines.
- A CRLF copy of `done-gate.spec.luau`, committed, passes `narrow.py` (exit 0, same `5f4bdbc4` digest). `Path.read_text()` and `subprocess.run(text=True)` both translate newlines, so the compare is not byte for byte. The gate's stylua stage would still catch the CRLF copy.
Critique: z-design/exact-checks-compare-against-the-merge-base asks what a merge-base check says after the branch lands. A finished `check.sh` is not rerun, so this is low, but the design should say it is done-time only, or handle the empty range.
Consequences: none beyond the text.
Recommendation: either make an empty range (merge base equal to HEAD, or every `new` already at the base) pass, checking only that no old text remains, or add a Design sentence that AC4 runs at `done` only and is red once landed. Read both sides as bytes (`read_bytes()`, `subprocess` without `text=True`), or drop "byte for byte".
Lesson: z-design/exact-checks-compare-against-the-merge-base

### F7 [low] E2's mutation script is not kept in the item, and the experiments don't say they ran bounded
Where: Unknowns & experiments, E2 ("The mutant script is the scratchpad's `mut269.sh` … `m4.py`").
Evidence: `ls z-nile/.tracker/issues/c0269` shows no `experiments/` folder. The scratchpad that held `mut269.sh` is the author's session's, so the seven `run` rows can't be re-run by a reviewer or the executor. E2 doesn't say the prototype and mutant runs went through `./zn run --time`.
Recommendation: commit `mut269.sh` and `m4.py` under `experiments/` and state that they run through `./zn run`. After F1's reformat, rerun them once and record the outcome.
Lesson: zz-test/pin-expected-text-not-documents

Not findings (checked):
- The scan is not vacuous: the `#files > 100` floor plus the four planted forms. It doesn't match itself: every phrase is built by concatenation, the promoted copy passes AC2, and `narrow.py` holds the literals but is not a `.spec.luau`.
- `git grep -n -i` of the stale phrases, their variants and comments wrapped across lines over every z-nile, pickman and arcade spec finds only the five places (E1 holds).
- c0178's sequestered pins don't name the renamed strings (`overrides.spec` checks clone and paths text), and neither does c0123's.
- c0083 already contradicts c0239, as the design says.
- c0174 pins only c0083's files, and c0136 doesn't touch these files.
- c0179 rewrites folder lines of both files but pins no titles.
- `repo-fence.spec:237` and `c0114/classified:129` don't depend on the titles.

Verdict: changes
