# Review 006: R0043 (design mode)
Inputs: origin/prep-z-nile-home at 1760273. This round covers only the delta of the user's 2026-10-21 decisions, `git diff 8ff448b..1760273` (c0114.md, R0043.md, c0114's check.sh, and acceptance `finished.luau`, `finished.spec.luau`, `rewrites.luau`, plus edits to docs, guards, layout, publish-roots, registry, roots-cli and window specs). I checked against the prototype branch `proto2-c0114` (365c548), using a scratch clone with no remote and `origin/main` set by `update-ref` to its merge base with origin/main. I also ran `scripts/tracker.sh capture c0114` and `scripts/tracker.sh lessons --when design --full`.
Dropped from design-review-005: none open (F1 and F2 were low and were answered at round 5).

Checked and sound:
- **G2.** The prototype's `.claude/settings.json` diff adds exactly the seven `./zn` entries beside the seven `scripts/tracker.sh` ones and changes nothing else. docs.spec pins the pairing and the hooks.
- **G3.**
  - `zn` exports `ZN_TOP` and `ZN_CWD`, and the engine's `hereDir` trusts `ZN_CWD` only when `pwd -P == ZN_TOP`. A fixture that inherits the variables therefore reads as its own root.
  - `new issue` and `new raft` refuse at the root and outside every project folder.
  - make-issue step 2, the lesson-capture lines and the tracker skill's Projects bullet all name `--project`, and say that pickman work needs `--project pickman` until c0120.
  - Nothing in the hooks or the workflows captures an item.
  - R89 to R95 and R99 cover the rules.
- **G4.**
  - `publish.commit` refuses on an origin with no registry, so nothing is pushed.
  - `engine.copy` carries the registry, since it isn't in `engine.STATE`. `engine.empty` works on a clone that holds the registry, and hand-built trees use `engine.registry`.
  - R96 to R98 cover the rules. I found no fail-open path in the publisher.
- **G5.** The rewrites happen in step 7a, an edits commit, so JC1 holds. finished.luau holds unfinished items to their base text byte for byte, and finished items to `rewrites.expected`.
  - I ran four rewritten finished checks by hand on the prototype clone. c0044 (special) passed 11/11, c0035 7/7, c0070 5/5, and c0007 (special) 3/3.
- **Repository safety (item 9).**
  - finished.luau runs only `git ls-files`, `git show` and `git merge-base`, plus fs reads.
  - finished.spec and `engine.registry` read the real tree but never write to it.
  - No guard is weakened.
- **Scope (item 11).** The capture is unmarked and unchanged. The delta adds only `Decided with the user` lines and the detail behind them.

### F1 [high] The promoted `finished.spec` goes red at c0114's own `done`, and again at every later `done` of a raft whose check.sh names a forwarded path
Where: `tracker/issues/c0114/acceptance/finished.spec.luau`, case "every finished item's check.sh and acceptance file is already rewritten"; c0114 §3 (G5)
Evidence:
- `done` promotes the whole `acceptance/` folder into `tests/acceptance/c0114/` and moves the items to `done/`. It then runs `z-nile/check.sh --full` on that tree (`cmd.done`).
- The case walks every `done/` check.sh in both roots and does not leave out c0114 or R0043. finished.luau does leave them out.
- c0114's own check.sh sources `.../scripts/lib/ac.sh`, and R0043's runs `scripts/check.sh --full` and `scripts/tracker.sh members`. `rewrites.paths` changes both texts (I ran it).
- I reproduced the failure on the prototype clone: I placed c0114's check.sh under `z-nile/.tracker/issues/done/c0114/` and ran the spec. Result: `FAIL ... z-nile/.tracker/issues/done/c0114/check.sh still names a moved path`.
- So `done R0043` fails its full gate and rolls back.
- The same failure hits every later raft whose sequestered check.sh sources `scripts/lib/ac.sh`: R0034 (active), R0012, R0035, R0041, R0040, R0030 and R0039.
  - Each one's `done` moves an unrewritten check.sh into `done/`. Its full gate turns red on a chore's promoted spec, which a feature raft can't override.
  - `done` only applies `paths.rewrite` for its own `done/` dirs (c0067), not `rewrites.paths`.
