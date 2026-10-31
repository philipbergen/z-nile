# Review 001: R0061 (code mode)
Inputs: R0061-z-nile-header-slug-scans at a033b715 (`git diff origin/main...HEAD`, origin/main a54c0603); R0061.md, its check.sh and design review/refute 001; c0134, c0135, c0137 documents, check.sh files and acceptance specs.

What I ran:
- `./zn check R0061` in the raft worktree: 5/5 PASS (RC0 full z-nile gate; c0134, c0135 and c0137 check.sh files; promote-check). Worktree clean afterwards.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` prints exactly one line: `M z-nile/.tracker/issues/active/c0135/acceptance/slugs.spec.luau`, the edit the user authorized. `git diff --summary` shows no mode change (only `create mode 100644 …/R0061/spend.md`).
- The authorized edit (5e0dbd30): the inline two-op table is replaced by the case's existing `ops` (typed `{ any }`), which holds the same two ops (`new`/`chore`, `c0001` then `c0002`, root `pickman/.tracker`). The slugOf map, the `taken` set and the expected `{ "a-2", "b-2" }` are unchanged. In a scratch clone outside the repository, the review-003 F2 shared-counter mutant (one `n` declared before the loop) fails the case at `slugs.spec:97`, giving 14 passed and 1 failed. Without the mutant it is 15/0.
- The branch's engine merged with today's origin/main (db7e812f, in the scratch clone): `./zn audit` gives `0 errors, 1 warnings` (orphan-raft R0040), so main's new items share no slug.
- My own mutants against slugs.spec, in the scratch clone:
  - (a) raft-plan's taken set without the `kind == "raft"` filter: slugs.spec stays green (15/0). It is killed in the gate by c0116's promoted `plan-cli.spec` (5 passed, 1 failed), so this needs no finding.
  - (b) slugClashes without its final sort, plus sluggedFromTree without `id == again`: 15/0, a survivor (F3).
- c0134's header matches its Design's five lines exactly. c0137's diff holds only its Verification log and spend.
- Repository safety: the engine change adds no write. `listed` is read-only, and `publish.allowed`/`validateMoves` are untouched. slugs.spec's mutations stay in its trackerfix fixture under `.cache/c0135-slugs`, and its skill case only reads the real tree. The c0082 changes edit fixture text only. No guard file is touched.

### F1 [low] reserveOnOrigin's doc comment now sits on slugTaken
Where: z-nile/engine/main.luau:713-716
Evidence: `slugTaken` and its comment were inserted between `-- Reserves the next number of \`space\` on origin/main … \`extra\`: ids that count besides origin's (the local tree's).` and `reserveOnOrigin`. Lines 713-714 now describe reserveOnOrigin but run straight into slugTaken's comment (715-716) and its definition. reserveOnOrigin keeps only the `check` paragraph (733-734).
Critique: a reader of slugTaken gets the wrong function's contract, and reserveOnOrigin loses its own.
Consequences: none.
Recommendation: move lines 713-714 down to sit directly above reserveOnOrigin's `check` paragraph.

### F2 [low] `listed` is typed optional, the callers cast it away, and slugTaken skips origin quietly when it is nil
Where: z-nile/engine/publish.luau `Build` (`listed: { string }?`); main.luau slugTaken (`if listed and roots and read then`) and the three `listed :: { string }` casts
Evidence: `publish.commit` always passes `listed`, yet each publishing caller casts it. If `listed` were nil, slugTaken would check only this checkout and still return nil. A publisher change that stopped passing it would make the origin check fail open, against zz-arch's rule that guards fail closed. Today slugs.spec catches that drop (M4b: the raft retired on origin only; M15: the emergent issue sees origin), so nothing is wrong now.
Critique: the optional type exists only so that older 4-argument callbacks keep fitting `Build`. It moves the burden onto the guard's caller, which then trusts a cast.
Consequences: making the argument required changes the `Build` type every publish callback is checked against. Older callbacks that take four parameters must still type-check (`./zn promote-check` and the gate's analysis).
Recommendation: in slugTaken's publishing callers, fail closed: return `publish gave no listing of origin/main: cannot check the slug` when `listed` is nil, instead of casting. Alternatively, make `listed` required in `Build` if the existing 4-parameter callbacks still type-check. Either way, no sequestered file changes.

### F3 [low] Two stated rules of the slug reader have no case: the clash order, and a document named after its folder
Where: z-nile/engine/audit.luau slugClashes (final `table.sort`) and sluggedFromTree (`id == again`); c0135 Design ("sorted by kind then slug")
Evidence: in the scratch clone I removed slugClashes' final sort and dropped `id == again` from sluggedFromTree. `lune run tests/run -- .tracker/issues/active/c0135/acceptance/slugs.spec.luau` still gives `15 passed, 0 failed`. Every case holds one clash at a time, and no fixture has a `.md` whose name differs from its folder. Without the sort, audit's order for several clashes comes from hash iteration.
Critique: the Rules and mutants table has no row for either rule, and the gate's real-tree audits hold no clash, so nothing pins them. Being sequestered, slugs.spec can't take the cases.
Consequences: none beyond one unsequestered spec file.
Recommendation: add a z-nile tooling spec (for example `z-nile/tests/tooling/slugs.spec.luau`, not sequestered) with two cases:
- slugClashes given two clashes of two kinds in reverse order expects them sorted by kind, then slug;
- sluggedFromTree given `issues/c0005/c0006.md` expects no item.

Run each mutant above against it and record the result in the Verification log.

### F4 [low] raftplan.commands' new comment line is 168 columns
Where: z-nile/engine/raftplan.luau:309
Evidence: `git diff origin/main...HEAD -U0 -- z-nile/engine | grep '^+' | awk 'length > 121'` prints this one line, at 168 characters. `z-nile/stylua.toml` sets `column_width = 110`, and stylua does not wrap comments.
Critique: this is the only over-long line in the diff, and it breaks the file's wrapped-comment style.
Consequences: none.
Recommendation: rewrap the comment to 110 columns.

### F5 [low] 5e0dbd30's spend record is on c0137, not on c0135, whose spec it edits
Where: z-nile/.tracker/issues/active/c0137/spend.md row 8 ("c0135: slugs.spec two-bases case passes the typed ops …", 10.0 min, `focus`)
Evidence: `git show --stat 5e0dbd30` changes `c0137/spend.md` and `R0061/spend.md`, not `c0135/spend.md`. The focus was still c0137 from the previous commit.
Critique: c0137's build minutes are overstated by 10 and c0135's understated, which skews per-issue cost in `./zn metrics`. The raft total is unchanged.
Consequences: the R0061 roll-up is regenerated from the issue tables, so both issues' totals lines must agree after the move.
Recommendation: move the record to c0135 with the tracker's spend tooling (zz-rules, Spend), or by editing both tables and their totals lines, then regenerate R0061's spend.md. Run `./zn focus c0135` before the next c0135 commit.

## Judged criteria (code mode only)
None: c0134, c0135 and c0137 each list `### Judged` as None.

Candidate lesson (for the lead to harvest): zz-execute: set the focus to the issue a commit changes before recording its spend. A fix to one member's file, made while another member holds the focus, goes on the wrong issue. Check: does the commit's spend row sit in the spend.md of the issue whose files the commit changes?

Verdict: approve
