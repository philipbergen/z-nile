# Review 003: R0100 (code mode)
Inputs: layer 4 (c0276), `git diff R0100/3/c0275...R0100/4/c0276` (layer 4 at 360d3036d, layer 3 at 57a78aae6). I read the files with `git show R0100/4/c0276:<path>`. Also read: c0276.md, its check.sh, acceptance/{verdicts,board}.spec.luau, R0100.md (Whole-raft design, Layer rules, Interfaces, Experiments, Risks), review-001.md and review-002.md, and `origin/proto-c0276` (965c0fd6), the prototype the layer was ported from.
Checked:
- Runs. Each ran in a copy made with `git archive`, never in the worktree, and each through `./zn run`.
  - `./zn check c0276` on the layer-4 tree: 4/4.
  - `./zn check c0265` and `./zn check c0275` on the layer-4 tree, one at a time, real-time proofs included.
    - c0275: 4/4.
    - c0265: 4/5 on the first run. One case of `proofs/race` failed: "one failed fetch of main inside a --watch tick is said …", at line 204, the stderr assertion.
    - That case runs no `sync` and no `board`, so it never reaches the only code this layer changed. I reran `proofs/race` alone, twice on the layer-4 tree and twice on the layer-3 tree: 8/8 every time.
    - So it is the load flake the raft's Risks describe for real-time proofs, not a regression from this layer.
  - `z-nile/check.sh --project z-nile --affected` on a scratch repository: `main` is the layer-3 tree, and the branch `R0100/4/c0276` is the layer-4 tree, so the selection is this layer's. The format stage fails and the gate stops before any spec (F1). Then I reformatted that one line in the copy only. With that change: `GATE PASSED (affected)`, 764 passed, 0 failed, 131 spec files. Both c0276 acceptance specs are included. selene and luau-lsp are clean.
- Sequestration. Over check.sh and acceptance/, the layer diff lists only `A z-nile/.tracker/issues/active/c0276/acceptance/watch.txt`. That is the watch map `./zn finish` writes, and its three lines (`board.html`, `board.luau`, `main.luau`) are this layer's own sources (as review-002 noted, zz-review item 2 does not name the file yet; c0326 captures that). Across the whole stack against `origin/main`, the only changes besides `R100` renames are the members' watch maps.
- The 200-local cap. I compiled padded copies of `main.luau` with `@lune/luau`. Layer 4 has 10 spare top-level locals, the same as layer 3; `origin/main` has 4. The layer adds no top-level local, because `boardVerdicts` is a field of `hb`.
- RC2 and the Risks' "two `local hb`" hazard. `main.luau` declares `local hb` once (line 422, above `buildBoard` at 660). `function hb.boardVerdicts` is defined once. The `boardview` local is kept. The prototype's typed second declaration is gone.
- The port. `board.luau` and `board.html` are byte-identical to `origin/proto-c0276`, and `hb.boardVerdicts` is the prototype's body unchanged. The only hand resolution is dropping the forward declaration (its comment stayed: F2).
- Design adherence:
  - Pure part:
    - `MARKS` maps lost, parked, stale, unknown→stale and nobeat. Live claims and other kinds get nothing.
    - `minutes` is `math.floor(silent / 60)`.
    - Lost cards come first in every `views` bucket and every column band. The sort is stable, and its comparator is a total order: lost first, then silence descending, then the old index. Bands keep their order.
    - The input model is never changed: the lists are cloned, and the views and columns are rebuilt.
    - `board.build` gains two trailing optional parameters. `notes` is set only when it is non-empty.
  - Edge:
    - `guarded(true)` runs first and quietly, then `publishing()`. That call cannot print the guard's saying, which is set only when the checkout is guarded.
    - `fresh` skips the fetch of main. `buildBoard` is the only `fresh = true` caller, and it is called only from the main-checkout `sync`, right after that sync's own fetch (line 3436).
    - Every read is inside the `pcall`, and `sh.git` throws (`sh.must`), so a vanished document is caught.
    - `hb.claimsOf` calls `fail` (`process.exit`) when origin/main's registry is missing. The `originRoots() == nil` test before `judgeAll` keeps that call from being reached.
    - The five warning texts are the Design's.
  - Page:
    - `mark()` draws on cards, on the band head (a raft's own claim), on list rows and in both panes. Everything it writes is escaped.
    - `--alert` has its own dark-mode value.
    - The notes go into a new `#notes` element above `<main>`, which AC2's "drawn above every view" needs (see F2 on the Design's wording).
- Repository safety and bounded commands. The diff adds no spec, check.sh or script, and no guard file changes. The new remote reads go through `hb.netRetry` and `hb.netRun`, which are bounded. They only read from origin (a fetch of `main`, one of `hb/*` into `refs/zn/hb-seen`, and `gh pr list`). None runs in a protected checkout.
- Docs. The zz-rules board row and Heartbeat bullet and the README's board paragraph carry what AC4 pins. The zz-rules merge with layer 5 (Experiments, conflict 2) is prepared as the raft says: the board sentence is appended to the Heartbeat bullet.