- Raft R0034 can finish inside c0114's execution window. The same drift then hits finished.luau when the branch merges main: R0034 is `done` at HEAD with its base text, not `rewrites.expected`.
  - Step 9 doesn't say to re-apply the rewrite to items that finished in the window.
  - `rewrites.SPECIAL` sits in a sequestered file, so the executor can't add an entry if such an item needs one.
Critique: the invariant "every finished check.sh is rewritten" is stated for all time, but only this PR enforces it. The tempting fix is to exclude c0114 and R0043 in the spec, as finished.luau does. That fixes c0114's own `done` and leaves every later `done` broken.
Consequences: the invariant needs an owner after c0114. One option is to scope it to the items finished when c0114 lands. Then a check.sh finished later still names `scripts/...` and relies on the forwarders, which the forwarder-removal raft already has to handle. The other option is to make it hold for the future. Then `done` must apply the move rewrite when it moves a check.sh into `done/`, which extends the user's sequestration exception to every future finish. That is the user's call, not the reviewer's.
Recommendation: escalate to the user, with these options:
- (a) Scope the promoted case to c0114's landing.
  - It checks the files finished at the merge base plus c0114 and R0043, with c0114 and R0043 left out as in finished.luau.
  - Step 9 re-applies `rewrites.paths` to any item that finished on main during the window.
  - The forwarder-removal raft's prep lists later finishes alongside the unfinished check.sh files.
- (b) Make the invariant permanent. `done` applies the move rewrite (a copy of `rewrites.SCRIPTS` and `TRACKER` in the engine) to each check.sh it moves into `done/`. This is a new exception to sequestration for every future `done`.
- (c) Don't promote the "already rewritten" case: keep it in check.sh only, as finished.luau is.

