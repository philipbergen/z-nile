# Review 001: R0135 (code mode)
Inputs: HEAD bc21aa7e5 (layer 1, c0388) against origin/main ce2c39c9d (`./zn sync --fetch`), `git diff origin/main...HEAD`; c0388.md, check.sh, guesses.md, acceptance/roots.spec.luau, experiments/prototype.patch; R0135.md and its check.sh.

Checks run by the reviewer: `./zn check c0388` 3/3 (AC1 runs `c0042/cli.spec.luau` on the real tracker, all three cases pass); `z-nile/check.sh --affected` GATE PASSED (336 passed, 0 failed, 44 spec files); `./zn promote-check R0135` OK; `git apply --check -R experiments/prototype.patch` applies, so the layer is the prep prototype byte for byte.

Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD` over the check.sh and acceptance globs lists only `A z-nile/.tracker/issues/active/c0388/acceptance/watch.txt`. That is the watch `./zn finish` generates (lesson zz-review/finish-watch-is-generated), not a sequestered edit: its two lines, `z-nile/tests/acceptance/c0042/ondisk.luau` and `z-nile/tests/inputs.tsv`, are exactly the layer's changed source files under zz-test's capture rule (the cli spec is left out as a spec, `c0042/watch.txt` as a watch file, tracker files as tracker files). No spec or check.sh under the item changed.

Correctness: `ondisk.items` reads `projects.roots(projects.load(top, true))`, the same registered roots `board.sources` reads (`projects.load(dir).projects`), and the same three states as `board.scan` (backlog, `active/`, `done/`), and skips a closed issue by the same predicate the board uses (`closing.isClosed(store.readFront(doc))`, board.luau:828). It keeps an independent folder walk with its own id patterns instead of reusing `board.scan`, which is right for an oracle the page is compared with (reusing it would make the case pass by construction). Retired roots and `rafts/retired/` are read by neither side. A missing registry errors through `projects.load`. The helper only reads; `roots.spec` writes only under the home's `.cache/c0388-roots`. Nothing outside `z-nile/tests/` and the tracker changed. Selection: `affected -- z-nile/engine/store.luau` already selects 37 specs; the three new `c0042/watch.txt` lines add c0042's fast siblings to it, a negligible cost.

### F1 [low] R0135's Risks says a leftover folder turns the case red naming the folder, but the raft half names nothing
Where: z-nile/.tracker/rafts/active/R0135/R0135.md, Risks & rollback, first bullet; z-nile/tests/acceptance/c0042/cli.spec.luau:67
Evidence: The raft half is a count, `t.expect(rafts).toBe(#found.rafts)`. A raft folder with no document (G3 keeps it counted) fails as `expected 122, got 121` with no id. Only the issue half names ids, through `table.concat(missing, " ")`; c0388's G3 says so accurately ("naming the missing issue ids"), and the raft document generalises it to every item folder.
Critique: whoever meets the red after a broken raft move reads the Risks line, expects an id in the failure and gets two numbers; they must then diff the folders by hand. The tempting fix is to make the raft half collect missing ids too, which would change the line `roots.spec` case 6 pins by text (`t.expect(rafts).toBe(#found.rafts)`), a sequestered spec.
Consequences: changing the raft assertion turns AC2 red and needs an escalation for a diagnostic nicety; rewording the document needs nothing else.
Recommendation: reword the Risks bullet to say what the case does: a leftover or broken issue folder turns it red naming the issue, a leftover raft folder turns it red on the raft count (expected N, got N+1). Leave the spec as designed.
Erred: z-raft
Upstream: none

### F2 [low] ondisk.luau's function comment sits on the wrong function and its header runs past the column width
Where: z-nile/tests/acceptance/c0042/ondisk.luau:7, :21-22
Evidence: The comment "the ids of the folders named like a raft (`R0010`) and like an issue ... a closed issue left out; the order is not part of the contract" documents what `ondisk.items` returns, but sits directly above `local function shown(dir, id)`, the closed-issue predicate, which returns a boolean and never sees a raft. Header line 7 is 153 characters against `z-nile/stylua.toml`'s `column_width = 110` (stylua does not rewrap comments, so the gate is green; every other line of the file is wrapped).
Critique: a reader of `shown` is told it yields ids of rafts and issues; a later edit to `items` is likely to leave its real contract (unordered, closed issues dropped) undocumented where it is defined. The prototype carried both, and the layer applied it byte for byte.
Consequences: none; comments only, no shape change (the design's "do not change the shape of the helper" is about the exported function and `Items`, which stay).
Recommendation: move the "ids of the folders ... order is not part of the contract" comment above `function ondisk.items`, give `shown` one line of its own (an issue folder is shown unless its document exists and is closed, c0278), and rewrap header line 7 under 110 columns. Rerun `./zn check c0388`.
Erred: zz-arch
Upstream: z-design

## Judged criteria (code mode only)
- JC1: pass. c0388 has no Judged criterion; its Judged section leaves the Non-goals to the code reviewer. The diff changes only `z-nile/tests/acceptance/c0042/` (cli spec, new helper, watch), `z-nile/tests/inputs.tsv` and tracker files: the board page and its engine, `z-nile/projects.toml`, the item folders and the cli spec's two other cases are unchanged.

Verdict: approve
