# Review 001: R0087 (code mode)
Inputs: HEAD 35679e00 (branch R0087-rename-done-gate-spec-titles), origin/main 1758cf21 (fetched during the review; merge base 84ec653d), `git diff origin/main...HEAD` (6 files: the two promoted specs, `z-nile/tests/inputs.tsv`, c0269.md's verification log, two spend.md files), R0087.md, c0269.md, c0269 `check.sh`, `acceptance/titles.spec.luau`, `acceptance/narrow.py`, the raft's `check.sh`.

No findings.

## What was checked (each run in the R0087 worktree)
- **Design adherence.** The code diff is exactly the five substitutions in the Design's table (four in `c0074/done-gate.spec.luau`: lines 2, 115, 213, 231; one in `c0080/consequences.spec.luau`: line 4) plus the one `inputs.tsv` row `tests/acceptance/c0269/titles.spec.luau<TAB>z-nile/tests/`, appended. No assertion, case body or other line changed. The folder form (trailing `/`) matches the file's header grammar and existing rows (c0034, c0042). `stylua --check` of both specs: clean. There are no deviations and none were claimed.
- **Sequestration.** `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` printed nothing (the move to `active/` is already on main). `git diff --summary` showed only `create mode 100644 …/R0087/spend.md`, with no mode changes.
- **Checks are meaningful.** `./zn check c0269` failed AC4 at first with `origin's main 1758cf21 is not fetched: fetch origin main first`, because main moved while the gate ran. That is the documented red: it shows AC4 reads the published tip and not the local ref. After `git fetch origin main` it passed 5/5. AC1 pins the exact new and old texts. AC2 (`titles.spec`) tests `stale()` on planted title, comment, string, block-comment, backtick, capitalised, spaced and wrapped forms, and guards against a vacuous walk (`#files > 100`). It also leaves the surviving rule alone (`the merge's full gate`). AC4 pins both files byte for byte as base plus the named substitutions, and pins `inputs.tsv` as superset-plus-row. So a wrong implementation (a reworded comment, a dropped assertion, a deleted tsv row) cannot pass. The prep recorded these as mutants M1 to M12 and the execution reran them. I did not rerun `mutants.sh`, because the network-bound 25-minute script is the author's step. I read `narrow.py` and found that each mutant class it lists maps to a branch that goes red.
- **Gate.** `z-nile/check.sh --affected`: `GATE PASSED (affected)`, with z-nile at 298 passed, 0 failed, 45 spec files (both edited specs among them), and every other project's fence spec green. Wall time was 308.5s.
- **Selector.** `lune run z-nile/affected -- <the three touched files>` lists `c0074/done-gate`, `c0080/consequences` and the specs declaring those inputs. `titles.spec` is not listed yet because it is still sequestered. After `done` its `z-nile/tests/` folder row selects it whenever any z-nile spec changes, as the raft's Risks section says.
- **Other restatements of "done runs the full gate".** I searched outside the tracker with `git grep -nIi 'full gate' -- ':!*/.tracker/**' | grep -i done`. The hits are AGENTS.md (land's full gate, true), `zz-rules` SKILL.md:110 (the merge's full gate), `zz-test` SKILL.md:21 ("every step before it runs `--affected`, `./zn done` included"), `c0239/docs`/`done`/`land` (pins of the new rule), and two z-design lessons. One of those lessons, `inherited-decisions-agree.md`, quotes history. The other, `prove-specs-pass-on-a-prototype.md`:26, tells a prep to run the full gate on a simulated promotion. That is stricter than `done`'s gate, not a claim about what `done` runs, so it is not a finding.
- **Unfinished items on main that still quote the old titles.** I ran `git grep -nF -e 'done runs the full gate' -e 'skips the full gate' -e 'the gate decision: full' -e 'runs the full gate on the final tree' origin/main` with done/, review and refute files excluded. Besides the two edited specs and c0269/R0087's own docs, it found only:
  - c0178's `prototype.patch`: two hunk headers and one context line, a hand merge the Design already names.
  - c0180's `proto.patch`: one hunk header.
  - c0083.md:128: a stale "skips the full gate" note, a Non-goal left to c0083's own re-prep.

  None of these is a check that turns red when this raft lands.
- **Repository safety.** The diff adds no script and changes no guard. `narrow.py` only reads: `ls-remote`, `cat-file`, `merge-base`, `show`.
- **Bounded commands.** The verification log runs `mutants.sh` through `./zn run --time 1500`. The diff adds no unbounded command.
- **Lessons (`./zn lessons --when build`).** The change passes zz-test/narrowing-pins-the-whole-file, absence-scans-cover-every-form, no-vacuous-pass, specs-read-sources-through-the-selector (the tsv row) and zz-review/sequestration-reference-not-a-ref (the remote tip, never the local `origin/main`).

## Judged criteria (code mode only)
None (c0269 has no Judged criteria).

Verdict: approve