Under every option:
- Add a case that runs on a fixture where a raft whose check.sh sources `scripts/lib/ac.sh` goes through `done`. Assert that the promoted spec stays green.
- Add a mutant that drops the exclusion.
- State what step 9 does for items that finish in the window.
- (a) and (c) need no further user decision; (b) does.
Lesson: testing/no-live-counts-in-promoted-specs (the same failure: a promoted spec over the live tracker goes red in an unrelated raft's `done`). Candidate generalisation for the lead: "a promoted spec that reads the live tracker must stay green when any other raft finishes; check: which later `done` changes the set it walks?"

### F2 [medium] §5 and §11 still say the branch's engine reserves ids on origin's `tracker/next`, which G4 made impossible
Where: c0114 §5 (bullet "the base has no `z-nile/projects.toml` ... The branch's engine reserves there (new issue, emergent issue, new raft, renumber, remap)"); §11, The execution window (first sub-bullet: "every new issue, emergent issue, `new raft` and renumber raises it there")
Evidence:
- G4, §2 and R0043's Risks now say that while origin has no registry, `publish.commit` refuses and pushes nothing ("publish from the main checkout until it does"). window.spec pins "in the window the branch publishes nothing".
- The two sentences above still describe the pre-G4 behaviour, in which the branch numbered on `tracker/next`.
- `publish.counterOf`'s "no registry" case can no longer be reached by a publish.
Critique: an executor who reads §5 or §11 expects `./zn new issue --raft R0043` or `renumber` to work from the branch, and gets a refusal at a stop point.
- Renumber is the sharpest case: Phase 6 step 2 says "renumber colliding IDs" after merging main. Renumber reserves on origin, and it rewrites branch files, so it can't simply be run from the main checkout instead.
Consequences: the design must say how a collision is resolved in the window. One answer: none can arise, because the branch makes no ids, and every capture comes from the main checkout and arrives through the merge. If that is the claim, state it and pin it.
Recommendation:
- Rewrite §5 bullet 2 and §11 bullet 1 to match G4. In the window the branch's engine reserves nothing. Captures, emergent issues (`--raft R0043`, filed in `tracker/` by the old engine and moved in step 9) and claims come from the main checkout.
- Say why the branch never needs `renumber`, or how to handle one if it does.
- Mark `counterOf`'s no-registry case as local-only (audit and offline numbering), or remove it.

### F3 [medium] The code-mode sequestration check will flag the 122 rewritten finished check.sh files as high, and the design doesn't tell the reviewer or the executor that they are the user's exception
Where: review skill Code mode item 2; execute-raft Phase 4 step 4; testing skill; c0114 §3 and §10 ("the sequestration check" bullet only widens the globs); R0043.md
Evidence:
- The skills' check `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' ... '*/.tracker/**/check.sh' ...` must list "nothing except `R100` renames"; "any other change is high".
- With G5, each rewritten `done/` check.sh shows up as a non-R100 pair.
- §10 updates only the check's globs. R0043.md mentions AC14 but doesn't tell the code reviewer to read the sequestration output against finished.luau.
Critique: the clean code reviewer has no shared context, follows the skill, and files a high finding. A code-mode Recommendation can't edit sequestered files, so the executor must escalate a question the user has already answered. That is a guaranteed wasted round.
Consequences: the exception has to be stated where the reviewer reads, and stated narrowly, so it doesn't become a general licence to edit `done/` files.
Recommendation:
- Put a sentence in R0043.md (and so in the prompt) and in c0114's Implementation steps, with these parts:
  - For this PR only, the sequestration check's non-R100 lines must be exactly `done/` check.sh files.
  - AC14's `finished.luau` is the check that they differ only by `rewrites.expected`.
  - Every non-R100 line outside `done/` is still high.
- Optionally give the exact command: the check with `':(exclude)*/done/*'`, and finished.luau for the rest.

### F4 [low] `audit.scan`, `claims.taken`, `publish.allowed`, `trail` and `history` still default to the legacy root, against "Nothing falls back to the old single root any more"
Where: c0114 §2 (G4), §7 last bullet; prototype `z-nile/engine/audit.luau:36-40` (`rootsOf` returns `{ projects.LEGACY }` when `load` raises), `claims.luau:16`, `publish.luau:103`, `trail.luau:42`, `history.luau:144`
Evidence:
- audit's `rootsOf` is what `localIds` (offline numbering), `list` and `remap` scan. Reading it, `remap` in a tree with no registry would scan `tracker/` alone with no refusal; I didn't run that.
- Every caller I checked passes roots explicitly (claims at main.luau:518), so I found no fail-open path today.
Critique: a future caller that omits `roots` silently gets the single legacy root. That is the exact behaviour the user removed.
Consequences: removing the defaults touches the "old callers" that `history.LOG_ARGS` keeps.
Recommendation:
- Either make `roots` required (or have them raise without it) except where §6 explicitly keeps history's old callers, or state the remaining defaults as a listed exception in §2.
- Add a case where `remap` or `list` in a tree with no registry refuses.

### F5 [low] Stale guess marker and a new pending guess
Where: c0114 §7 jail-waiver bullet ("**Guess (pending user, 2026-10-20):**"), although G6 was accepted; §2 and "Decisions on the guesses" ("`list` at the checkout's root lists every project").
Critique:
- The §7 marker contradicts the decision recorded at the top of the document.
- The `list` guess sits close to the user's words "at root without project=fail". It is correctly marked as pending, but it must be put to the user before readying, with the cost of each reading:
  - list at the root: skills and step 9 run `./zn list` there;
  - refuse at the root: one line in `listedRoot`, plus the doc and spec edits that go with it.
Recommendation: turn the §7 marker into the 2026-10-21 decision, and ask the user about `list` before ready-raft.

### F6 [low] c0069 AC6 is a finished check that c0114 newly breaks, recorded but not resolved
Where: Verification log, "fails because of c0114: c0069 AC6"
Critique: G5's stated purpose is that finished checks "pass again when run by hand". The one failure that c0114 causes is listed but neither fixed nor accepted by the user.
Recommendation: either add a `rewrites.SPECIAL` entry or an override of c0053's replacement copy, or record c0069 AC6 as a known failure the user accepts, next to G5.

Verdict: changes
