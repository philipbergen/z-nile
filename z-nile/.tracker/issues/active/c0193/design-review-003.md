# Review 003: c0193 (design mode)
Inputs: prep worktree HEAD 7871c2f9 with the uncommitted `c0193.md`, `check.sh`, `acceptance/*.spec.luau`, `prototype.patch`, design-review-001/002, design-refute-001/002 and `harvest.md`; `./zn capture c0193` (capture 6495f5f3); origin/main 7e1b5ee8 (since 7871c2f9 it changes, in covered paths, only `z-nile/tests/lib/deploylist.luau`, which has no loop, and leaves zz-arch and zz-test unchanged); c0191's reference runner `ref-bounded.pl.txt` and its `ref-boundcmd`, `ref-reap`, `ref-guard-bash` and `ref-main-luau.diff` (`.worktree/prep-no-leaked-processes`, de3ad691); c0181 as it stands now (`.worktree/prep-lessons-codify-consolidate`, 6d9318e5 plus its uncommitted `c0181.md`, which is `design: ready`, `status: prepared-…`); every `origin/*` branch.
All runs were in a throwaway clone with `prototype.patch` applied and the reference runner at `z-nile/lib/bounded.pl`. Every lune process ran under `perl z-nile/lib/bounded.pl --time N --`. Unmutated: scan 5, texts 7, loops 19, problems 9, tree 4, docs 2, finishes 11 (4.3 s wall), scanners 5 (1.5 s). Each of finishes and scanners ran once. The specs that read the edited skills or lessons also passed: c0111/lesson-format, c0115/lessons, c0114/docs, c0120/docs, c0081/skill-doc, c0115/absence, docs and layout, c0127/skill, c0077/cache-paths and tooling/repo-fence. `tests/meta/architecture` failed only on my own scratch scripts, which I then deleted. AC9's command passes with the executor's harvest note added: `sources: c0193 note raftcheck word() spun …`. I left no process behind (`ps` shows only another session's `c0156/kills.luau`).
Dropped from design-review-002: F2 and F3. The second runner is gone, and `hostile.bounded` is one call of c0191's runner, which refuses `--time` outside 1..3600. F4 is answered: rule 9 states the limit, and text-reading loops are never proven. The probes below found no new false proof. F6, F8, F9 and F10 are fixed. F7's wording is fixed. F1's witness and its per-loop mutation check hold (re-run below). F5's c0191 row was added, but its search misses loops in diff form (F3 below).

Re-run of the round-2 fixes:
- **Witness rule.** I made each swept loop stop advancing, then ran its case alone through `hostile.finishes(…, scanners.texts(), 3)`. Every one of the ten mutants failed:
  - graph `:347`, `:350`, `:357`, `:361`, `:365` and `:370`;
  - ids `:149`;
  - paths `:66`, `:83` and `:86`;
  - skills `:377` and `:430`.

  I ran the same ten again with the witness removed, to see whether `scanners.texts()` reaches the loops by itself. All ten failed again. The stopping blocks were 193..208, 52449..52464, 33..48, 1..16, 225..240, 73953..73968, 73985..74000 and 74113..74128. So the texts reach every listed loop, not only the witnesses.
- **Stricter lint.** On the prototype tree it covers 73 files, finds 38 loops and proves 3 (`affected.luau:147`, `stats.luau:169`, `run.luau:199`). It has 35 entries: main's 33, plus hostile's and loops.luau's own. 19 loops read text. Main has 67 covered files (`git ls-files` with the design's filters), so **36 loops, 3 proven and 33 listed is right**.
- **Existing work.** I ran the prototype lint over every `origin/*` branch's added or changed covered files. The table is not right (F3).
- **check.sh.** The pins hold (AC7's six names, AC9's lesson checks).

Scope: the captured Problem is kept verbatim. The lesson keeps the rule and the check question ("leave its position where it was" for "leave the index where it was") and adds to them. Nothing has moved into Non-goals. The c0181 question ("which part can be a check") gets a real answer: a lint, a sweep and a fail-closed step. The captured outcome is delivered whole.

On the machinery:
- **The sweep is sound now and is the part that earns its keep.** Every listed loop's sweep fails when that loop stops advancing.
- **The fail-closed step** costs 16 lines.
- **The lint is fail-closed under its stated limit.** But its proof proves 3 of 36 loops, and both earlier rounds' holes were in that proof (F6).
- **Nothing should go to c0191.** Its runner is already reused.
- **Two seams remain.** The standing check behind `sweep = "<case>"` is weaker than the one-off prep check (F1). The c0181-first branch would make the executor's gate red (F2).

