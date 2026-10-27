# Review 002: c0141 (design mode)
Inputs: prep `prep-check-paths-home` c11b92c1 (c0141.md, check.sh, acceptance/touched-from-home.spec.luau, acceptance/uses-module.spec.luau, design-review-001.md, design-refute-001.md, harvest.md); prototype `proto-check-paths-home` 24beb235 (`z-nile/tests/acceptance/c0120/checkpaths.luau`, c0120 `check-paths.spec.luau`); `./zn lessons --when design --full`. Probes ran in a scratch clone of 24beb235 (scratchpad `dr-chores-3/c0141`).
Dropped from design-review-001: F1, F2, F3

Rulings on refute 001:
- F1 (both readings): the fix holds for the two cases the review named (c0006 and f0007 are reported). But the new rule decides some entries by what exists on disk, and that leaves a hole of the same kind (F1 below). Under the skill's rule for a second hole in one mechanism, F1 questions the mechanism.
- F2 (c0120's spec keeps its own scan): fixed. `uses-module.spec` pins the require, the call and the absent local functions. The pin is textual, so a deliberate evasion still passes it (F2 below, low).
- F3 (the rule leaves the promoted folder): fixed. The module sits beside `rewrites.luau` and `finished.luau`, and the Overrides line names the spec and the module.

### F1 [medium] Rules 2–4 read an entry by what exists on disk, so a path an item will create is misread until it exists, and the reading changes between checkouts
Where: c0141.md Design, "The rule (c0141)" rules 2–4 ("Each entry's own first segment tells which it is"); prototype `checkpaths.owned`
Evidence: probe spec on the prototype (scratch clone). The fixture has a root `.github/` and `AGENTS.md` and a pickman item that creates its own `pickman/.github/workflows/new.yml`. Its Touched entry is written home-relative, `.github/workflows/new.yml`.
- f0001's check.sh is `test -f .github/workflows/new.yml`, which is correct: it tests what the item creates.
- f0002's check.sh is `cd .. && test -f .github/workflows/new.yml`, which is wrong: it tests the root path, which nothing creates.
`checkpaths.scan` printed:
```
before pickman/.github exists: { "pickman/.tracker/issues/f0001/check.sh: .github/workflows/new.yml (from pickman)" }
after pickman/.github exists:  { "pickman/.tracker/issues/f0002/check.sh: ../.github/workflows/new.yml (from pickman)" }
```
Before the item's work runs, the correct check is reported and the wrong one is exempt. This is the capture's defect ("fails the gate the moment its prep lands") together with design review 001 F1's (an exempt path the item never creates). After the work runs, the two swap. The live backlog already has an entry this rule misreads. c0117 (active) lists `- \`.models.toml\`` beside `z-nile/…` entries, and its Design says "Add a root `.models.toml`". Neither `.models.toml` exists, so rule 4 reads the entry as `z-nile/.models.toml`, and rule 3 will read it as the root's once c0117 creates the file. Today no literal names it, so nothing is reported. Existence also differs between checkouts. The main checkout has an untracked `build/`, an ignored `sourcemap.json` and `.cursor/` at the top, and a fresh worktree has none of them, nor a CI checkout, nor c0152's trial merge, which runs this spec in a throwaway worktree. The same entry can therefore read one way in one checkout and the other way in another.
Critique: "chosen from the entry's own text" is true only of rule 1. Rules 2–4 choose from the tree, which the item itself changes, and the design's caveat names only a home holding a folder called after another home. The tempting fix is to add the root-level names to a fixed list (`FILES` plus `.github`, `.claude`, `tracker`). That still misreads c0117's `.models.toml`, and every new root file needs an entry.
Consequences: the live documents show that a document has one convention, not each entry. Every document that writes a `<home>/` entry is repository-relative throughout (c0117, c0075, c0083: their bare `AGENTS.md`, `.models.toml`, `scripts/…`, `tracker/…` are root paths). The documents that never do are home-relative throughout (c0128, c0150, d0124, f0126). A reading per document uses only text, so it can't flip and can't differ between checkouts. A home-relative document then names a root path as `../AGENTS.md`, which `repoPath` already folds. The new consequence is that a home-relative document with a bare root name (`AGENTS.md` meaning the root's) reads it as the home's. The search below finds none today, and the z-design skill's Touched-modules guidance must say how to write one.
Search (rerun it): for each unfinished item document, the first segments of its Touched entries:
```
for f in $(git ls-files | grep -E '\.tracker/(issues|rafts)/(active/)?[fdcR][0-9]{4}/[fdcR][0-9]{4}\.md$'); do
  awk '/^### Touched modules/{f=1;next} /^#/{f=0} f' $f | grep -oE '^- `[^`]+`' | sed 's/^- `//;s/`$//' | cut -d/ -f1 | sort -u | tr '\n' ' '; echo " $f"; done
```
Hits: pickman c0128 `tests tracker`, c0150 `.tracker tests`, d0124 `src tests tracker`, f0126 `.tracker src tests` (all home-relative); z-nile c0117 `.models.toml AGENTS.md z-nile`, c0075 `.github AGENTS.md scripts SETUP.md tests tracker z-nile`, c0083 `AGENTS.md pickman scripts tests tracker z-nile` (all mixed with `z-nile/`, so repository-relative).
Recommendation: take the convention from the document, not from the disk. If any Touched entry (of the item, or of the raft's member it comes from) starts with a registered home, read every entry of that document from the top. Otherwise read every entry from the item's home, and `..` reaches the top. Drop the `fs.isDir`/`fs.isFile` tests from `owned`, and state the rule and how to name a root path from a home-relative document in the Design and in z-design's Touched-modules guidance. Cases: the probe's f0001/f0002 give the same report before and after `pickman/.github` exists (f0001 exempt, f0002 reported); a c0117-like document (`.models.toml` + `z-nile/x`) owns the root's `.models.toml`; a home-relative document with `../AGENTS.md` owns `AGENTS.md`; the existing c0001/f0003/c0005/c0006/f0007 verdicts are unchanged. Mutant: "existence decides" (the prototype's rules 2–3), killed by the before/after pair. Rerun E1 on the live tree. If the author keeps reading by existence instead, the Design must name the misread class (a first segment that exists only at the top, or nowhere yet) and the checkout dependence. It also needs the before/after case, plus a `Decided with the user` line, because the gate's verdict would then depend on the checkout.
Lesson: z-design/new-rules-migrate-existing-work

### F2 [low] `uses-module.spec` passes a spec that keeps its own scanner under another spelling
Where: acceptance/uses-module.spec.luau
Evidence: the pin looks for `local function <name>(` and `PREFIXES =`. A c0120 spec that keeps `local scan = function(…)` or `local PFX = {…}`, with `checkpaths.scan(` only in a comment, passes all assertions.
Critique / Consequences: this is the textual pin design review 001 asked for, and an executor in a hurry won't evade it on purpose. Lesson zz-test/source-pins-name-what-the-design-names prefers a behavioural case where one can observe the rule.
Recommendation: also pin the wrapper, so the spec's `scanFrom` body is `return checkpaths.scan(base,`, matched after stripping comments. Or add a behavioural case: run c0120's spec once with `checkpaths.scan` replaced, through the module's table, by one that reports a sentinel, and expect the real-tree case to go red. Either way the mutant "local scan kept, comment names checkpaths.scan(" goes red.

Candidate lessons (for the lead):
- z-design: a rule that guesses a value's meaning from what exists on disk changes its answer when the item's own work creates the thing, and between checkouts that differ in untracked or ignored files; check: does any reading depend on the filesystem, and what does it say before and after this item's work, and in a fresh clone?

Verdict: changes
