# Review 003: c0141 (design mode)
Inputs: prep `prep-check-paths-home` 3524a78d (c0141.md, check.sh, acceptance/touched-from-home.spec.luau, acceptance/uses-module.spec.luau, design-review-002.md, design-refute-002.md, harvest.md, the new lesson z-design/readings-from-text-not-disk); prototype `proto-check-paths-home` 83f41f9c (`z-nile/tests/acceptance/c0120/checkpaths.luau`, c0120 `check-paths.spec.luau`, z-design SKILL.md); `./zn lessons --when design`; `./zn capture c0141`. Probes ran in a scratch clone of 83f41f9c with the two acceptance specs copied to `z-nile/tests/acceptance/c0141/` (scratchpad `dr-chores-4/c0141`).
Dropped from design-review-002: F1, F2

Rulings on refute 002:
- F1 (existence decides): fixed. `owned` reads no file; the reviewer's f0001/f0002 probe is a case and gives the same verdict before and after `pickman/.github` exists (ran: 4/4 pass). The per-document rule matches the live search, rerun on the prototype: every unfinished document with a `<home>/` entry is repository-relative, the rest home-relative. z-design's Touched-modules bullet states the rule. Two mutants of the new rule survive (F1, F2 below); they are gaps in the cases, not in the mechanism.
- F2 (textual pin): fixed. `uses-module.spec` strips comments, requires `local function scanFrom(…)\n return checkpaths.scan(base,` and refuses every spelling of the moved functions and constants. It passes on the prototype (1/1).
- Overrides (item 4): `lune run z-nile/affected` on the prototype lists c0120's check-paths spec and c0141's touched-from-home spec for `checkpaths.luau`. The z-design SKILL.md change is `ALL`, and the eight promoted specs that read it (grep: c0119 scope-docs, c0120 docs, c0111 skill-docs and lessons-cli, c0116 docs, c0047 override-check, c0115 docs, c0043 ticket-prep) are covered by E1's full gate on 83f41f9c. Overrides line complete.
- Scope (item 11): the capture's outcome (fold to the repository-relative form before comparing; the `cd .. && x pickman/new-thing` case; the override of c0120/check-paths) has its Design and AC1–AC3.

### F1 [medium] "Any entry starts with a home" is only tested with the home entry last, so "the last entry decides" passes every spec
Where: c0141.md Rules and mutants, row "the convention is the whole document's" (N5); touched-from-home.spec "reads a document's Touched entries…"; prototype `checkpaths.owned`
Evidence: every mixed case puts the `<home>/` entry last (`{ ".models.toml", "z-nile/x" }`, `{ "AGENTS.md", "game2/x" }`), and the scan fixture has no mixed document. In the scratch clone I replaced the loop's `if first and table.find(homes, first) then fromTop = true end` with the overwrite `fromTop = first ~= nil and table.find(homes, first) ~= nil`, so the last entry decides. touched-from-home: 4 passed, 0 failed. c0120 check-paths: 4 passed, 0 failed. Under that mutant, a repository-relative document that lists its root files after its `z-nile/…` entries (c0117's order, for example, if edited) is read from the home, and its exemptions move to `z-nile/.models.toml`.
Critique: N5 ("only a `<home>/` entry from the top") is killed, but its sibling, a loop that overwrites instead of OR-ing, is the bug a hurried executor writes. The tempting fix is one more case with the home entry first. That is the right fix, but it is enough only if it also covers a bare entry *after* the home entry.
Consequences: none beyond the case and the table row.
Recommendation: add `owned("z-nile", { "z-nile/x", ".models.toml" }, homes) == { "z-nile/x", ".models.toml" }` and a three-entry case with the home entry in the middle. Add row N7 "the last (or first) entry decides" to the Rules and mutants table, and record it as killed in E2. Ran in the scratch clone: the first case fails under the overwrite mutant.
Lesson: zz-test/seed-every-enumerated-case

### F2 [medium] "Homes come from the registry" is pinned only at `owned`'s parameter, so a hand list in `scan` passes every spec
Where: Rules and mutants row "homes come from the registry" (N2, said to be killed by the `game2/x` case); prototype `scan` (`for _, r in projects.roots(reg)`)
Evidence: the `game2/x` case calls `owned` with `homes` passed in by the test, so it never exercises how `scan` builds `homes`. The scan fixture registers `game2` but has no item that names it. In the scratch clone, `scan` with `local homes = { "pickman", "z-nile" }` (registry loop removed) gave touched-from-home 4/4 and c0120 check-paths 4/4. A third project is the case the design's "read from the registry's roots, never a hand list" exists for. The round-001 draft's `PREFIXES` was exactly such a hand list.
Critique: the row claims a kill that only a mutant of `owned` gets. The tempting fix is to assert on `scan`'s internals. That fix isn't needed: one fixture item shows it.
Consequences: the fixture needs `game2/.tracker/issues/` to exist. With that in place, `projects.load` accepts it (ran).
Recommendation: in the scan fixture, add a z-nile item with Touched `{ "game2/new" }` and check.sh `cd .. && test -d game2/new`, expected exempt. Ran in the scratch clone: `scan` reports nothing with the registry and reports the item with the hand list. Reword row N2 so its mutant is "`scan` builds homes from a hand list", and record the kill.
Lesson: zz-test/pin-call-site-arguments

### F3 [low] Four places still state the round-001 rule (per entry, from disk)
Where / Evidence: `git grep -nE "entry's own text|existence check|one reading per entry"` (prep 3524a78d; prototype 83f41f9c `z-nile/tests z-nile/skills`):
```
c0141.md:50   … per Touched entry, one fold and at most two existence checks …        (Scalability: there are no existence checks now)
c0141.md:102  AC1: … read one way chosen from the entry's own text …                   (the rule is the document's)
c0141.md:115  3. Add `repoPath`, `owned` (one reading per entry) …                     (an executor may build N5)
check.sh:12   check "AC1: … read one way chosen from the entry's own text …"           (the sequestered label)
proto checkpaths.luau:6  -- … read one way chosen from the entry's own text (`owned`) …
```
Critique / Consequences: the Design is right, but AC1's label and step 3 are what an executor reads first, and step 3 points at the killed mutant N5. Fixing check.sh now, in prep, is allowed (it is not yet sequestered against an execution).
Recommendation: reword all five to "one convention per document, from its text", and Scalability to "no file system access per entry".
Lesson: z-design/restated-rules-move-together

Lessons added since round 002: z-design/readings-from-text-not-disk is a lesson another raft could fail (a reading taken from disk), not a restated finding. The note on zz-test/moved-rules-pin-the-old-caller is a fair generalisation. Both fine.

Candidate lessons (for the lead):
- zz-test: a rule stated as "any element decides" needs a case where the deciding element is first and one where it is last, or a loop that overwrites instead of accumulating passes; check: for each any/all rule, is the deciding element placed both first and last in some case?
- zz-test: a mutant counted as killed must be killed where the value is built, not at a function that takes the value as a parameter; check: for each "comes from X" rule, does a case go through the caller that reads X?

Verdict: changes
