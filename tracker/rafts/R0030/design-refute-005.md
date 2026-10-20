# Refute 005: R0030 (answers to design-review-005)

Round 5 is the final round, and its F1 is high, so by the ticket-prep skill this round went to the user. The user chose option B on 2026-10-20 and approved a sixth round (design-review-006).

- F1: fixed (option B, the user's choice). The finding is correct. Four promoted specs read the real tracker tree without naming the changed item's path: c0034 `locator`, c0044 `guard`, c0063 `narrowed` and c0103 `narrowed`. The item-folder rule (refute-004) drops them for changes inside item folders, and the sequestered AC2 case hard-codes the reader list, so the list can't be completed during execution. The three options were measured on the prototype on 2026-10-20.
  - **A. Complete the list.** The list grows to six readers and is exported as `suites.TRACKER_TREE_READERS`. The AC2 case takes its allowance from the exported list and asserts the six by name. A raft-shaped change selects about 78 specs.
    - The reviewer's completeness scan is not precise on this tree. A scan for bare `"tracker…"` literals and `` `{root}/tracker…` `` pieces finds about 20 fixture specs that use `"tracker"` only as a git argument inside a fixture (c0067 `ready`, c0068 `stop`, c0072 `land`, c0081 `allocate`, `ready-members`, `start-pr-reuse`, …), as well as the six real readers.
    - So a completeness case needs a reviewed exclusion list. Every new fixture spec that writes `git add tracker` would turn the promoted c0083 spec red until it is listed.
    - This is still a hand-kept list. The fourth hole in four rounds suggests the list is the weak part.
  - **B. Keep `check.sh` and `acceptance/**` on the plain rule** (review 004's original recommendation). Only the other files in an item folder use the narrow rule: documents, `spend.md`, reviews, experiments. The list then covers only specs that read item *documents* of the real tree: c0082 `real-tree` (and `repo-fence`, harmlessly). The readers of `check.sh` and acceptance specs (c0034, c0044, c0063, c0103, `repo-fence`) are selected through the tokens they already name.
    - Measured: the Game init plus a raft's `spend.md`, review and issue document selects 74 specs, and one issue document selects 2. The Game init plus `done`'s move of the raft (documents, `check.sh` and acceptance spec) selects 134, and that includes c0034, c0044 and c0063. A prep's new `check.sh` plus acceptance spec plus document selects 60.
    - The cost: about 60 harness specs (around 58 s) run once at `done` and on prep gates. They no longer run on every raft commit's spend or review.
    - It needs one AC2 case rewrite, the reverse of refute-004's change. It adds no list that must be complete.
  - **C. Treat a change to a tracker item's `check.sh` or acceptance spec as `HARNESS`** (the whole harness suite). This is a product call on "what is harness". It runs 145 specs on every prep and `done`, and it is the most robust option.
  - Author's recommendation: B. It removes the completeness problem for the readers that review 005 found, because they name the tokens. It keeps the saving where the changes are frequent: spend rows, reviews and Verification logs on every commit. It leaves exactly one listed reader, whose job (auditing item documents) is narrow and named. The noise moves to once per raft (`done`) and to preps.
  - Consequences of B, to apply if the user picks it:
    - the AC2 case drops `done/f9999/check.sh` and `acceptance/x.spec.luau` from the "nothing else" list and asserts c0034 and c0044 for them;
    - the Rules row's mutant becomes "check.sh under the narrow rule";
    - Scalability and E2 are re-measured;
    - the testing skill's Suites sentence names documents, not every file;
    - one more design round with a new reviewer.

Applied (option B):
- An item's `check.sh` and acceptance specs keep the plain rule. Only the other files in an item folder use the narrow rule.
- `TRACKER_TREE_READERS` holds only c0082's `real-tree`.
- The AC2 case is renamed "a tracker item's documents select only the specs that name them, plus the real-tree audit". It asserts the narrow selection for documents, and that a done `check.sh` still selects c0034's `locator`, c0063's and c0103's `narrowed` and `repo-fence`, while an acceptance spec still selects c0044's `guard`.
- Rules rows, AC2, Scalability, Usability, E2, the Suites sentence and R0030's Theme (which quotes the decision) are updated.

On the prototype c0083 passes 9/9. Nine option-B mutants were run and every one failed its case: P1–P9 in `experiments/mutants.log`.

Consequences:
- A prep that writes a `check.sh` or acceptance spec, and `done`'s move, select about 60 harness specs (about 58 s), once per raft.
- Commits that change only spend, reviews or documents select only `real-tree` beyond their own code.
- `repo-fence` left the list; the plain rule selects it for `check.sh` files.
