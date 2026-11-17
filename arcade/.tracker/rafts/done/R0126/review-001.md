# Review 001: R0126 (code mode)
Inputs: d895e7321f2d18883847e4e33a2fcb61fef360eb (branch R0126/1/c0397, layer 1), `git diff origin/main...HEAD` after `./zn sync --fetch` (origin/main 897e97f27); c0397.md, its check.sh, acceptance/narrow.py, experiments/ (prototype.patch, mutants.out); R0126.md and its check.sh.

No findings.

What was checked:
- **Scope of the diff**: six files. Two are the Overrides' promoted specs (`arcade/tests/acceptance/f0201/config.spec.luau`, `receipts.spec.luau`); the rest are tracker records (c0397's Verification log line, `results.txt`, a spend.d row, the raft's `spend.md`). No file under `arcade/src`, no other spec, no `check.sh`, no script and no guard changes.
- **Exactly the Design's patch**: the base blobs on origin/main are f0201's prepared `f09b9d38` and `d298dee9`; HEAD's are the reviewed `4d20b213` and `3e9e5007` that narrow.py pins. The diff's +/- lines are identical to `experiments/prototype.patch` (sha256 2dff2b13…368b, as the Design names). Both files stay plain ASCII with LF endings.
- **What the narrowed cases still pin** (Design, Per case): case 1 pins struck, price and sale one by one with `toBe`, and still pins the charge and frozen. Case 2 pins a play's line count (3), its title line and the note last. It keeps the revive title assertion word for word and adds the revive's count and note last (C9, C10). The second line is no longer pinned there. Case 3 compares `{ "open", PaidPlay.testLines("INVADERS", "revive", Prices) }` and keeps the `ask` answer, no prompt, one message to that player, the folder and the remote. The window's gaps (W1, W2) and C16's survival on f0201 alone are the capture's choice and are recorded in the Design. The case titles are unchanged, so f0395's Overrides line still names them.
- **Sequestration**: the three-dot `--name-status` diff over every `.tracker/**/check.sh` and `.tracker/**/acceptance/**` lists nothing. narrow.py's sha256 is 65f66165…9217, as `check.sh` pins.
- **Runs**: `./zn check c0397` passes 2/2. AC1's printed base is `https://github.com/philipbergen/pickman.git refs/heads/main`, the project's repository. `bash arcade/.tracker/rafts/active/R0126/check.sh` passes 3/3 (affected gate, c0397's checks, promote-check). `z-nile/check.sh --affected` reports GATE PASSED: config.spec 10 passed, receipts.spec 30 passed, 0 failed.
- **Repository safety**: the changed specs are Luau cases on the stub engine and pure Logic, with no file, process or git access. The sequestered narrow.py, unchanged here, only reads (`git ls-remote`, `cat-file`, `merge-base`, `ls-tree`, file reads). Every item on the "Caught only by review" list is clear: no process is handed out, no model CLI starts, no `PICKMAN_*` variable is set, and the printed origin URL is correct.
- **Bounded commands**: the diff adds no script, loop or background process. The author's Verification log reports only the gate, `./zn check` and `git apply`.
- **Lessons** (`./zn lessons narrow override promoted`): zz-test/narrowing-pins-the-whole-file and zz-test/narrowing-keeps-each-members-check are met (whole-file byte pin; revive count and note added). z-design/finished-overrides-land-before-ready is also met, since f0201's `check.sh` is unchanged. No lesson's defect repeats here.

## Judged criteria (code mode only)
None: c0397 has no Judged criteria.

Verdict: approve
