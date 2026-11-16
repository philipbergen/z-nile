# Review 002: R0072 (code mode)
Inputs: origin/main b50c4b56 after `./zn sync --fetch` (no merge). Layer 1 (c0192): `git diff origin/main...R0072/1/c0192` at 3d18bcd8. Layer 2 (c0193): `git diff R0072/1/c0192...R0072/2/c0193` at a580447d (= HEAD = origin/R0072/2/c0193). Documents: `R0072.md`, `refute-001.md`, `review-001.md`, `c0192.md` and its `check.sh`, `c0193.md`, its `check.sh` and `acceptance/`.

What I ran:
- `./zn check c0192`: 5/5 pass. `./zn check c0193`: 9/9 pass.
- `z-nile/check.sh --affected`: GATE PASSED. Format clean. selene: 0 errors, 0 warnings, 0 parse errors. Types: no diagnostics. `skills --check`: ok. 221 passed, 0 failed in 33 spec files (pickman and the other homes: no specs affected). Slowest were the sequestered `finishes.spec` at 9.3 s and `scanners.spec` at 3.0 s. No `REPOSITORY CHANGED`.
- `lune run tests/run --` with `tests/tooling/repo-fence.spec.luau` (10/10), `tests/meta/architecture.spec.luau` (2/2) and `tests/acceptance/c0077/cache-paths.spec.luau` (4/4). The affected run did not select these, and they cover the new files.
- Sequestration (`git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'`): one entry, `A z-nile/.tracker/issues/active/c0193/acceptance/watch.txt`. Its five paths are exactly layer 2's changed source files (`engine/scan.luau`, `tests/lib/{hostile,loops,scanners}.luau`, `tests/slow.tsv`). zz-test, Affected selection, Capture, says `./zn finish` is that file's only writer. No `check.sh` or acceptance spec changed, so this is not a finding (but see F6). The same diff for layer 1 lists nothing.
- Probes, each through `./zn run --time 30|60 --`, with scratch files under `z-nile/.cache/rev2-r0072/` (now removed):
  - `loops.find`, `loops.problems` and stylua (`--config-path stylua.toml`) on the shapes quoted below.
  - A patched copy of `loops.luau` over the real tree: 119 covered files, 82 loops, 5 proven, 77 listed.
  - Every text-reading loop listed with `sweep = false` (21), read against its `why`.
- `lune run z-nile/affected --` for each file the c0192 meta case reads or calls.
- `gh pr view 329` (read only): F6's count is in the PR text.
- Lessons searched: `loops`, `comment`, `watch`, `guard-no-is-explicit`, `specs-read-sources-through-the-selector`, `hand-written-parsers-advance-or-refuse`.

