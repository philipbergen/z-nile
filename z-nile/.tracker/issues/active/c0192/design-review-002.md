# Review 002: c0192 (design mode)
Inputs: worktree `prep-lesson-bound-every-probe` at a6aabd18 plus the uncommitted `c0192.md`, `check.sh`, `harvest.md`, `design-refute-001.md` and `experiments/` (`ref-lesson.md.txt`, `ref-lesson-c0181-first.md.txt`, `ref-meta-spec.luau.txt`); c0191 at `origin/prep-no-leaked-processes` 88168bf6 (`c0191.md`, `acceptance/docs.spec.luau`, `experiments/ref-boundcmd.luau.txt`, `ref-bounded.pl.txt`, `ref-reap.luau.txt`, `ref-pre-bash.sh.txt`, `ref-docs-draft.diff.txt`); c0181 at `origin/prep-lessons-codify-consolidate` 70fa9f21 (`c0181.md`, `experiments/E1-similar.luau`); c0136 (`c0136.md`, `experiments/prototype.patch`), c0112 and c0193 at `origin/main` 896526de; c0166 at `origin/prep-relevant-review-lessons`; `./zn capture c0192`; `./zn lessons --skill zz-review --full`, `--when design --full`.
Dropped from design-review-001: F1, F2, F3, F4, F5, F6 (each fix re-run below; F3's fix is right for the note but opens F1 here).

Re-run evidence, in a throwaway clone of this worktree under the scratchpad (deleted afterwards):
- `./zn check c0192` in the real worktree: **0 of 5**, for the right reasons (no lesson file; "AGENTS.md carries no bounded-command rule (c0191 not landed?)"; no Enforced by line; "not listed for --when design"; "no meta spec").
- In the clone, with c0191's `ref-boundcmd.luau.txt` as `z-nile/engine/boundcmd.luau`, `ref-bounded.pl.txt`, `ref-reap.luau.txt`, `ref-pre-bash.sh.txt` at their Design paths, a stand-in `z-nile/tests/acceptance/c0191/docs.spec.luau`, AGENTS.md with the **Processes:** sentence from `ref-docs-draft.diff.txt`, `ref-lesson.md.txt`, `ref-meta-spec.luau.txt` and the note ending `(erred zz-review)`: `./zn check c0192` **5 of 5**. `lune run tests/run -- tests/meta/bound-every-probe.spec.luau` passes (0.1 s). Without `ctx`, `boundcmd.check` says `./zn run --time 60 -- lune run probe.luau` (`CTX.zn` defaults to `"./zn"`), so the `say` assertion holds.
- The gate's static checks the design did not record: `luau-lsp analyze --base-luaurc=.luaurc --platform=standard` on the meta spec gives no errors, `selene --quiet` 0 errors, and `stylua --check` is clean. `tests/meta/architecture.spec` and `tests/tooling/repo-fence.spec` name nothing of c0192's. Their two failures in the clone come from my stand-ins (a non-strict docs stand-in; c0191's `reap.luau` needs c0191's own repo-fence allowance diff).
- `tests/acceptance/c0120/check-paths.spec` on the round-2 `check.sh`: 4 passed. I also ran `finished.spec` with the item moved to `done/`, but it was stopped at my 240 s limit while another session's suite loaded the machine, so it decides nothing. The new AC5 paths use the same `"$ZN_ROOT/…"` and `skills/…` forms that E6 passed.
- c0181's similarity rule (`E1-similar.luau`) over the clone's 163 lessons: the new lesson is in no same-skill pair at 0.24 or above, so there is no hard pair (0.35) in the c0181-first order.
- c0166 (`design: ready`) switches the readers to `--for <id> --mode …`. It keeps `zz-review` as an exercised skill in all four modes, and its tag table takes every tag already on the tree. All four of the lesson's tags are on main today (`process` 9, `review` 12, `experiments` 4, `probes` 1). So Decision 2 still holds once c0166 lands, and `--check` raises no `unlisted tag`.

### F1 [medium] When c0136 has landed first (always true in the c0181-first order), AC4 fails on the item's own harvest entries, and no step tells the executor to group them
Where: Design 8 ("so it is green whether c0136 has landed or not (review 001 F3)"); check.sh AC4 (`if grep -q unattributed …; then "$Z" lessons --unattributed c0192 || exit 1; fi`); Implementation step 4 (it adds only the note line); Non-goals/Design 7 (the c0181-first branch); Chore checklist, Existing work (c0136).
Evidence: c0136 defines `lessons.unattributed` as "`<item> <review> <finding>` or `<item> note <text>`, for every entry with no `erred`". Its E5 lists every legacy entry, and c0112's E1 says "`--unattributed` lists all 1071". c0192's `harvest.md` has six ungrouped finding entries (`- design-review-001 F1: z-design/quote-other-preps-before-promising` … F6), and round 2's entries will be the same.

Run in the clone: I applied the engine part of c0136's `experiments/prototype.patch` (`git apply --include='z-nile/engine/*'`, which puts `unattributed` in `lessons.luau`, so AC4's branch fires). Then:
- `./zn lessons --unattributed c0192` prints `c0192 design-review-001 F1` to `F6` and exits 1.
- `./zn check c0192` gives **4 of 5**: `FAIL AC4` with those six lines. The reference texts are all in place and the note is grouped.
- Rewriting the six lines as `- design-review-001 F<n> (erred z-design): …` gives `lessons: 163 lessons, 1158 harvest entries, ok`, `harvest: every entry names its step`, and exit 0.

c0181 has `depends_on: [c0136]`, so the c0181-first branch (Design 7, E7) always runs with c0136 present. E7's c0181-first simulation added only the `enforced_by` marker, so it never met this.
Critique: the design states a landing-order claim that one of the orders breaks. This is the same class of defect as round 1's F1, now on the c0136 axis. An executor who follows steps 1 to 5 exactly gets a red AC4 and has to work out the cause from c0136's skills. The tempting fix is to drop `--unattributed` from AC4. That would hide an outcome c0136 makes required: c0136's z-design 5.5 and zz-execute Phase 5 run it, and c0112 makes it a gate invariant.
Consequences: grouping binds lesson filing. Under c0136 rule 2, each lesson an entry names must be filed under its `erred` or `upstream` skill. All of round 1's lessons are `z-design`, so `(erred z-design)` is valid (run above). A later round whose finding names lessons of two skills needs `(erred X, upstream Y)`. A finding that names three skills needs c0112's note form. Rule 3 applies to any review written after c0136 that carries `Erred:`/`Upstream:` lines: its entry must copy them.
Recommendation:
- In step 4, add: "if `z-nile/engine/lessons.luau` has `unattributed` (c0136 landed), give every entry of `harvest.md` its step group, `- <review> F<n> (erred <skill>[, upstream <skill>]): <ids>` (each lesson named filed under one of them; a review with `Erred:` lines is copied), and run `./zn lessons --unattributed c0192` before `./zn check c0192`."
- Correct Design 8 so it says the note is green either way and the finding entries need groups once c0136 exists.
- Add to Existing work that the c0181-first order implies c0136-first.
- Add a Rules-and-mutants row: "c0136-first: every harvest entry names its step | AC4 | an ungrouped `design-review-001` entry | run (c0136's prototype.patch, engine only)".
Lesson: z-design/quote-other-preps-before-promising

### F2 [low] Text that round 1's change made stale: "no test changes", "no new rule a gate enforces", "one 13-line file", the c0180 example and the type pass
Where:
- Chore checklist, No behaviour change: "one markdown file in a lessons folder … Nothing under `pickman/`, `z-nile/engine/`, `scripts/` or any test changes".
- Existing work: "The lesson makes no new rule that a gate enforces, so nothing existing fails on the day it lands".
- Scalability: "One 13-line file".
- Design 6: "a moved `reap.luau`, e.g. into `engine/cmd/` if c0180 lands".
- Regression guard: "lune's type pass is the gate's".

Evidence:
- Round 1's fix added `z-nile/tests/meta/bound-every-probe.spec.luau`, a new test that every gate runs. It enforces a rule in every gate: AGENTS.md's sentence is in the lesson, and every path on the Enforced by line exists.
- c0191 says it is the `reap` *command* that becomes `z-nile/engine/cmd/reap.luau` if c0180 lands first ("`reap` is `z-nile/engine/cmd/reap.luau` like the other commands"). The pure `z-nile/engine/reap.luau` that the lesson names stays where it is.
- The gate's type stage is `luau-lsp analyze` (`z-nile/check.sh:173`), not Lune. The design never ran it. I did: clean (Inputs).

Critique: the claims are harmless today, but a reader who checks the Existing work against the meta case finds a contradiction (z-design/restated-rules-move-together, second clause: sweep the earlier design's text after a change).
Recommendation:
- Say "one lesson and one meta spec (about 55 lines, 0.1 s in every gate)".
- Say the meta case is a new gate rule that reads only this lesson, AGENTS.md and the named files, so nothing existing fails on the day it lands.
- Drop or correct the c0180 example.
- Record the `luau-lsp analyze`, `selene` and `stylua` runs in E7.
Lesson: z-design/restated-rules-move-together

Verdict: changes