### F1 [medium] A `sweep` entry is checked only for naming some case that exists, so a loop can claim any other file's sweep. `sweep = false` is open to every text loop, including the design's own new text walker and c0191's tokenizer
Where: `prototype.patch` `loops.problems` (`type(s) == "string" and not sweeps[s]`); `acceptance/tree.spec.luau:60-72`; `loops.ALLOWED["z-nile/tests/lib/loops.luau"]` (`sweep = false`); Design "What the list holds" (sweep = false only for "not callable, shrinking path, a literal needle"); Chore checklist, Existing work, c0191 row ("adds a `boundcmd` case … and sweeps it").
Evidence:
- **Wrong case accepted.** In the clone I changed both `paths.luau` entries to `sweep = "skills.oldNames"`, and `lease.luau`'s `redact` entry (a local function) to `sweep = "ids.rewrite"`. `tree.spec` passed, 4 of 4. Nothing ties a case to the file that holds the loop. E14's per-loop mutation check ran once, in prep. The standing gate re-checks only that the name exists.
- **The class this applies to.** This is the hole round 2's F1 found, "the reviewed list claims a sweep that tests nothing". It now applies to every future entry: a sibling raft listing its 16 loops, or this raft's executor listing c0191's 7 text-reading `boundcmd.luau` loops, can name any existing case.
- **The design's own walker.** `loops.find(text)` is a public function that walks arbitrary file text. Its text-reading loop (`writes()`'s `while at do`) is listed `sweep = false`, which the design's own criteria do not allow: it is callable, and the needle is not a literal.
- **c0191's tokenizer.** The design promises a `boundcmd` case with a witness. No check asks for one: AC7 pins six names, and tree.spec's conditional case covers only `raftcheck`. `boundcmd.check(command)` is a quote and backslash tokenizer. It is the incident's own class, and c0191 runs it as a PreToolUse hook on every Bash call.

Critique: the lesson's value depends on the next scanner being swept. The lint routes text loops to a sweep, but the field it routes them through accepts any name. The tempting fix is "the reviewer reads it". That is what already failed in round 2, when `paths.rewrite`'s entry named a case that never reached its loops.
Consequences:
- Tying a case to a file needs one mapping from a case's `module` alias to a repository path: `@znile/` to `z-nile/`, `@tests/` to `z-nile/tests/`, `@scripts/` to `scripts/`. An alias it can't map is a problem (fail closed).
- `loops.problems` then takes `sweeps: { [name]: file }` in place of a set.
- A loop in a local helper whose public scanner lives in another file is the only legitimate mismatch. None exists today: all seven sweep entries are in their case's own module.
- A conditional rule for `boundcmd` (and `raftcheck`) is a check of today's tree, like the existing raftcheck case.
Recommendation:
1. `loops.problems` reports `<file>:<line>: its entry names the scanners case "<s>", whose module is <other file>`. Add a problems.spec case for it, and a mutant row "module unchecked".
2. In tree.spec, generalise the raftcheck case: for each covered file that `scanners.luau` must sweep, a case exists whose module is that file. The files are `z-nile/engine/raftcheck.luau` and `z-nile/engine/boundcmd.luau`, each only once it exists. Alternatively, put the `boundcmd` requirement in check.sh's AC7 line, since c0191 lands first by `depends_on`. That is a claim about the tree on the day c0193 executes, so check.sh is the right place (zz-review/recommendations-pick-spec-or-check).
3. Either add a `loops.find` case to `scanners.luau` (a witness such as `while i <= n do\n\ti += 1\nend`, with the result its loop count), or narrow the design's `sweep = false` criteria to what the entry actually says. Today the list and the criteria disagree.
Lesson: zz-test/no-vacuous-pass

### F2 [medium] The c0181-first branch of Non-goals can't be followed as written: c0181's policy runs in every gate and refuses a ref to a spec that `done` hasn't promoted yet, and the "move the lint to `z-nile/lints/`" clause conflicts with this issue's own promoted docs.spec
Where: Non-goals, c0181 bullet ("If c0181 lands first, the executor adds `enforced_by` … and moves the lint to a `z-nile/lints/` file if the policy requires it"); Implementation step 6; `acceptance/docs.spec.luau` (rule 9 must name `z-nile/tests/lib/loops.luau`); c0181.md (current) policy rules 2 and 3, "Gate", harvest `codify` line.
Evidence: c0181 is now `design: ready` and `prepared` in its worktree, and it has no `depends_on`. So c0181 landing first is a live branch. What c0181 says today:
- **Rule 1:** every lesson states `enforced_by` or `not_codifiable`.
- **Rule 3:** a spec ref must lie "under `<home>/tests/` … so a sequestered issue spec … is refused".
- **"Gate":** `z-nile/check.sh` starts `lessons (./zn lessons --check --policy)` **unconditionally**.
- **Harvest:** the item's harvest carries `- codify <id>: <ref> mutant: <what>`, which `--check --policy --item <id>` (zz-execute Phase 4 and 5) checks, refusing "a spec ref without `mutant:`".