Refutation 001 against the code:
- F1, partly true. `assigns` (`z-nile/tests/lib/loops.luau:70`) now catches every compound operator and typed `local`/`for`. Comparisons do not count. `t[i] = i` is not a write, and the sequestered `loops.spec` :187 pins that (not `loops-writes.spec`, which the log names). But "recognizes every … assignment" is not true: see F1 below.
- F2, true. `slow.tsv` lists both promoted paths. `slow-tier.spec` accepts a sequestered copy and counts 101. The sequestered files are unchanged. This is the owner's ruling.
- F3, true. The wildcard lines are gone, and c0310 is captured with the right scope (it names c0192's meta case too). The deviation's wording about which gate runs the checks is wrong: see F4.
- F4, partly true. An unfound end now reads as `scansText = true` (:144). The same hole is still open through the one-line test: see F2.
- F5, true. Both `trace` reasons now name their literal needles.
- F6, true. 33 + 2 + 15 + 18 + 2 + 3 + 4 = 77, the probe found 77 listed loops, and the PR text carries the count.

### F1 [high] loops.find still proves loops that reset their variable or rewrite their bound, when stylua wraps the value onto the next line
Where: z-nile/tests/lib/loops.luau:71 (`assigns`: `string.match(line, "^%s*(.-)[^=~<>]=([^=])")`) and :88 (`writes`: `string.match(after, "^[^=]-[%+%-]?=[^=]")`).
Evidence: Both patterns need a character after the `=`. Stylua (the gate's formatter, this repo's `stylua.toml`) puts a value that does not fit in 110 columns on the next line and leaves `X =` at the end of the line. 50 lines in the covered non-spec files end that way today, 17 of them reassignments (`engine.STATE =`, `boardview.WINDOWS =`, `loops.SKIP =`). I ran this text through stylua, which left it as shown, and then through `loops.find`:
```
	while i < n do
		i += 1
		if state.reset then
			i =
				state.currentDocument.currentSection.currentParagraph.currentSentence.currentWordWithinSentence.startingCharacterIndex
		end
	end
	while i <= #items do
		i += 1
		if state.reset then
			items =
				state.previousDocument.previousSection.previousParagraph.previousSentenceTokens.withEveryWordStillInIt
		end
	end
```
Both loops come back `advances=true`. In the first, the branch resets `i`, so the loop can step back on every pass. In the second, the body rewrites the bound. AC4 asks for both of these: "nothing else in the body resets or steps back that variable, the bound is a number, a name or `#name` that the body never writes". So a proven loop needs no entry and no reviewer ever reads it, which is review 001 F1's failure again. The lesson this raft added names the rule: "An unrecognized form must count as a write, never as proof." Neither the sequestered `loops.spec` nor `loops-writes.spec` has a wrapped assignment, so `check.sh` passes this implementation.
Critique: The tempting fix is a third pattern for "`=` at the end of the line". That adds one more hand-picked form, and the same gap stays in `writes`, which checks the bound with its own pattern.
Consequences: Treating a line-final operator as an assignment can only void proofs. That is the safe direction. Nothing in today's tree turns red: I ran a copy of `loops.luau` with both matches made on `line .. " "` and `after .. " "` over the real tree, and it reported 0 problems, with the 5 proven loops still proven. The sequestered `t[i] = i` case and a wrapped `local x =` that names neither V nor B both stay proven. Stylua never starts or ends a line with `==`, so a comparison does not become a write. A step written over two lines (`i =` with `scan.advance(i, next)` below) becomes an unproven, listed loop. Design rule 3's wording ("a line that starts with a list of names ending in `=`") needs the same recorded deviation as review 001 F1's widening.
Recommendation:
- Make one assignment reader, used by both `assigns` and `writes`. It finds the first assignment operator on the line, and a line-final operator counts as one: match on `line .. " "`, or test `=%s*$` alike.
- Add cases to `z-nile/tests/tooling/loops-writes.spec.luau`. Its watch file is rewritten by `./zn finish`.
  - Must not prove: a reset `i =` with a value on the next line inside an `if`. A compound `i +=` with its value on the next line. A bound `items =` with its value on the next line.
  - Must still prove: a wrapped `local x =` that names neither V nor B, and `i += 1` alone.
  - These cases kill both "the old pattern" mutants and an "every line-final `=` writes everything" mutant.
- Add a note to `zz-arch/assignment-forms-void-proofs` and to the F1 deviation in c0193.md: the formatter's wrapped form is an assignment form too.
- Rerun the meta case. The 5 proven loops must stay proven.
Lesson: zz-arch/assignment-forms-void-proofs

### F2 [medium] A loop header whose trailing comment ends in "end" reads as a one-line loop, so its body is never read and a text-reading loop needs no sweep
Where: z-nile/tests/lib/loops.luau:142 (`local oneLine = string.match(rest, " end$") ~= nil`), then :143-144 and :149.
Evidence: `loops.find` on `while i <= #text do -- read to the end` / `local c = string.sub(text, i, i)` / `i = g(text, i)` / `end` gives `advances=false scansText=false`, and `loops.problems` accepts an entry with a reason and no `sweep` (0 problems). The same loop with the comment `-- read on` gives `scansText=true`, and the problem "reads text: its entry names the scanners case that sweeps it". `repeat -- scan up to the end` behaves the same way. Stylua keeps trailing comments and always expands a real one-line loop: I ran stylua on `while i < 3 do i += 1 end` and it split it over three lines. So in formatted code, `oneLine == true` happens only through this misreading. Review 001 F4 closed one way for a text-reading loop to skip its sweep (an end not found). The `oneLine` test is a second way to skip the end search. AC4 says "its end is found by structure", and AC5 says "a loop that reads text to name its sweep". No header in today's tree ends in ` end`, so nothing is red now.
Critique: Making every one-line loop read as text would break the sequestered `loops.spec` :143-149, which requires `while i <= n do i += 1 end` to stay `scansText = false`. That spec cannot change.
Consequences: Strip a trailing `--` comment from the header before the ` end$` test. The safe direction then holds even when the strip cuts at a `--` inside a string (`while args[1] == "--" do`, `z-nile/specs.luau:37`): the header just stops looking like a one-liner, `endOf` runs, and an end it cannot find reads as text (:144). A real one-liner with a `--` string fails closed the same way. The sequestered one-liner has no `--`, so it is unchanged. The `while V op B do$` proof pattern already refuses a header with a comment, so no proof changes.
Recommendation:
- Decide `oneLine` on the header with `%s+%-%-.*$` removed.
- Add cases to `loops-writes.spec`:
  - The `-- read to the end` header and the `repeat -- … end` header, each with `string.sub` in the body. Both must report `scansText = true`, and `problems` must ask for a sweep.
  - A loop whose end is not found and that makes no text call anywhere (only a column-0 long string in its body). It must still report `scansText = true`. Today's F4 case has `string.sub` in its body, so a mutant that reads to the end of the file for text calls still passes it.
- Record the fix beside F4's in c0193.md.
Lesson: zz-test/source-text-pins-read-the-code

### F3 [medium] `sweep = true` satisfies "a loop that reads text names its sweep" without naming one
Where: z-nile/tests/lib/loops.luau:17 (`sweep: (string | boolean)?`) and :232-246 (only `nil` and an unknown or foreign string are refused).
Evidence: `loops.problems("fixture.luau", <a loop with string.sub in its body>, { { loop = <header>, why = "the helper advances, reviewed", sweep = true } }, {})` returns 0 problems, the same as `sweep = false`. The type allows `true`, and the `:: { [string]: { Allowed } }` cast at the end of `ALLOWED` accepts it. The Design ("What the list holds") allows only `sweep = "<scanners case name>"` or `sweep = false` with a reason. AC5 requires "a loop that reads text to name its sweep". So an entry that names no case and gives no reason why none is needed passes the lint. The sequestered `problems.spec` has no `true` case. No entry uses `true` today.
Critique: Changing only the type to `(string | false)?` does not hold: a cast accepts the wider `boolean`, and the lint has to refuse the value at run time.
Consequences: `true` gets refused with the file, line, lesson and fix, like the other sweep problems. Nothing in the tree turns red.
Recommendation:
- In `loops.problems`, give a problem when `s ~= false and type(s) ~= "string"`. The message says the entry names a scanners case or `false`.
- Type the field as `(string | false)?`.
- Add a case to `loops-writes.spec`: `sweep = true` gives exactly one problem, and `sweep = false` with a reason gives none. Together these kill the "anything but nil" mutant.
Lesson: zz-arch/guard-no-is-explicit

### F4 [low] The records say the meta cases run at every merge's full gate, but a tooling pull request merges on `--affected`; c0192's six `inputs.tsv` lines are unread and left its meta case watching only `inputs.tsv`
Where:
- c0193.md:294 (F3 deviation: "these checks run in every merge's `--full`").
- c0192.md:40 (Design 6: "runs in **every full gate** (`land`, the merge gate of zz-rules, CI …)").
- z-nile/tests/inputs.tsv:299-304.
- z-nile/tests/meta/bound-every-probe.watch.txt.
Evidence:
- zz-rules, Merging step 2: "A pull request that changes only tooling … is gated by `z-nile/check.sh --affected` on the branch". zz-test, Gate by step: `land` runs `--static`, and GitHub Actions does not run the specs.
- `lune run z-nile/affected --` lists neither `tests/meta/bound-every-probe.spec.luau` nor `tests/meta/scanning-loops.spec.luau` for `z-nile/engine/boundcmd.luau`, `reap.luau`, `z-nile/lib/bounded.pl`, `scripts/hooks/pre-bash.sh`, the lesson or `AGENTS.md`. Only a change to `z-nile/tests/inputs.tsv` selects them.
- `context.load` hands the selector `inputs = {}` (`z-nile/lib/context.luau:52`), so c0192's six lines select nothing.
- They were the layer's only source change, so `./zn finish` wrote `inputs.tsv` as the meta case's whole watch. Without them, the watch would have been what the case requires (`boundcmd.luau`).
- A tooling branch that adds an unlisted loop or edits the AGENTS.md sentence merges green. It goes red only in watch-net, after the merge.
Recommendation:
- In c0193.md's F3 deviation and in a c0192 Verification log line, say where the checks really run: every `--full` (setup.sh, a game pull request's clean-clone merge) and watch-net after every merge. A tooling pull request's merge selects them only when a watched helper changes. Cite zz-rules Merging step 2 and c0310.
- Put a `#` comment above c0192's six `inputs.tsv` lines saying the selector does not read them (c0310). Or drop them.
- No spec case: this changes records only.
Lesson: zz-test/specs-read-sources-through-the-selector

