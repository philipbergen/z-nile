# Review 007: R0043 (code mode)
Inputs: `impl-r43` at b8de795 (PR #98 head, draft, base `main`); main's tip from `git ls-remote https://github.com/philipbergen/pickman.git refs/heads/main` is 841b88f, and the branch holds it (merge-base = 841b88f). Fix delta: `064196a..b8de795`, plus d1d6764 (the review-006 fix, which landed after review-006 was written and just before 064196a added it). Also read: review-006, refute-006, the PR #98 description, c0114.md (step 9, JC1, the 2026-10-23 decision), R0043.md, and `./zn lessons --when build --full`.
Dropped from review-006: none. F1 and F2 are fixed as refute-006 says (checked below).

What I ran and checked:
- `z-nile/check.sh --full`: GATE PASSED (full). 2256 passed, 0 failed, 331 spec files, 81.1 s. Lint: 0 errors, 0 warnings, 0 parse errors. No repository tripwire fired in any run.
- c0114's `check.sh`: 16/16. R0043's `check.sh` (`./zn check R0043`): 5/5.
- `finished.luau`: `184 sequestered files, 140 finished ones rewritten, 0 wrong`, with base = merge-base(HEAD, ls-remote tip) = 841b88f.
- `./zn audit`: 0 errors, 1 warning (`counter-unmigrated tracker/next`, expected).
- Sequestration, three-dot against the ls-remote tip, over both roots' `check.sh` and `acceptance/**`:
  - With `':(exclude)*/done/*'`: 41 `R100`, the 2 template `D`s accepted in earlier rounds, and exactly 02ba5ab's three files as `D`/`A` pairs (`acceptance/finished.luau`, `acceptance/finished.spec.luau`, `check.sh`). Nothing else.
  - `git log origin/main..HEAD` on c0114's sequestered paths: only 93e7ce1 (renames) and 02ba5ab.
  - `done/` side: 77 `A`, 77 `D`, 63 `M`, all proven by `finished.luau`.
- 02ba5ab, the user-approved edit: `finished.luau` reads main's tip with `git ls-remote origin refs/heads/main`, requires it to be a local commit, and takes the merge base with HEAD. It refuses when the tip can't be read, isn't fetched, or shares no history with HEAD. The new `finished.spec` case covers all four (a forged local `origin/main` stays red, plus three refusals) in a `.cache/c0114-finished-tip` fixture with a local bare origin. Its pushes go only to that fixture. fcef378 records the decision in c0114.md (with the Rules row R116) and in R0043.md.
- Step 9:
  - 948f87b rewrites 10 files, and 6c7a3f0 (earlier) rewrote R0034 and f0065. Every one of the 12 `done/` `check.sh` files missing from `rewrites.FINISHED` (c0129, f0065, f0100–f0102, f0104, R0034, R0035, R0046, c0127, c0131, R0047) is rewritten. `finished.luau` proves each one differs only by `rewrites.expected`. All 140 `done/` `check.sh` files on the branch are rewritten.
  - 25fbc63 is 2 one-line lesson path fixes.
  - 642f046 and ee07c04 are the overrides: c0127/reuse, c0131/accept and c0131/refuse, plus tests/tooling/lock-start-ids. They are path-only, recorded in c0114's Overrides (64), and green in the gate.
- Finished checks run by hand:
  - f0100: 6/6.
  - R0047: 4/4 (gate, c0127, c0131, promote-check).
  - R0035: 8/9. RC3 ("no promoted spec edited") fails because it diffs `tests/acceptance` against `merge-base origin/main HEAD`, and on this branch that shows c0114's own overrides. It passes on main once #98 lands, so this is not a rewrite defect.
- Merges in the delta:
  - 4f62b71 (R0043 readied) resolved two things by hand:
    - The rename/rename of c0114/R0043. It took main's `active/` path, which 93e7ce1 then moved. Contents are identical apart from `ready`'s status line.
    - A testing-skill conflict. It kept main's new lock text with `z-nile/lib/fence.sh`.
  - 1380fcb, 8b70fa2, 909105d and b8de795 have no hand-resolved file.
- d1d6764 (review-006 F1/F2):
  - The `raft-spans-projects` audit reads membership from both `issues:` and `raft:`, and exempts `done/`.
  - `audit-raft-roots.spec` has the four cases, in a `.cache` fixture with no git.
  - The offline hint says `./zn sync --fetch`.
- Classification of every unfinished item on main (and this branch):
  - Game items, in `tracker/`: f0109, f0110, f0125, f0126, c0128, d0124, R0044, R0045.
  - Tooling items, in `z-nile/.tracker/`: c0075, c0083, c0112, c0113, c0115–c0118, c0120–c0123, c0132, c0134–c0137, R0030, R0039, R0040, and c0114/R0043 (active).
  - Finished during the window: R0035 and R0046 (game) are in `tracker/…/done`. R0047, c0127 and c0131 (tooling) are in `z-nile/.tracker/…/done`.
  - c0133 is withdrawn on main (dbe8f8a), and c0130 was folded into R0035.
  - No unfinished raft spans roots (audit 0 errors).
- Simulated `./zn done R0043`, in a clone whose origin is a local bare copy of origin (main 841b88f, impl-r43 b8de795):
  - Real tree: refused at `reviewProblem` ("refute-006.md: F1/F2: a fixed answer needs '; consequences: …'"). That only applies while 006 is the latest round. An approving review-007 skips it (see F1).
  - With a stand-in approving review-007 committed in the sim, `done` passed:
    - check.sh 5/5;
    - promotion of all 14 c0114 acceptance files to `tests/acceptance/c0114/`;
    - full gate on the done tree: 2334 passed, 0 failed, 343 spec files, lint clean;
    - committed `tracker: done R0043`, pushed only to the local bare.
  - After it:
    - the promoted `classified`, `docs` and `finished` specs: 16/16 (slugs unique now c0133 is gone);
    - `./zn audit`: 0 errors;
    - the promoted `finished.luau` against `done/c0114`: 0 wrong;
    - c0114's done `check.sh` got its done-path rewrite.
  - `rewrites.FINISHED` holds the 128 prep-time files, as designed ("a fixed list"). The 12 that finished on main since then are covered by step 9's rewrites and `finished.luau`, so every finished `check.sh` is covered.
- Repository safety: the delta touches no guard file. The only new git-writing code is finished.spec's new case, and it is fenced into `.cache` with a local bare origin.
- Lessons (build): audit-what-new-refuses holds for the raft-root rule (see F3 for slugs). The fix-rounds rerun holds (16/16 and 5/5 after the last commit). grep-preps-for-removed-names: the overrides cover R0047's specs. no-vacuous-pass: `finished.luau` counts 184/140, not zero.

### F1 [low] refute-006's "fixed" answers don't carry the "; consequences:" form that `done` parses
Where: z-nile/.tracker/rafts/active/R0043/refute-006.md. `reviewProblem` in z-nile/engine/main.luau (around line 2645).
Evidence:
- F1's consequences sit on a separate sub-bullet, `  - consequences: …`.
- F2's answer has no consequences at all.
- With review-006 as the latest round, `./zn done R0043` fails with `F1: a fixed answer needs "; consequences: …"` (and the same for F2).
Critique: harmless now, because `done` reads only the latest round, and this round approves. But review-006/refute-006 stay in the record malformed, and the next refute in this raft would fail the same way.
Consequences: none (text only).
Recommendation: rewrite each line of refute-006 as `- Fn: fixed <sha>: …; consequences: …` on one line. F2's consequences are "the needle in window-new-raft.spec changed with it; window.spec's sequestered needle still matches".

### F2 [low] AC14's description in c0114.md and #98's Results are stale after 02ba5ab and the landing merges
Where:
- c0114.md line 195 ("compares … with its text at `git merge-base HEAD origin/main`").
- The PR #98 description:
  - "Sequestration in this PR": "only `R100`: 37 lines";
  - "Results (on f7144d6 / febae35)": "189 sequestered files, 128 finished ones rewritten".
Evidence:
- Since 02ba5ab, the base is the merge base with main's tip as `git ls-remote origin` reports it.
- The sequestration check now lists 41 `R100`, plus 02ba5ab's three pairs and the two templates.
- `finished.luau` reports 184/140.
Critique: the reviewer and user read the description to judge the exception. Stale numbers make a correct tree look as if it differs from what was claimed.
Consequences: none.
Recommendation: update line 195 to name the ls-remote base, as the 2026-10-23 paragraph above it does. Refresh the PR's Results and the sequestration line with this round's numbers (b8de795: 16/16, 5/5, 184/140, 41 `R100`, gate 2256/0).

### F3 [low] After landing, one duplicate-slug capture turns the promoted `classified.spec` red for every PR, and nothing reports it earlier
Where: c0114 acceptance/classified.spec.luau ("each slug seen once" over every item of a kind, done ones included). c0135 (`new issue` refuses a used slug), still `new`. z-nile/engine/audit.luau (no duplicate-slug rule).
Evidence:
- c0133 had the same slug as c0132, captured 10 s apart. It had to be withdrawn by hand so the promoted spec could pass.
- Once c0114 lands, a capture publishes straight to main with no gate. So a repeat of that capture turns `classified` red on main and on every branch that merges it, until someone renames the slug.
Critique: the spec is sequestered and the uniqueness rule is the user's (c0133 was withdrawn for it). So the gap is upstream: `new` still allows it until c0135 is done, and `audit` never reports it. This repeats the lesson's shape: a promoted case that walks a live set of items which other work changes.
Consequences: an audit error for duplicate slugs would also fire on any existing duplicate. There is none today, because the simulated promotion is green.
Recommendation: the lead adds to c0135 (an edit on main, or a capture) an `audit` error `slug-duplicate <kind> <slug>: <id>, <id>` beside the `new` refusal. That follows tracker/audit-what-new-refuses. Order c0135 soon after the landing.
Lesson: testing/no-live-counts-in-promoted-specs

## Judged criteria (code mode only)
- JC1: pass.
  - The PR description lists all six `c0114: move` commits. Under `git show -M --find-renames=100% --name-status`, each one is only `R100`: 9e178c4 703, 54f0226 8, 93e7ce1 45, ead1bb1 26, d693b30 7, a4b811b 3.
  - Every other non-merge PR commit shows only `A`/`M`. In the delta, 948f87b, 25fbc63, 642f046, ee07c04, 02ba5ab and fcef378 are all `M`.
  - The merges move nothing of the PR's own. 4f62b71's rename/rename resolution takes main's `ready` move (`tracker/…/active/`), and 93e7ce1 lists the follow-up move to `z-nile/.tracker/…/active/`.

Verdict: approve
