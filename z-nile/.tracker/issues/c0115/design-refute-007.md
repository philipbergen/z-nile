# Refute 007: c0115 (design mode)
Answers `design-review-007.md` (the focused review of the user-decision delta). The base is unchanged: bc550e9.

- F1: fixed: AC14 now fails closed and no longer depends on the working directory.
  - `backlog_clean` runs `lune run z-nile/roots` from `$ZN_ROOT` and anchors every `find` there. It returns 1 when the roots command fails or prints nothing, and when no unfinished item's document was read. It prints its count: 27 on the prototype, from the root and from `z-nile/`.
  - The rename script anchors every path at `git rev-parse --show-toplevel` and exits 1 on a failed or empty roots command.
  - §11 (l) names AC14.
  - M57 (`backlog_clean`'s roots command failing, on a copy) and M58 (the script's roots command failing): run, both red.
  - Consequences: the floor "more than zero documents" holds while any item is unfinished (c0113 is, until c0115's `done`), and it fails closed when that stops being true, which a later raft's override can lift.
- F2: fixed: c0113's AC2 runs `git -C "$ZN_ROOT" ls-files --error-unmatch -- .claude/README.md`, and AC1 finds c0115's promoted specs at `$ZN_ROOT/tests/acceptance/c0115` or `$ZN_ROOT/z-nile/tests/acceptance/c0115`, after its sequestered folder. With `.claude/README.md` restored on the prototype, AC2 is red. §11 (l) names c0113's `check.sh`.
- F3: fixed:
  - c0113 is `design: ready`, and its Design records that design review 007 covered its superseded Design and `check.sh`, and that the next round covers them again.
  - §9 gains "The raft": the raft is formed holding c0115 and c0113, and Implementation step 1 checks it.
  - AC15 (`raft_holds_c0113`) reads c0115's `raft:` and `./zn members`, and fails while there is no raft or the raft lacks c0113. On the prototype it is red for the right reason: no raft is formed yet.
- F4: fixed: `engine.COPIED_SKILLS = { "z-nile/skills" }` in `tests/lib/engine.luau` is the one list of copied skills folders. `engine.clearLessons` and the G7 case both walk it. With a game lesson planted in `pickman/skills/pickman-arch/lessons/` on the prototype, the case stays green. A Rules row is added.
- F5: fixed: programme-review F5's answer now states the user's G4, and points at §8 and AC14.
- F6: fixed: step 5b reads pass 3's diff line by line and rewords half-renamed sentences by hand in documents only, never in sequestered files, and lists them in the PR description. On the prototype that is four sentences in `c0083.md` and one in `R0040.md`. c0083's sequestered `check.sh` keeps one message ("tracker or AGENTS.md…"), listed in §8.
- F7: fixed:
  - `backlog_clean` also matches `/<old>` (the command form) and `/<old>/SKILL.md` for every old name, literal or built from a variable. A planted `/launch-raft R0010` is red.
  - The script's gate for a sequestered file now also takes a `/<old>/SKILL.md` path, aligning the two.
  - §8 and step 5b say that a sequestered file AC14 flags beyond the script's gate is escalated to the user under the G4 exception, never edited by hand.
- F8: fixed: JC2 checks each README sentence against zz-rules, zz-test, z-run and zz-execute.

The gate passes on bc550e9 (228.0 s at load average 22). Its first run this round failed the lint stage on a selene warning: my own lint runs had filtered warnings out (harvested as a note on ticket-prep/rerun-skipped-checks-after-edits).