c0193's deciding cases live in `.tracker/issues/c0193/acceptance/` until `./zn done` moves them to `tests/acceptance/c0193/`. So from step 6 (the lesson is written) to `done`, every gate fails one of two ways:
- the lesson names `z-nile/tests/acceptance/c0193/tree.spec.luau :: "[zz-arch/scanning-loops-advance] …"`, a file that doesn't exist yet;
- or the lesson has no state.

The design says neither of these, nor the `codify` line. The "move the lint to `z-nile/lints/`" clause has two problems. c0181's policy doesn't require a move, since a spec ref is a valid ref. And a move would break this issue's own promoted docs.spec, which requires rule 9 to name `z-nile/tests/lib/loops.luau`. The lesson body is 1,183 bytes against c0181's 1,200-byte cap for `part`, so there are 17 bytes of headroom.
Critique: an executor who meets a red policy stage mid-raft will improvise. The likely moves are a `not_codifiable` line, which is false, or a ref to the sequestered path, which the policy refuses. Executability (item 8) fails on a branch the design itself names. The gap is c0181's in general: any issue that codifies its own new lesson through its own acceptance spec meets it. But this design is the first to promise that path.
Consequences: whatever the executor writes before `done` is either a known red stage or a temporary state that `done` has to replace. Asking c0181 to accept "an item's sequestered spec, read at its promoted path" is a change to c0181's rule 3, which is a decision for c0181's lead, not this issue's.
Recommendation:
1. Rewrite the c0181-first branch concretely:
   - the lesson's `enforced_by` names the two promoted paths and case names (tree.spec "[…] has no loop…" and scanners.spec "[…] finishes…"), with `enforced: part`;
   - the harvest gets `- codify zz-arch/scanning-loops-advance: <ref> mutant: <SW1 / E5's graph mutant>`;
   - the body stays within 1,200 bytes;
   - step 6 runs right before `./zn done`, and the only gate between them is expected to report the two missing refs, until `done` promotes them (or: run the affected gate before step 6 and the full gate after `done`).
2. Drop "moves the lint to a `z-nile/lints/` file if the policy requires it". The policy accepts spec refs, and docs.spec pins the current path.
3. Send c0181's lead the gap, "an issue's own sequestered spec can't be its new lesson's ref until `done`", and record that it was sent. c0181 may answer it with a rule-3 exception for the item that wrote the lesson.
Lesson: z-design/quote-other-preps-before-promising

### F3 [low] The in-flight search misses loops added in diff form, and the Existing work counts were taken before the stricter lint
Where: Chore checklist, Existing work (table, and "the search was `grep -lE '^\s*(while|repeat)\b' …/experiments/*` plus every `prototype.patch`"); Design "scanners.texts()" and E5/Scalability ("74,197 texts").
Evidence:
- **The search pattern.** It can't match a `+\twhile` line in a patch or `.diff.txt`. The search I ran was:

  ```
  awk '/^\+\+\+ /{f=$2} /^\+[ \t]*(while|repeat)([ \t]|$)/{print f}'
  ```

  over every `.worktree/*/…/experiments/*.patch` and `*.diff.txt`. It finds three covered loops the table lacks:
  - c0191's `ref-main-luau.diff.txt` adds `while at ~= nil and at.ppid > 1 and #self < 64 do` to `z-nile/engine/main.luau`. With the diff applied, the prototype lint reports `main.luau:5676`, so c0191 has 11 loops, not 10.
  - c0157 (`prep-gate-contention`) adds `while true do` to `z-nile/tests/slot.luau`.
  - c0178 (`prep-shared-fixture-images`) adds a loop to `z-nile/tests/lib/images.luau`.

  The other hits are out of the lint's scope (`pickman/src`, `.pl`, `.py`, specs) or c0083's `classify.luau` under `.tracker/`.
- **The branch counts.** Re-run with today's lint over `git diff --name-only --diff-filter=AM origin/main...origin/<b>`:

  | branch | table says | today's lint |
  |---|---|---|
  | `impl-c0117` | 16 | **18** (`raftcheck.luau` 4: `:24` `head`, and `:51`, `:93`, `:113`; `wrapper.luau` 3) |
  | `impl-c0118` | 14 | **15** |
  | `impl-c0121` | 15 | **16** |

  The other rows hold (R0061 1, proto-c0144 2, proto-c0162 1, proto-merge-past-tracker-only 1).
- **The text count.** `scanners.texts()` returns **74,237** texts, not 74,197: the root-bearing needle added 40.

Recommendation: correct the table and the counts, and replace the pasted search with one that reads `+` lines of patches and diffs (the awk above, or the prototype lint run over each applied prototype). The gate names every missed loop at rebase anyway, so this costs notice, not correctness.
Lesson: zz-review/lists-paste-their-search, z-design/new-rules-migrate-existing-work

