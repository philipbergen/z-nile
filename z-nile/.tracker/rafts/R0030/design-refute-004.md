# Refute 004: R0030 (answers to design-review-004)

- F1: fixed. The mechanism changed for tracker item folders; no case was added on top of the old rule.
  - A path inside a tracker item folder (`^tracker/(issues|rafts)/(active/|done/)?[fdcR]NNNN/`, every file in it, `check.sh` and `acceptance/` included) is matched only by a token equal to it, or by a folder at or below its item folder. A folder above the item folder never matches (`tracker`, `tracker/issues`, `tracker/issues/done`). Every other path keeps the plain rule, including `tracker/game-design.md`, `tracker/next` and `tracker/templates/`. This differs from the review's recommendation, which kept `check.sh` and `acceptance/**` on the plain rule: `done` moves every file in the member folders, so that would bring the 60-spec noise back on every raft's `done` gate. The two real readers of those files are covered by F2's list.
  - Measured on the prototype:
    - the Game init plus a raft's `spend.md`, a review, an issue document and `done`'s moved `check.sh` and acceptance spec: 74 specs (the Game init's 72 plus the two readers), was 132;
    - one issue document: 2, was 60;
    - `done`'s whole move of R0030 and c0083: 2.
  - The new AC2 case "a tracker item's own files select only the specs that name them, plus the tree readers" pins that union. It checks every graph hit of the Game init and both readers, nothing beyond the Game init's own selection and the readers, and none of c0072 `land`, c0084 `spend-command` and c0067 `ready`. It also checks that one issue document selects both readers and not pellets, that a done `check.sh` still selects `repo-fence`, and that `tracker/game-design.md` still selects f0054's docs spec.
  - Mutants run and killed: item documents matching tokens above the item folder; the rule for issues only; the rule skipping `done/`.
  - Consequences:
    - Specs that name `tracker/issues/done` or `tracker/issues` (c0042 and c0082 `cli`, c0044 `naming`, c0081 `allocate`) no longer run for an item change. They test fixture trees, not the real one.
    - A spec that reads a real item by its exact path, or by a folder at or below the item folder, still runs.
    - The Stop hook in a prep or capture session now gates on 2 specs, not 60.
    - Not a product change: tracker documents stay unexpanded (not `HARNESS`), as before.
- F2: fixed. `TRACKER_TREE_READERS` in `scripts/lib/suites.luau` lists `tests/acceptance/c0082/real-tree.spec.luau` and `tests/tooling/repo-fence.spec.luau`. `repo-fence` is on it too, because without the list it ran for a done `check.sh` only through the `tracker` token, which the mutant "no tree readers" showed. `textAffected` includes both whenever any changed path is under `tracker/issues/` or `tracker/rafts/`, whatever their text says.
  - The case asserts the rule, not today's title: with the item-folder rule, the title word `tracker` no longer matches an item path, so the mutant "real-tree selected only by text" fails it. So do "no tree readers" and "readers only for a `check.sh`".
  - The testing skill's Suites paragraph names the list and says that a new spec of that kind joins it. AC7 checks the token, and the mutant "paragraph without the list" fails AC7.
  - Consequences: the list has an owner (the testing skill), and its two entries exist (the case's `exists` calls). A spec that walks the real tree and isn't on the list is caught only by CI's `--full`, as a selector miss handled forward.

After the fixes, on the prototype, c0083 passes 9/9 and `scripts/check.sh --full` passes (1821 cases). The whole mutation record (82 mutants) is in `tracker/issues/c0083/experiments/mutants.log`. Its first-round count was miscounted as 54 in the documents; it is 65, plus M21c.
