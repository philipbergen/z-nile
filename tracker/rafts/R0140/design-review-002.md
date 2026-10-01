# Review 002: R0140 (design mode)
Inputs: prep worktree HEAD aa06e7c plus the uncommitted prep files: tracker/rafts/R0140/{R0140.md,check.sh,design-review-001.md,design-refute-001.md}, tracker/issues/c0450/{c0450.md,check.sh,acceptance/override-check.spec.luau}, tracker/issues/c0460/{c0460.md,check.sh,acceptance/*.spec.luau}; origin/main b6e3e59 (R0130) for drift. I ran `tracker.sh check c0450` (2/5, the expected failures), `tracker.sh check c0460` (3/7, the expected failures) and `promote-check R0140` (OK). In scratch copies I built the c0450 text and the c0460 `setup.sh` stage from the Design and ran the specs: override-check plus c0410 gave 19/19, setup-skip-gate gave 6/6, and all of `tests/acceptance` plus `tests/tooling` with the new template gave 413/413. I also ran my own mutants and replayed `start` on a b6e3e59 tree.
Dropped from design-review-001: F2, F3, F4, F5, F6, F7. The fixes hold. I accept the F5 correction: a workflow-level concurrency group is evaluated when the run is queued, before job `if` conditions, so a global group would let a skipped branch dispatch cancel the `main` run, and the per-ref group plus the main-only job `if` is right. F6 also holds: the visible placeholder renders through `tracker.sh new` (`{{…}}` substitution only), the board and `metrics` build, and `c0410/table.spec` stays green. F1 was only partly fixed and comes back as F2.

### F1 [high] Both issue `check.sh` files use the locator that main's promoted c0330 spec forbids, so the gate turns red at `tracker.sh start`
Where: tracker/issues/c0450/check.sh:5 and tracker/issues/c0460/check.sh:5 (`source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"`). The prep branch is based on aa06e7c, and origin/main is b6e3e59.
Evidence: R0130 (b6e3e59) promoted `tests/acceptance/c0330/locator.spec.luau`. Its case "no live check.sh or the template uses the locator that needs acceptance/ to exist" scans every `check.sh` under `tracker/issues/{active,done}` and `tracker/rafts/{active,done}` for the text `"$A/.."`. R0130 also changed the issue template and the testing skill to the `HERE=… pwd -P` locator with the fallback `[[ -d $A ]] || A="$PWD/tests/acceptance/<id>"` ("Must run after promotion"). I extracted b6e3e59 to scratch, put c0450 and c0460 in `tracker/issues/active/` (what `start` does) and ran the spec. Result: `FAIL … tracker/issues/active/c0450/check.sh finds the repo through "$A/..", which fails once acceptance/ is promoted away`, 7 passed and 1 failed. The prep PR still merges green, because backlog is not scanned. But Phase 0 `start` puts the items in `active/`, after which `scripts/check.sh --full`, AC5/AC7 and RC0 are red. The executor can't touch sequestered `check.sh` files, so it must stop and escalate. After `done`, the same files would also fail the case "every finished item's check.sh finds the repo".
Critique: The raft can't be delivered as written. This is also exactly the residual that c0450 describes: a promoted spec that walks directories (`fs.readDir("tracker/…")`), which neither the grep nor the selector finds. Neither Regression guard lists it. The tempting fix is to edit the two `source` lines by hand.
Consequences: Without merging main first, a hand edit can still drift from the current template and testing skill (the `pwd -P` physical path, and the promoted-path fallback that `done` relies on). The design also needs a check that the scripts work in their post-promotion location, not just before it.
Recommendation:
- Merge origin/main into the prep worktree.
- Regenerate both `check.sh` headers from the current `tracker/templates/issue/check.sh`, with the `HERE`/`pwd -P` locator and the fallback to `tests/acceptance/c0450` or `c0460`, keeping the `check` lines unchanged.
- Rerun `tracker.sh check c0450` and `c0460`. Expect the same pass/fail split as now.
- Rerun `promote-check R0140`.
- Run `tests/acceptance/c0330/locator.spec.luau` with the items copied into `active/` and `done/` in a scratch tree, and check that `AC_LIST=1 bash tracker/issues/c0460/check.sh` lists 7 criteria.
- Add `tests/acceptance/c0330/locator.spec.luau` as "at risk" to both Regression guards.
- In c0450 Design, give it as the worked example of the directory-walk residual. The folder skim should name specs that walk `tracker/`, such as c0330, c0400, c0420 and c0430.

### F2 [high] (repeat of design-review-001 F1) setup-skip-gate still passes a stage that swallows the gate's failure or drops `--full`
Where: tracker/issues/c0460/acceptance/setup-skip-gate.spec.luau:35-47 (the stub always exits 0 and ignores its arguments), :73-81; c0460 Rules and mutants.
Evidence: I built the stage from the Design in a scratch copy, which passed 6/6. Each of the following mutants of `scripts/setup.sh` also passed 6/6:
- `scripts/check.sh --full || true`. Round 1 named this mutant, and the refute didn't address it.
- `scripts/check.sh` without `--full`. In `check.sh` that defaults to `--affected`, so CI on `main` runs no specs.
- `scripts/check.sh --full &`.
- `PICKMAN_SKIP_GATE=${PICKMAN_SKIP_GATE:-${CI:-}}` near the top.
- `[[ -z ${PICKMAN_SKIP_GATE:-} ]] && [[ -n ${CI:-} ]] && exit 0` before the stage.

The first three keep `check.yml` green when the gate fails or doesn't run. The last two skip the gate on every CI run. The promoted c0010 spec already treats `|| true` as worth a check for `check.yml` itself.
Critique: The spec runs the guard but not the gate's contract: that the gate is called with `--full`, and that its failure propagates. The tempting fix is to grep the block for `|| true`. That misses `; true`, `&` and `if !`.
Consequences: A behavioural fix needs two stub modes: success, and a failure with a known exit code. The "outside the stage" assertions have to cover the variable and early exits, not only `scripts/check.sh`. `setup.sh` today has exactly one `exit`, the one in `die()`, so a rule about `exit` is cheap to pin.
Recommendation:
- Make the stub `printf 'GATE-RAN %s\n' "$*"; exit "${STUB_RC:-0}"`.
- In the unset and empty cases, assert the exact line `GATE-RAN --full`.
- Add a case with the variable unset and `STUB_RC=3`: the stage must exit non-zero (`ok == false`).
- Add a case: every line of `setup.sh` that mentions `PICKMAN_SKIP_GATE` lies inside the stage.
- Add a case: the only `exit` in `setup.sh` is inside the `die()` definition.
- Add Rules and mutants rows for `|| true`, a missing `--full`, `&`, the default taken from `CI`, and an early `exit`, and run them on the prototype.

### F3 [medium] The Override check never says what to do when the selector prints `ALL`
Where: c0450 Solution bullet 1 ("read every promoted spec either lists"), Design "Where the text goes" (names `ALL` as a token only); review item 4 (no `ALL`).
Evidence: Any `scripts/` or config path prints `ALL`. c0460's own `scripts/setup.sh` does (verified). Read literally, the step then makes the author read every promoted spec, 56 files in this tree. The author of c0460 instead used the grep result alone, but no text says that is allowed. My prototype bullet said only "`ALL` means a full run", and it passed `override-check.spec`, so neither the meaning nor the rule is pinned.
Critique: An agent new to the repo must invent the rule, and the reviewer can't check it mechanically. That defeats the claim that "unnamed override is a mechanical finding". The tempting fix is to add the word `ALL` to more places.
Consequences: Whatever the rule, the review has to apply it the same way. If `ALL` defers to the grep, then for `scripts/` changes the grep plus the folder skim is the whole list, and the full gate is only a late backstop.
Recommendation: Write the sentence into the c0450 Design and the bullet: "`ALL` names no particular spec: the selector can't narrow this path, so the grep result plus the folder skim is the list". Add the `ALL` token to review item 4 in the Design and the spec, with a mutant row (the sentence removed from item 4).

### F4 [medium] The "chore in `done/` before `start`" rule lives where the executor reads it only after `start`
Where: c0450 Solution bullet 1 and Design ("the issue's raft document must say, under Order & dependencies…"); execute-raft Phase 0 (step 2 runs `start`, step 3 reads the raft document); make-prompt step 2 (readiness has no dependency check).
Evidence: `tracker.sh start` ignores `depends_on` from outside the raft (`workstreamPlan` drops non-members, main.luau:478), and the board only displays it. The sentence is also inlined into the prompt, but the protocol reads the raft document after the `start` it is meant to gate, and no readiness step looks at it. The executor finds out the way c0450 says it shouldn't: a red `--full` mid-raft once S still pins X. The Solution doesn't say that the issue's frontmatter gets `depends_on: [<chore>]`. Only a Rules row ("a chore the issue depends on") and the token imply it.
Critique: The prep-time rule has no enforcement point before the work starts. The tempting fix is to add a tracker code check to `start`. That is out of scope here, and the refute rightly leaves it to the user.
Consequences: A skill-level check is enough and is generic: any cross-raft `depends_on` should block a prompt. That also covers non-override dependencies. It touches `.claude/skills/make-prompt/SKILL.md`, and the grep check shows no promoted spec reads that file.
Recommendation:
- State explicitly that the issue sets `depends_on: [<chore id>]`, so the board shows the raft as Waiting.
- Add a make-prompt "Check readiness" bullet: every `depends_on` id of a member that is outside the raft is in `done/` (`scripts/tracker.sh find <id>`), otherwise stop.
- Add `.claude/skills/make-prompt/SKILL.md` to c0450's Touched modules.
- Add a spec case pinning `depends_on` and `done/` in make-prompt step 2, with a mutant row.

### F5 [medium] The documented download command collides with the local board's default output path
Where: c0460 Design "Docs" (`gh run download -n tracker-board -D .cache`), OC1; the tracker skill's `board` row (default `.cache/board.html`).
Evidence: `tracker.sh board` writes `.cache/board.html` by default (main.luau:1058), and the artifact holds `board.html` at its root, so the documented command extracts to the same file. gh 2.83's extractor opens each file with `O_CREATE|O_EXCL` (`pkg/cmd/run/download/zip.go`), so it fails with "file exists" for anyone who has run `board` locally and on every second download. I could not run a download here (the attempt was blocked), so this is reasoned, not run.
Critique: The doc row and OC1 would fail on the developer machine where they're used, and OC1 says to file a chore when that happens. The tempting fix is `-D .cache/ci-board`, which still fails on the second download.
Consequences: The command needs a fresh or emptied directory each time. OC1 and the doc row must use the same command.
Recommendation: Add E6 (pass/fail: does a second `gh run download` into the same directory succeed?) and run it once on any repo's artifact. Document `rm -rf .cache/ci-board && gh run download -n tracker-board -D .cache/ci-board` (or the variant E6 proves), use it in OC1, and add `-D .cache/ci-board` as a board-docs token with a mutant row.

### F6 [low] Stale sentence after the per-ref change
Where: c0460 Scalability ("`concurrency` bounds parallel runs to one").
Evidence: The group is now per ref, so it bounds runs to one per ref. Branch dispatches run in their own groups and are skipped.
Critique: It is a minor inaccuracy, but it is the reason a later reader would "fix" the group back to a global one.
Consequences: none.
Recommendation: Write "one run per ref; branch runs are skipped by the job `if`".

Verdict: changes