### F4 [low] A scanner that hangs on its witness is reported as stopping in "texts 1..15 of N", texts that never ran
Where: `prototype.patch` `hostile.luau` DRIVER (`at\t<case>\t0` before the witness) and `finishes` (`first = math.max(at, 1)`, `last = at + BLOCK - 1`).
Evidence: in the clone, with the witness kept, the mutants graph `:350`, ids `:149`, paths `:83` and skills `:430` hung on the witness. The message was `…: did not finish within 3 s; it stopped in texts 1..15 of 74237: "" "\\" "'" …`. The driver never reached text 1, and the block is 15 texts, not 16. The Design's Usability promises that a hang names the 16 texts to try.
Recommendation: when the last breadcrumb is index 0, say `<case>: did not finish within <n> s on its witness <%q text>`. Add a finishes.spec case (a fixture whose witness spins) and a Rules row ("a witness hang names the witness").

### F5 [low] Two promoted specs pin today's files and needles, not the rules
Where: `acceptance/tree.spec.luau:22-25` (`z-nile/engine/ids.luau`, `z-nile/lib/graph.luau`, `z-nile/tests/run.luau`, `pickman/scripts/lib/lease.luau` must be covered); `acceptance/scanners.spec.luau:59-60` (`set["z-nile/a\\"]`, `set["\\zz-test/pin"]`).
Evidence: if `lease.luau` is renamed, or `graph.luau` moves, the promoted tree.spec goes red, and so does scanners.spec if `"z-nile/a"` is dropped from the needles. That needle served the old `paths.rewrite` case and is unused since round 2 changed the case. Both are sets, so changing them needs an override chore.
Recommendation: pin the rule instead. For coverage: every root in `loops.ROOTS` that exists contributes a file, and the skips hold. For the needles: every needle in `scanners.luau` appears with each wider character on either side. That means exposing the needle list (`scanners.NEEDLES`) and checking it, rather than two literals. Move today's literal file list, if it's wanted, to check.sh's AC6 line.
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F6 [low] The lint's proof proves 3 of the 36 loops on main, and every hole found in rounds 1 and 2 was in it. Say why it is kept, or list every loop
Where: Design "What proven means" (six conditions); `loops.find` (`steps`, `assigns`, `writes`, `closesAtEnd`, `endOf`); about 20 Rules rows.
Evidence: on main, 33 of 36 loops are listed. The three proven loops are two argument loops and a queue walk. No engine code calls `scan.advance`. If every loop were listed, the lint would drop four helpers and most of AC4, and the list would grow by three entries. The lesson's rule would still be enforced the same way: every new loop passes a reviewer, and every text loop names a sweep. The one thing the proof buys is a route around the list for new code (`i = scan.advance(i, next)` at top level).
Recommendation: this is the author's call, and either way keeps the captured outcome. Either keep the proof and add one sentence to the Design weighing its yield (3 loops, plus the `scan.advance` route), or drop it, so that every `while`/`repeat` is listed. If it is dropped: AC4 shrinks to finding loops and telling text loops, the three proven loops get entries, the scan.advance spec cases stay with `scan.spec`, and rule 9 and the lesson drop "proven".

### F7 [low] AC8 claims a clause that docs.spec doesn't check, and refute 002 says the lesson's check states the proof limit, which it doesn't
Where: AC8 ("zz-arch states the rule (a text-reading loop is always listed and swept)"); `acceptance/docs.spec.luau`; design-refute-002 F4 ("Design, rule 9, the lesson's check question and AC4 say so"); the lesson's `check:` and AC4.
Evidence:
- docs.spec checks rule 9's heading, the four file names, `scan.advance` and the heading suffix. Deleting "a loop that reads text is never proven, always listed and swept" from rule 9 keeps it green.
- The prototype lesson's `check:` asks only whether a branch can leave the position, and whether a hostile input reaches it.
- AC4 ends "it fails closed on any other shape", with no "no write that the loop's own lines show". Only rule 9 and the Design state the limit.

Recommendation: either pin the clause in docs.spec (`has(rule, "a loop that reads text is never proven")`) or drop the parenthesis from AC8. Then correct the refute's claim, or add the limit to the lesson's check: "… (a write through a call, a closure or an alias is not in the loop's own lines)". The lesson's text is pinned by check.sh, so the extra clause costs nothing to the promoted specs.
Lesson: z-design/spec-design-correspondence

Lesson candidates (for the lead to place; I write no lesson file):
- A reviewed list whose field names a check (`sweep = "<case>"`) is verified against the thing it names, not just for existence. Check: could this entry name an unrelated check and still pass? (F1)
- A search for in-flight loops (or any added construct) reads the `+` lines of patches and diffs, not only whole files. Check: does my pattern match the form a diff writes, `+\t<code>`? (F3)

Verdict: changes
