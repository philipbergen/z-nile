# Review 012: c0115 (design mode)
Inputs: prep-c0115 at a2ab20a6 (`design-review-011.md`, `design-refute-011.md`, `check.sh` AC13 and AC14, `experiments/trusted-base.luau`, `rewrite-finished.luau`, `rewrite-finished-sim.sh`, `acceptance/trusted-base.spec.luau`); prototype `proto-c0115` at 3d1326c1 (its `rewrite-finished.luau` and `trusted-base.luau` are byte-identical to the prep's), used only through scratch clones; c0137 as captured on main (34dc336e).
Dropped from design-review-011: none. F1, F2 and F3 are fixed; F4 is captured as c0137. The three findings below are low.

What holds:
- **The simulation.** `rewrite-finished-sim.sh <scratch> proto-c0115 d6874ef2` reproduces every case of the refute: all 22 lines print the expected exit. That covers the ref forged to HEAD and to the edit commit (red), unfetched and unreachable origin (red), B, C and C2 (red), main's deletes, renames and edits merged (green), c0199 before and after 5c, RC3 and c0040, and AC13 with the ref forged.
- **`trusted-base.spec.luau`** passes under the runner in a clone of the prototype (7 passed). Its fixture is a local bare origin under `.cache`, so the spec runs with no network. The real `ls-remote` happens only in `check.sh`'s own `lune run` (plain bash under `./zn check`, not the jail), and it is a read. In the prep worktree it returns main's tip in about 1 s.
- **F1 attacks** (in the sim's bare-origin clone, with c0004 AC1 weakened):
  - *A forged local ref* is never read: red.
  - *A tip that is local but not an ancestor*: main edited c0005, the branch fetched it and didn't merge. The honest branch is green against the fork point, which is right. The merge-base is always an ancestor of the remote tip, so its text is main's: the author can't push the base onto the branch's side. Rebasing onto an older main only makes the base older, and the PR merge then keeps main's later edits.
  - *Origin repointed at a bare repo the author controls*: green (`remote set-url`, and also `url.<evil>.insteadOf`). It is a real hole, but a deliberate one. Under the user's choice to detect, not prevent, it is the same class as the next item, so it is F1 below at low.
  - *A fake `git` early on PATH*: it defeats every check in the repository, not just this one. It isn't a finding.
- **F2.** The base-side listing reads the roots from the base's `projects.toml`, and its id pattern matches the HEAD loop's. Pointing a finished `check.sh` at another file through a symlink is still red, because the HEAD side reads the content. `./zn done` refuses a dirty tree, so an untracked copy can't stand in for a deleted file.
- **F3.** c0084:60 is now `grep -rnF -- "--time 0" skills ../pickman/skills`. With `--time 0` planted in `zz-rules` it finds the line, and without the plant it doesn't. The forms `grep -n -r … ../.claude/skills` and `grep --recursive … ../.claude/skills`, finished on the branch as c0198, are red through rule 1b ("needs a rewrite").

### F1 [low] An origin swapped before the run (`remote set-url`, or `url.*.insteadOf`) makes AC13 and AC14 green, and the limit is written only in a code comment
Where: `experiments/trusted-base.luau:6-7` (the "What review must still catch" comment); c0115.md §8 and AC13 don't mention it.
Evidence: c0004 AC1 was weakened in the sim clone. Then a bare `evil.git` was created with main at HEAD, and `git remote set-url origin evil.git` was run: `--check` exits 0 (`0 of 131 … would be rewritten`, the empty range). The same happens with `git config url.<evil>.insteadOf <origin>`, which leaves `remote.origin.url` honest. Nothing in the check's output says which repository gave the tip.
Critique: this is the accepted limit (detect, not prevent), and it needs deliberate config tampering, which is the same class as a fake `git`. But the code reviewer who must catch it learns about it only by reading the helper's source. The tempting fix is to compare the URL with a hard-coded GitHub URL, which breaks every fixture and fork.
Consequences: printing the URL costs one `git ls-remote --get-url origin` (it applies `insteadOf`), with no new red state.
Recommendation: the helper prints the URL it resolved (`ls-remote --get-url origin`) with the base, on both `--print` and `rewrite-finished`'s summary line. Add one line to c0115.md's AC13/AC14 text, or to its Unknowns: "an origin swapped before the run is review's to catch; the check prints the URL it read". No spec case is needed beyond the existing ones still passing.

### F2 [low] The recursive-grep scan and rule 1b still miss a trailing-slash operand (`../.claude/skills/` or `../.claude/skills/*`), which is just as vacuous
Where: `rewrite-finished.luau` `linkScans` (`if after ~= "/" then bare = true`), and rule 1b's "not then `/`".
Evidence: a branch-finished `done/c0198/check.sh` with `bash -c "! grep -rn x ../.claude/skills/"`, and another with `…/skills/*`, both give `--check` exit 0. macOS `/usr/bin/grep -rln "name:" ../.claude/skills/` (and `…/skills/*`) lists 0 files from `z-nile/`: BSD grep's default `-p` follows no links, not even links named on the command line. No finished file at the base uses either form, so this matters only for an item that finishes on main during the window, which is exactly what the independent scan exists for. This is the eighth hole in an operand-matching rule since round 10.
Critique: the mechanism matches spellings, and each round finds another one. The tempting fix is to add `/` and `/*` to the list, which is fine for these two, but it remains a list.
Consequences: treat `.claude/skills` followed by an optional `/` and then a non-name character (the end, a space, a quote, `*`, `)` or `;`) as bare, in the scan and in rule 1b alike. Rule 1b would then rewrite `../.claude/skills/*` to the real folders' globs, a new form the exact check would have to pin. Applying the change only to the scan (red, rewrite by hand) is cheaper and enough for a window-only risk.
Recommendation: widen `linkScans` alone to that pattern, and add the two c0198 forms to `rewrite-finished-sim.sh` as red cases. Leave rule 1b as it is, since nothing at the base needs it.

### F3 [low] c0137's capture misses a fifth vacuous `.claude` scan: c0069 `check.sh:41`
Where: main's `tracker/issues/c0137/c0137.md` Problem lists c0044:56, c0067:56, R0025:15 and c0067:44.
Evidence: `git grep` at d6874ef2 shows `done/c0069/check.sh:41: bad=$(grep -rnF "./zn launch" .claude ../AGENTS.md ../SETUP.md ./templates scripts || true)`. It runs from `z-nile/`, where `.claude` doesn't exist in the base or the prototype, so it errors and `|| true` swallows the error, the same as the other four. Round 11's F4 also missed it.
Critique: this is outside c0115, and c0115 isn't widened. But the capture's list is what c0137's prep will start from.
Consequences: none for c0115.
Recommendation: add c0069:41 to c0137's Problem, through the lead's capture edit or a note for c0137's prep.

Candidate lesson (for the lead): when a finding names "the N places that do X", find them with a search over the whole corpus and paste that search into the finding, rather than listing them from memory. Round 11 listed four `.claude` scans and missed a fifth. Check: "is the list the output of a search I can rerun?"

Verdict: approve
