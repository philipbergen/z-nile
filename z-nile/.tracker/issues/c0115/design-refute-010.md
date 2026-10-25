# Refute 010: c0115 (design mode)
Answers `design-review-010.md`. The prototype is `proto-c0115` at the rebase's tip on 757a5fa1; every experiment ran in a scratchpad clone.

- F1: fixed. `rewrite-finished --check` is three-way against `git merge-base HEAD origin/main`; `MARK` and `premove()` are gone.
  - A file at the base must be its base text rewritten by the four rules, less `DELETED` (an id with no statement at the base stays absent). A file not at the base only has to need no rewrite. An empty range checks only that nothing needs a rewrite.
  - No `origin/main` or no merge-base is red, and so is a non-empty range that compares no file with its base. That last is new (lesson testing/no-vacuous-pass): on the prototype's real remote, `origin/main` predates c0114 and c0120, so AC14 is red there until they land, as AC12 is.
  - Steps 5, 5c and 10 rerun 5c after every merge of `origin/main`, as its own commit.
  - The reviewer's simulation is `experiments/rewrite-finished-sim.sh`, run in a scratchpad clone with `origin/main` at the c0120-done base, and every case ends as it should:
    - the branch alone: green;
    - main edits c0004 and R0025 after the move, merged: green;
    - c0199 finishes on main with an old path, merged: red, then green after rerunning 5c as its own commit;
    - the branch deletes RC3 too: red;
    - c0040 left unrewritten: red;
    - landed (squashed), then main edits c0007: green;
    - no `origin/main`: red.
  - Lesson: ticket-prep/exact-checks-compare-against-the-merge-base (new), and design-the-execution-window.
- F2: fixed under G13's decision ("carry"). Rule 3 now matches any assigned value ending in `.claude/skills`, then a quote, a space or the line's end. It carries c0040 AC1 and AC2 (both pass, on the base and on the prototype).
  - `--check` gained an independent old-path scan: any finished `check.sh` still naming `.claude/skills/<old>` or `/<old>/SKILL.md` is red. Before the widened rule it found c0040 only.
  - The base-against-prototype comparison now covers every finished `check.sh` that names `.claude/skills` or an old skill (37 files, base found by `git grep` at the base). No criterion is red on the prototype that is green on the base. Nothing new to delete.
  - Mutants M68 (c0040's `$R/zz-execute/` back to the old name) and the sim's unrewritten c0040: red.
  - Lesson: ticket-prep/new-rules-migrate-existing-work, a note added.
- F3: fixed. Rule 1b rewrites a bare `<up>.claude/skills` operand to every real skills folder from the home (`skills ../pickman/skills` from `z-nile/`). Six files: c0005, c0046, c0067, c0070, c0071 and R0013.
  - A planted phrase turns c0071 AC2, c0070 AC5, R0013 RC2 (planted in `pickman-arch`) and c0046 AC6 (in `pickman-test`) newly red.
  - c0005 AC5's and c0067 AC10's operands find the planted phrase (2 hits against 1 clean, 0 through the old operand). Both criteria are red on the base and the prototype alike, because the real scan now sees a lesson phrase (`zz-arch/lessons/guards-trust-only-origin.md`) the vacuous one hid on the prototype; the base, whose `.claude/skills` were real folders, was already red.
  - M69 (c0071's operand left on the links): red.
  - Lesson: testing/no-vacuous-pass, a note added.
- F4: fixed. AC14 says "the six `DELETED` criteria (G12, G13) and nothing else". §8 opens with "four rules", and the script's header lists all four.

Mutants M62 to M69 against `--check`, in a clone whose `origin/main` is the base: all killed. In the prototype worktree itself, M64 to M66 survive only because the real `origin/main` has no finished file at the base, which `--check` now reports as red.
