# Review 005: R0026 (design mode)
Inputs: prep worktree `prep-guard-follow-ups` at 83e6f00 (`git diff HEAD~1 -- tracker/`): c0083 (`c0083.md`, `check.sh`, `acceptance/suites.spec.luau`), c0074 and c0080 where round 4 changed them, `R0026.md` and `check.sh`; design-review-004 and design-refute-004; the review, testing, tracker, ticket-prep and execute-raft skills; `.github/workflows/check.yml`; the other rafts' `check.sh` files. Prototype `.worktree/proto-r0260`: read `scripts/lib/suites.luau`, `scripts/affected.luau`, `scripts/lib/changed.luau`, `scripts/check.sh`, `scripts/hooks/stop.sh`. I ran `lune run scripts/affected -- <path>` (and `--deps`) for every tracked file outside `src/ tests/ scripts/ tracker/ .claude/` and the paths below, and ran `suites.spec.luau` once (11 passed, 0 failed). For one experiment I deleted `SETUP.md` and restored it (`cp -p` backup, `cmp` equal, `git status` clean afterwards).
Dropped from design-review-004: F1 (settled by the user's "Nowhere"), F2, F3, F5, F6, F7, F8 and F9 (the fixes hold; what they open is below). F4's text selection holds for files that exist, so F4 is dropped too; F1 below is the hole it leaves.

### F1 [high] Deleting or renaming a file that specs read as text selects none of its readers, so under "Nowhere" no local gate runs them (partial repeat of review-004 F4)
Where: c0083 Design, `suites.textAffected` ("a piece is kept only when it exists in the checkout"); prototype `scripts/lib/suites.luau`, `textRefs` / `exists`; `scripts/hooks/stop.sh`.
Evidence: `textRefs` keeps a spec's token only if `fs.isFile(p) or fs.isDir(p)` holds in the current tree. Once a change deletes the file, nothing names the changed path any more:
- `lune run scripts/affected -- SETUP.md` with the file present: 3 specs (c0003 `pipeline`, c0006 `clone`, c0015 `docs`).
- The same call with `SETUP.md` deleted: **0 specs**.

The same holds for every text-read file outside `SHARED`/`HARNESS`/`GAME`: `.github/workflows/check.yml` (3 readers), `tracker/architecture.md` (`tests/meta/architecture.spec`), `tracker/game-design.md` (f0054's docs spec), a renamed `tracker/**/check.sh`. A rename is the same case: `--no-renames` lists the old path, which no longer exists, and the new path, which no spec names. So `check.sh --affected` prints "no specs affected" and passes. The Stop hook gets an empty selection and exits 0 without gating. RC0 and `done`'s gate (both `--affected` now) pass too. Every one of those readers then fails on the final head. Before "Nowhere", RC0's `--full` caught this; now nothing local does (F2).
Critique: the tempting fix is to drop the existence filter. That lets any word in any string literal (`"ok"`, `"main"`) become a ref, which is harmless (over-selection), but it hides the real rule: a path counts if it existed on either side of the change.
Consequences: a token's existence then needs a second tree. In default mode (`changes.files`) that's the merge-base. In explicit mode (`affected -- <files>`, which the Stop hook uses) it's `HEAD`, which covers uncommitted deletions but not a deletion committed earlier on the branch. The Stop hook only passes uncommitted paths, so `HEAD` is enough there, and `check.sh --affected` uses default mode. The cost is one `git ls-tree -r --name-only <ref>` per selection, plus folder prefixes derived from it. The selector must still work with no git (a failing `ls-tree` falls back to the working tree only, which over-selects nothing and under-selects only deletions).
Recommendation: a token is a ref when it exists in the working tree **or** in `git ls-tree -r --name-only` of `HEAD` and, in default mode, of the merge-base (files and their parent folders). New `suites.spec` cases, in a `.cache/<unique>` fixture repo holding a reader spec and its target, committed as `@example.invalid`:
- the target deleted but uncommitted: `affected -- <target>` selects the reader;
- the target deleted and committed on a branch: default-mode `affected` (base = the fixture's `main`) selects the reader;
- the target renamed: the reader is selected.

Add a Rules row with the mutant "existence by working tree only", run on the prototype, and a Stop-hook case: a deletion-only turn gates.

### F2 [high] Under "Nowhere" the first run of both suites is CI's, and it comes after `done`, so every selector miss turns into a red merge on a finished PR: c0074's bug moved, not prevented
Where: c0083 Solution ("CI on GitHub keeps it"); design-refute-004 F1 ("c0074's original bug … is now prevented by c0083's text selection"); tracker skill, Merging 3 and 4; execute-raft Phase 3 step 2 and Phase 5; testing skill line 87 ("**Graph miss**: a spec fails under `--full` but wasn't selected").
Evidence:
- `.github/workflows/check.yml` runs `scripts/setup.sh`, which ends with `scripts/check.sh --full`, on `pull_request` (ready, not draft) and on pushes to `main`.
- `done` marks the PR ready. Merging condition 3 then requires the `gate` check green on the final sha.
- Condition 4: "a finished PR gets no unreviewed code changes". Post `BLOCKED:` and stop.

Before this raft, RC0, Phase 3's double-check, `done` (with c0074) and Merging 2 all ran `--full`, so a miss showed up before `done`. After it, every one of them runs the same `--affected` selection. They agree with each other by construction, so none of them can find a selector miss. CI is the first place a miss is seen, after `done`. That is exactly c0074's Problem ("R0021's `done` passed while the gate on its final head failed … a one-line fix had to land after `done`, unreviewed"). Text selection prevents only the misses where a spec names the path. F1 is one it doesn't, and the testing skill already expects others ("neither sees a spec that builds paths or walks a directory"). Separately, the Graph-miss rule now names a `--full` run that no step performs.
Critique: the tempting fix is to put `--full` back in one step, `done` or Phase 3. That overrides the user's decision.
Consequences: the decision leaves CI on `--full`, so moving *when* CI's result is consulted doesn't re-open it. `scripts/ci-verify.sh` already dispatches the CI gate on a draft head; the tracker skill uses it.
- It needs `HEAD == origin/<branch>`, so push first.
- It costs one CI run per raft, plus one more if Phase 5's merge of `origin/main` brings changes.
- It runs Linux, unjailed, so platform differences show up earlier, which is a gain.
- It doesn't run `beta`, which is fine.
- It doesn't see `done`'s promotion. That's the one window left, and `done`'s own gate covers it by selecting the promoted specs and the scanners.

Recommendation: execute-raft Phase 3 step 2's "double-check" becomes: push, run `scripts/ci-verify.sh`, and wait for its `gate` SUCCESS on that sha before Phase 4. Phase 5 step 2 does it again if the merge of `origin/main` changed anything. A CI failure that `--affected` didn't select is a Graph miss: rewrite testing skill line 87 to say so (and file the chore as today). Extend c0083's AC8 (or AC7) to grep execute-raft Phase 3 for `ci-verify`, and the testing skill's Graph-miss line for "CI". Say in the raft's binding decisions that this follows from "Nowhere" (CI's `--full` is consulted before `done`, not only at merge). If the author reads that as a both-suites gate, it's a question for the user, not a reason to leave the hole.

### F3 [medium] The baseline steps become no-ops under `--affected`, and the design never says what replaces them
Where: c0083 Design, "Nowhere: the gate steps" (lists Phase 3, the post-merge rerun, review step 1, the template, the prompt); execute-raft Phase 0 step 1 ("Confirm `scripts/check.sh --full` passes here. **If main is red, stop.**"); tracker skill, Landing a change step 0 (after `sync`) and Merging 4 ("rerun `check.sh --full`"); Merging 2; execute-raft Phase 6 step 1; tracker skill line 41 ("`tracker.sh check` runs … for a raft, the full gate"); prompt template line 27; testing skill lines 12, 87 and 103.
Evidence:
- On a fresh raft worktree (branched from `origin/main`, nothing changed), `changes.files` is empty. So `check.sh --affected` runs the static stages, prints "no specs affected", and passes. Phase 0's "if main is red, stop" can no longer fire.
- A spec that is red on `main` then shows up mid-raft, the first time the raft's selection includes it. The executor can't tell it from its own breakage, and the skill forbids fixing main inside the raft.
- The design's list misses Phase 0, Phase 6, Landing step 0, and Merging 2 and 4. AC8's grep will force the executor to edit them, but only by swapping the token, which leaves the baseline step reading as a check it no longer is.
- Tracker skill line 41 says "the full gate" without the literal `check.sh --full`, so AC8 doesn't catch it, and it goes stale.

Recommendation: the design lists every step above with its new wording. Phase 0's baseline becomes: `main`'s latest CI `gate` run is green (`gh run list --workflow check --branch main -L 1 --json headSha,conclusion`), and, consistent with "Nowhere", `check.sh --suite <side>` for each side the raft's Touched modules select.
- Consequence: CI ignores `tracker/**` pushes, so the latest run's sha is often behind `origin/main`. Accept it when `git diff --name-only <sha> origin/main` lists only `tracker/` paths. Otherwise stop, as for red.
- AC8 adds: Phase 0 names the CI check, and no skill line says "full gate" as a step (a case-insensitive grep, excepting the testing skill's on-demand line).

### F4 [medium] Five design-ready rafts keep a sequestered RC0 `scripts/check.sh --full`, so "no gate runs both suites" isn't delivered for the next rafts, and one of them relies on that `--full`
Where: `tracker/rafts/R0018/check.sh`, `R0024/check.sh`, `R0025/check.sh` (line 6, all `design: ready`), `R0027/check.sh` on `origin/main` (12db1d5), plus drafts R0011 and R0012; c0083 AC8 (skills and templates only); R0025 design-review-002 (lines 17–18) and design-review-004 (line 39), which rely on RC0's or Merging 2's `--full` to run c0049's scan and repo-fence after promotion.
Evidence: the template change affects only rafts made after it, and AC8 greps only `.claude/skills` and `tracker/templates`. The next four rafts to execute run both suites at RC0 whatever they touch. R0025's reviewed protection against a scan-banned name in a promoted spec partly assumed Merging 2's `--full`. After c0083 that step runs `--affected`, so the protection rests on F1's and F2's mechanisms, and nobody told R0025.
Critique: the tempting fix is to sed the RC0 line in those files. They are reviewed, sequestered files owned by other preps, and R0025's design leaned on the old behaviour.
Recommendation: record a user decision in R0026's binding decisions: either (a) rafts prepped before c0083 keep RC0 `--full` until they are re-prepped, named as an exception in the testing skill's Suites part; or (b) each is re-prepped with an `--affected` RC0. Either way, add a line to R0025's document (or a note for its executor) that Merging 2 no longer runs both suites after c0083. R0026 doesn't edit those rafts itself.

### F5 [low] Stale "full gate" text contradicts the decision in the raft and in c0083
Where:
- R0026 Whole-raft design diagram (`gate.doneGate(process.env): full gate`).
- Risks ("`done` takes longer: it now runs the full gate twice … that is the bug c0074 fixes").
- Exit criteria ("RC0: the generated lines (the full gate, …)").
- R0026 `check.sh` header comment ("Runs the full repo gate").
- c0083 Problem ("`check.sh --full` (the Stop hook's and `done`'s gate)"): the hook never ran `--full`, which review-004 F2 asked to correct.

Recommendation: reword each to "the gate (`check.sh --affected`)". The Risks bullet should say what `done` now costs (one selected run after promotion, plus RC0's), and the Problem should say the hook ran `--affected`, only for `src/` and `tests/`. The `check.sh` comment is sequestered once the raft starts, so fix it in prep.

### F6 [low] The review skill's Override check is left conditional and unchecked, and the kept `ALL` sentence describes output `--deps` never prints
Where: c0083 Skills ("the review skill's design-mode item 4 if it names the selector"); review skill, Design mode item 4 (it does name it: "run `lune run scripts/affected -- <path>`"); ticket-prep line 37; AC7.
Evidence: AC7 checks ticket-prep only. Left as it is, a design reviewer still gets the whole harness suite (81 specs) for each `scripts/` path, which is review-004 F7 for reviewers. `--deps` never prints `ALL`: `--deps scripts/check.sh` prints 23 specs. So the sentence "Output `ALL` carries no list … use the grep alone", which c0083 keeps for c0047's pinned tokens, no longer matches the command it follows.
Recommendation: make the review-skill edit unconditional (item 4 uses `--deps`, like ticket-prep), and add it to AC7's greps. Reword the `ALL` sentence so it stays true and keeps c0047's tokens. For example: "`scripts/affected -- <path>` prints `ALL` for a shared path; `--deps` still lists that path's readers. Read them, and grep as well."

Verdict: changes