### F5 [low] An existing lesson still tells c0193's executor to merge it into the new lesson; that did not happen, so after `done` the sentence is false
Where: z-nile/skills/zz-test/lessons/hand-written-parsers-advance-or-refuse.md:13 ("See also c0193 … its executor merges the two into one lesson").
Evidence:
- That lesson landed with R0052 (#125, e8c832ff) after c0193's prep, and c0193's Implementation step 1 has the executor read `--skill zz-test --full`.
- Nothing in c0193.md, the raft or `harvest.md` mentions it, and both lessons now exist and are both listed for design and build.
- Once c0193 is done, the line points readers at work no item holds.
Recommendation:
- The lead rewrites the line to point at the landed `zz-arch/scanning-loops-advance` (its Enforced by files are the general check), and leaves merging overlapping lessons to c0181's consolidation, which c0193's Non-goals name.
- Don't delete or rename either lesson: R0052's `harvest.md` names this one, and `./zn lessons --check` reads it.

### F6 [low] The new lesson zz-review/finish-watch-is-generated contradicts zz-review code mode item 2, which still says any change other than an R100 rename is high
Where: z-nile/skills/zz-review/lessons/finish-watch-is-generated.md; z-nile/skills/zz-review/SKILL.md:106.
Evidence: The lesson says "The sequestration diff permits `acceptance/watch.txt` as an addition". The skill says the diff "must list nothing except `R100` renames … Any other change is **high**". A reviewer who follows the skill marks every finished layer high, and one who follows the lesson does not. Review 001's candidate asked for the exception to go into item 2 itself. A lesson cannot change a rule that its skill still states.
Recommendation: The lead captures an issue (`./zn new issue c … --project z-nile`) to name `acceptance/watch.txt`, written by `./zn finish`, as the one allowed addition in zz-review code mode item 2 (and in zz-test's Sequestered bullet, which restates it). The lesson then points at that rule. zz-review/SKILL.md is outside this raft's Touched modules.

## Judged criteria (code mode only)
- None: both c0192 and c0193 have `### Judged` None, so there is nothing to rule on.

## Lesson candidates (for the lead)
- F1, a note on zz-arch/assignment-forms-void-proofs: "The formatter's wrapped form is an assignment too: an operator at the end of a line with its value on the next line. Stylua writes it for any value too long to break." Check: does the matcher read `x =` with nothing after it as a write?
- F2, a note on zz-test/source-text-pins-read-the-code: "A line lint strips the trailing comment before it decides a line's shape by its last word (` end$`, `do$`)." Check: what does the lint decide for this header with a comment ending in the word it looks for?

Verdict: changes