### F1 [high] The layer's tree fails the gate's format stage, so RC0 (and `./zn done R0100`) fails
Where: z-nile/engine/main.luau:1566 (`hb.readBeats`); z-nile/check.sh:234 (`stylua --check "${LUAU_DIRS[@]}"`)
Evidence:
- The line `local f = hb.netRetry("git", { "fetch", "-q", "--prune", "origin", `+{heartbeat.PREFIX}*:refs/zn/hb-seen/*` })` is 113 columns at the configured tab width of 4. `stylua.toml` sets `column_width = 110`.
- `stylua --check` reports a diff in `main.luau` at that line on R0100/1/c0265, R0100/3/c0275, R0100/4/c0276 and R0100/5/c0277, and none on `origin/main`. I ran the rokit pin (2.5.2, `~/.rokit/bin/stylua`) with the repository's `stylua.toml`.
- On the layer-4 tree, `z-nile/check.sh --project z-nile --affected` prints `== format (stylua --check) (4.3s, FAILED)` with that diff and exits 1 before any spec runs.
- The line was introduced in layer 1 (`git log -S` finds 5fac972a4). It is review-001 F5's fix: the hard-coded `+refs/heads/hb/*` was replaced with `heartbeat.PREFIX`, which made the line longer. Layer 4 did not touch it, but this layer's gate and the raft's RC0 run on the whole tree.
- c0276's Verification log records `./zn check c0276` only, not a gate run, so nothing shows that the gate ran green after the layer-1 fix.
Critique: RC0 is the raft's first exit criterion and the merge's gate. As the stack stands, the gate is red at its first stage and never reaches a spec. The tempting fix is to reformat in the top layer. That leaves layers 1 to 3 red as commits, and each stack PR's own gate stays red.
Consequences: Fixing it in layer 1 changes layer 1's commit, so the restack rewrites layers 2 to 5. The change is formatting only: no spec, watch map or behaviour changes, and the affected selection is the same.
Recommendation:
- Run the pinned `stylua z-nile/engine/main.luau` on layer 1. It splits the line as `local f =` with the call on the next line. Then restack.
- After the restack, run `z-nile/check.sh --project z-nile --affected` once per layer, and record it in that layer's Verification log, not only the member's `./zn check`.
- With that one change made in my copy, this layer's affected gate passed: 764 passed, 0 failed, 131 spec files.
Lesson: zz-execute/fix-rounds-rerun-every-member-check

### F2 [low] The comment above `buildBoard` describes a declaration that no longer exists and callers that no longer rebuild, and two documents disagree with the code
Where: z-nile/engine/main.luau:656-659; c0276.md Design section 2 ("drawn in the page's `#problems` area"); z-nile/README.md, the board paragraph
Evidence:
- **The comment.** Lines 656-658 read: "c0276: each claim's verdict for the board, or nil (no marks) when none can be read; `fresh` says the caller has just fetched origin/main (a publish, land or sync), so the rebuild does not fetch it again. Assigned where the heartbeat's reads are defined, below. …" A blank line follows, then `local function buildBoard`.
  - It was the comment on the prototype's forward declaration `local hb = {} :: { boardVerdicts: … }`, which the port rightly dropped.
  - "Assigned … below" now refers to nothing.
  - "(a publish, land or sync)" contradicts the Design ("a publish and a `land` rebuild nothing since #296") and the comment 15 lines further down ("A publish pushes and does nothing else").
  - The blank line separates `buildBoard`'s own comment (lines 652-655) from the function.
- **The notes.** The Design's section 2 says the notes are drawn in `#problems`. `#problems` sits inside the Board section, which is hidden on the Rafts and Issues views. The code draws them in a new `#notes` above `<main>`, which is what AC2 and Rules row V11 need. The Verification log does not record this deviation.
- **The README.** It says the board shows "the same verdicts as `./zn lost`". zz-rules says "the verdicts of `./zn status`". The board marks parked, `stale?` and `no beat` claims too, and `./zn lost` does not list those.
Critique: c0180 will move `buildBoard` by name, and its executor will read this comment. A comment that says a publish rebuilds the board restates a rule that `c0070/board-refresh` pins the other way.
Consequences: none.
Recommendation:
- Replace lines 656-659 with one line inside `buildBoard`'s comment, for example "c0276: the page carries the claims' verdicts (`hb.boardVerdicts`, below); `true`: its one caller, the main-checkout sync, has just fetched origin/main". Remove the blank line.
- Add a line to the Verification log saying the notes are drawn in `#notes` above every view (AC2, V11), not in `#problems`.
- README: "the same verdicts as `./zn status`".
- None of these strings is pinned: AC4's README words are `lost 35m`, `no beat`, `lost work comes first` and `c0276`.
Lesson: z-design/restated-rules-move-together

## Judged criteria (code mode only)
- None: c0276 has no Judged criteria, and OC1 is a person's look at the drawn page. Each Checked criterion has code that implements it as the Design states, and each passes on the layer-4 tree:
  - AC1: `withVerdicts` and `mark()`.
  - AC2: `hb.boardVerdicts` and its two call sites.
  - AC3: the promoted board specs, run in a protected checkout with no remote read.
  - AC4: the docs.
- F1 is not in c0276's code. It is the stack's gate, which this layer's tree inherits from layer 1. With F1 fixed, nothing in layer 4 stands in the way of an approval.

Verdict: changes
