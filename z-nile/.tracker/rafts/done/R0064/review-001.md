# Review 001: R0064 (code mode)
Inputs: HEAD 99d06fe8 (branch R0064-register-arcade-projects), `git diff origin/main...HEAD` (origin/main 04571dee, merge-base 6d61bf73; main's two commits since the base touch only c0170's and c0190's items and three lessons, none of this diff's files), R0064.md and its check.sh, c0183.md, its check.sh, acceptance/ and experiments/.

Evidence run:
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` printed nothing (the move to `active/` landed on main with `ready`), and `git diff --summary origin/main...HEAD` shows only `create mode 100644` lines, no `mode change`.
- `./zn check c0183`: 6/6 criteria passed (AC1 to AC6).
- Design adherence: a scratch clone at 990575b6 (the branch's start), with `experiments/E2-proto.py` applied, stylua over the changed `.luau` and `experiments/E2-rehash.py` run, has a tree equal to 99d06fe8's except the two `spend.md` files (`git diff --cached --name-status 99d06fe8` lists only them). So the delivered change is the reviewed prototype byte for byte: items 1 to 7, the nine Overrides (each with its `-- c0183 override:` comment), the gate-cover case rename, and c0172 `narrowed`'s four new digests (gate-cover b95f71b3, ci d2ddf12c, c0120 docs a9c5f2a2, c0015 workflow 8107ba9f).
- Item 8: `z-nile/tests/lib/engine.luau` is not in the diff.
- `python3 -I experiments/E4-digests.py` and `shasum -a 256` of the nine delivered files agree.
- Touched modules: every path in `git diff --stat origin/main...HEAD` is a Touched module or one of the two `spend.md` files.
- Pinned stylua (`~/.rokit/bin/stylua` 2.5.2, as `rokit.toml` pins) `--check` over the changed `.luau`: clean.
- Each overridden spec run alone in this worktree: c0114 registry 7/7, gate-cover 8/8, docs 6/6, classified 5/5; c0120 registry-home 5/5, ci 4/4, docs 7/7; c0172 narrowed 1/1; pickman c0015 workflow 8/8.
- Non-vacuity of the derived overrides (scratch clone of the prototype):
  - `snake/.tracker/**` dropped from deploy.yml: gate-cover fails both cases and c0120 ci fails, while c0015 stays green (shape only, as designed).
  - `pickman/src/**` added to the list: c0015 fails.
- Repository safety: the new helper (`deploylist.ignored`) and the overrides only read (`projects.load`, `fs.readFile`, `git ls-files`). classified's copy still writes only under `.cache/c0114-classified-tree`. No guard file (`fence.luau`, `fence.sh`, `git-hooks/`, `ac.sh`, `repo-fence.spec`) is touched.
- Searches: `git grep -n "a new root needs only its registry entry"` and `git grep -n "registry entry only"` hit only c0183's own document, its E2-proto.py and the finished c0172's document (history). `git grep -nE "paths-ignore|registry entry only|needs only its registry|z-nile/\.tracker/\*\*" -- '*.md' '*.luau' '*.sh' '*.yml' ':!*/.tracker/**'` finds no other restatement of the ignore list besides the ones this diff updates.

### F1 [low] The c0183 Verification log is empty though its check passes
Where: z-nile/.tracker/issues/active/c0183/c0183.md, `## Verification log` (last section, no entries)
Evidence: zz-execute Phase 2 step 4 says to append a Verification log entry once `./zn check <issue>` passes. Phase 3 step 3 says to record the gate wall time and `slowest:` specs there. `./zn check c0183` passes 6/6 at 99d06fe8, and the section has nothing under it.
Critique: the PR's record doesn't say what was verified, or that the delivery is the E2 prototype unchanged (no deviation). The author may be tempted to add a bare "6/6 PASS" line.
Consequences: the full-gate figures can only be written after the lead's `z-nile/check.sh --full` run, which (per the user's "full gate only at merge" rule) comes later. So a single entry written now can't hold them.
Recommendation: append the entry now with the AC results and "no deviations: the tree equals E2-proto + stylua + E2-rehash". Add the gate wall time and `slowest:` specs as a second entry after the full gate, before `done`.

## Judged criteria (code mode only)
None (c0183 has no Judged criteria).

Lessons pass (`./zn lessons --when build`): promoted-specs-pin-rules-not-sets, no-vacuous-pass, one-reader-per-format (deploylist reads through `projects.load`), specs-pin-only-their-own-project (c0015 reads only deploy.yml, a root file it already read, and no registry), run-the-pinned-tools (stylua 2.5.2 checked): none repeated. No candidate lesson.

Verdict: approve
