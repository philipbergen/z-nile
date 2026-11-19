# Review 004: c0194 (design mode)
Inputs: prep worktree `prep-temp-trees-under-repo` at 7871c2f9 with the uncommitted `c0194.md`, `check.sh`, `acceptance/{tmp,shim,runner,callers,docs}.spec.luau` (byte-identical to the prototype's `z-nile/tests/acceptance/c0194/`, `cmp`), `harvest.md`, `experiments/proposed-lessons.md`, `design-review-00{1,2,3}.md`, `design-refute-00{1,2,3}.md`; prototype `.worktree/proto-c0194` (base 02aae689, 17 modified and 6 untracked paths, read only); `./zn capture c0194` (capture 64239635, unmarked); `./zn lessons --skill zz-review --full`; `./zn lessons --when design`; the author's `scratchpad/c0194/{mut-clone.py,mut-clone.out,mut-clone2.out,e12c-main.out,guards.out}`.
Runs, all in my own jailed clone made the way the brief and zz-test say (`./zn tmp new unguarded` from the prototype, `--no-hardlinks` clone, origin removed, the prototype's uncommitted files rsynced in and committed as `x@example.invalid`, every command through `./zn tmp jail`, removed with `./zn tmp rm`): a write probe of the jail (F1); `runner.spec` baseline (8 passed, 1 failed: the `needJail` case); my mutants P1 (the author's), W1, R1 and S1 (`scratchpad/c0194-review4/mut.py`, output `mut.out`), which print every FAIL line. The tripwire did not fire. Overrides and Affected specs were not re-run: the Touched list is unchanged since round 3, which checked them.
Dropped from design-review-003 (fixed; change, case and mutant checked): F1 (user decision "Make them work jailed"; the clone's runner is accepted and nested runs pass, my baseline agrees with E12c), F2 (no guess is pinned; `docs.spec` pins only what holds), F3 (`tmp.spec :: the jail command runs in the tree …` runs the real command line with a stand-in `sandbox-exec`; N4–N6), F4 (N8–N10, N13), F5 (`tmp.STARTED` equals `fence.STARTED`; my S1, which ignores the recorded start id, is killed by `a tree whose recorded owner is alive survives a sweep …`; one residue in F5 below), F6 (zz-test's procedure copies and commits the prototype's files; it ran as written), F7 (`tmp.homesOf` feeds the sweep; N8), F8 (`rm ""`/`verify <missing>` refuse with a message; N15; Merging says `$dir` does not survive between Bash calls).

Scope: the title, Problem and Solution are the capture's plus three `Decided with the user (2026-11-01)` lines. Every captured outcome has a Design and a criterion. The Decided line "Make them work jailed" is carried out except for the property it states in parentheses (F1).

### F1 [high] The clone's jail lets the command create and write `.cache` folders inside the clone's sources and git directory, though the user's decision says it may not, and the sequestered spec pins the loose rule
Where: `tmp.jailProfile` (`(allow file-write* (regex #"^<tree>/(.*/)?\.cache(/.*)?$"))`, with the entry deny only at depth 1–2: `^<tree>/[^/]+(/[^/]+)?/\.cache$`); `acceptance/tmp.spec.luau` "the jail profile is the spec jail's rule set for the clone …" (asserts that exact regex text and `allows == 5`); the Problem's Decided line ("it writes `/dev`, its `TMPDIR` and the clone's `.cache` folders, not its sources or git directory"); zz-test "Running specs against unguarded code" ("never the clone's sources or git directory"), pinned by `docs.spec` ("is the spec jail's rule set applied to the clone"); AC1.
Evidence: In my clone I ran `./zn tmp jail "$tree" -- sh -c '…'` with a write probe:
```
write denied repo/zn.probe
write denied repo/.git/probe
mkdir denied repo/scripts/.cache
MKDIR OK  repo/z-nile/tests/lib/.cache
WRITE OK  repo/z-nile/tests/lib/.cache/f
MKDIR OK  repo/.git/hooks/.cache
WRITE OK  repo/.git/hooks/.cache/f
mkdir denied repo/z-nile/lib/x/.cache
WRITE OK  repo/.cache/probe
WRITE OK  repo/pickman/.cache/probe
```
Any existing folder three or more levels into the tree (`z-nile/tests/lib`, `.git/hooks`, `.git/refs`, `.git/objects`, …) can get a `.cache` child with any contents. The live spec jail allows only the home's `.cache` (`fence.profileFor`), so a spec, fixture or guard prototype that writes such a path passes in the jailed clone and fails only in the raft's gate. The real repository is not reached: every probe stayed inside the tree.
Critique: The regex exists for "a nested fixture's own `.cache` too". But every fixture lives inside a home's `.cache`, which a subpath allow already covers. The rule is a name pattern over paths the command can create itself, so it opens every place the name can be made. The obvious fix is to tighten the regex's depth. That still leaves a pattern, and `tmp.spec` pins its text, so any correct rule fails the sequestered spec.
Consequences: The exact rule needs the list of folders it allows. `prepareCaches` already computes that list (the root's `.cache` and each home's), so the profile takes it: `tmp.jailProfile(tree, resolved, caches)`. That means `jail` calls `prepareCaches` before it builds the profile (today it builds the plan first). A `.cache` made later inside the jail, such as a home that did not exist at start, is not writable. That is the spec jail's rule too.
Recommendation:
- The profile allows `<tree>/.jail-tmp` and, for each folder `prepareCaches` returns, `(subpath <cache>)`, written and resolved. Then it denies `(literal <cache>)` and a symlink at the top of each. No regex over `.cache` names.
- Amend `tmp.spec`'s case to assert the subpath rules for a given list and that no `regex` allow is present, with mutant "the name regex back" (killed).
- Add a jailed probe to E12c, in the clone outside the spec jail: `mkdir repo/z-nile/tests/lib/.cache` and `mkdir repo/.git/hooks/.cache` are refused, and `repo/z-nile/.cache/fx/.cache/f` is allowed (a nested fixture). Re-run E12c's two runs.
- Correct the Rules row (N2 becomes "a nested fixture's `.cache` is writable").
Lesson: z-design/spec-design-correspondence, zz-test/narrow-guard-allowances

### F2 [medium] The Design says three different things about where the live-jail cases and their mutant run, and keeps a "need" for mutated guard code in a worktree that the pure case has already removed
Where: Design, "Making the nested runs work jailed" ("Those two cases … run only where the runner can jail itself: the raft's own gate"; "the two live-jail cases stay in the regression list (AC6)"); Unknowns, "Where the earlier mutation runs ran" ("the two live-jail cases and their mutants (M20) are the only ones that need the worktree"); Rules row "the live spec jail closes the rest of `.tmp`" ("run in the prototype worktree under its own spec jail …; in the raft they run in its own gate"); the Problem's Decided line ("from now on guard-prototype cases run in the jailed clone").
Evidence:
- **Where they run.** Line 130 says the raft's own gate only. Line 223 says M20 "need[s] the worktree", in the present tense, so a later round of this prep would run it there. Row 320 records the worktree.
- **AC6.** `runner.spec` is AC3's spec, not in AC6's list (`check.sh` AC6 names `repo-fence.spec` only), so "stay in the regression list (AC6)" is half true.
- **M20 is P1.** M20 drops the `.tmp` deny. Since round 4 that rule is emitted by `fence.profileFor`, so M20 is the same edit as P1. My P1 run in the jailed clone: `7 passed, 2 failed`, the extra failure being `runner.spec :: the spec jail lets a spec write the cache, minus .tmp, plus the run's own folder, in that order`. So no mutant needs the worktree any more.
- **Are the rules pinned elsewhere?** The rules' text and order are pinned (P1–P3 killed). The wiring is not: my W1, `profile` passing the cache as the run folder (`fence.profileFor(cache, resolved(cache), cache, resolved(cache))`, which reopens all of `.tmp`), gives `8 passed, 1 failed` in the clone, the needJail failure only. It survives everywhere except the live cases. Nothing in the Design says that the live cases are what pin `fence.enter`'s call of `profile`.
Critique: Saying a guard mutant "needs the worktree" endorses running mutated guard code live in a worktree of the real repository, the risk the user's two decisions removed. The lead's decision (live cases run unmutated in the raft's own gate) is sound, but the document does not state it once.
Consequences: Once the worktree is gone from the record, a later guard prep has no sanctioned place for a mutant of the jail's wiring. It needs to know that such a mutant is judged by reading, and that the live cases catch a wiring defect in the raft gate.
Recommendation:
- One statement, repeated identically in the Design, Unknowns and the Rules row: M20 is P1, killed in the jailed clone by the pure case. The live-jail cases ran unmutated in the prototype worktree in round 1 (E5) and run in the raft's own gate. No mutant runs in a worktree.
- A Rules row for "`fence.enter` hands `profile` its own `.cache` and run folder": mutant W1, `reasoned` (killed only by the live cases, which run in the raft gate).
- Fix "AC6" to "AC3 and AC6".
Lesson: z-design/restated-rules-move-together

### F3 [low] The round-4 mutation record cannot tell a kill from the baseline failure for `runner.spec`
Where: `scratchpad/c0194/mut-clone.py` (`'KILLED' if fails`: any `FAIL` line); `mut-clone2.out` P1–P3 (each prints the needJail case as its failure); Rules preamble and rows P1–P3.
Evidence: In the jailed clone, `runner.spec`'s baseline is `8 passed, 1 failed` (the `needJail` case). So every mutant run against it prints a FAIL line, and the script calls every one KILLED. P1–P3 show `7 passed, 2 failed`, so something more did fail: my P1 rerun names the pure case. But a survivor is recorded the same way: W1 (F2) gives `8 passed, 1 failed` and `mut-clone.py` would print `W1 KILLED`.
Recommendation: Judge each mutant against the baseline's failing set: a kill is a FAIL that is not in it. Record the case that killed each row (P1–P3: the `profileFor` case). Re-run P2 and P3 with that criterion.
Lesson: z-design/spec-design-correspondence

### F4 [low] Restatements left from the first jail and the first runner message
Where and evidence (each a sentence the round-4 change made untrue):
- Design, `jail` bullet (line 104): "may write that tree and `/dev`". Line 129: "it may write the clone and `/dev` only". Rules row "the jail profile allows the tree and `/dev` only (F2)". Row "the jail really contains the command", whose evidence is E12 on the whole-tree profile. All four describe the first jail.
- Design line 104 and line 130, and the comment in `tmp.spec`: "adds the tree's `.cache` to `GIT_CEILING_DIRECTORIES`". The code and the assertion add the checkout's `.cache` that holds `.tmp` (`GIT_CEILING_DIRECTORIES=/x/.cache:{co}/.cache`).
- zz-test ("The clone's runner takes the tree for a fixture of this checkout (`this is a fixture of a guarded checkout`)"), zz-rules' table row and the Decided line say the runner prints that note. My run and the author's `e12c-main.out` both print `note: not jailed (already inside a sandbox, and macOS can't nest them); the outer sandbox protects the repository`. An agent told to expect one message sees the other.
- Cleanup: "agents remove their trees (`rm -rf "$dir"`)". AGENTS.md and the Landing step say `./zn tmp rm <tree>`. The harness refuses a bare `rm -rf` of a variable.
Recommendation: Rewrite each to the round-4 behaviour (after F1's fix), and quote the note the runner actually prints. `docs.spec` needs no new pin for the message.
Lesson: z-design/restated-rules-move-together

### F5 [low] `tmp.startOf` reads "cannot read" as "no such process", unlike the runner's reader of the same record
Where: `tmp.startOf` (returns `trim(r.stdout)`, so `""` whenever perl exits non-zero); `fence.startOf` (returns nil for a failed read, and `fence.holds` then keeps the owner); Design, Cleanup ("A start record that cannot be read at all (no perl) takes the owner as alive").
Evidence: By reading. The perl snippet exits 1 both for "no such process" and for a platform it does not know or a failed `sysctl`/`/proc` read. `tmp.sweep` takes `""` as dead, and the runner's clearing takes the same failure as holding. The `tmp.spec` case pins `tmp.startOf("99998") == ""` and equality with `fence.startOf(pid) or ""` only for a live pid. So the two readers of one format still disagree on the failure path, which is the path a guard has to get right.
Recommendation: Make the snippet tell the two apart (for example exit 2 for "cannot read"), have `tmp.startOf` return nil for that exit, and add a `tmp.spec` row with a stand-in `perl` that exits 2, so the sweep keeps the tree.
Lesson: zz-arch/one-reader-per-format, zz-arch/guard-no-is-explicit

Candidate lesson (for the lead; I write none): **A jail's allow rule names the folders it opens, never a pattern over names the jailed command can create.** c0194's clone jail allowed `(.*/)?\.cache(/.*)?`, so any folder in the clone's sources or git directory could gain a writable `.cache` child. Check: can the jailed command create a path that one of the profile's allow rules matches?

Verdict: changes
