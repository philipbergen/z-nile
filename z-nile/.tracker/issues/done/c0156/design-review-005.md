# Review 005: c0156 (design mode)
Inputs: prep worktree `prep-whole-file-pins-keep-newlines` at c5ab507a plus its uncommitted prep files (sha256 prefixes: `c0156.md` 869498cd, `check.sh` fec9224d). The prototype's `check.sh`, its six acceptance files and `experiments/mutants.py` are byte-identical to the worktree's (`cmp`), and its diff against 0d4323b4 equals `experiments/prototype.patch` apart from `check.sh`. I read `design-review-001..004.md`, `design-refute-001..004.md` and `harvest.md`, and printed `./zn capture c0156` (capture 3bf887d6). origin/main is now 973b7250 (48 commits past c5ab507a), and all eight base blobs the Design lists still match it (`git rev-parse --short=8 origin/main:<path>`: e7888cd8, 0187cfc4, c6e1b6c2, 4dcd3dd8, f77fe1a5, a7df96d8, 14e8f252, ed43a849).

Runs, all in the prototype `…/tmp.fipPiC5Jjp/proto` with `PICKMAN_FENCE_REAL_GIT` set and a time limit:
- `bash z-nile/.tracker/issues/c0156/check.sh`: `7/7 criteria passed`, 38.9 s.
- `kills.luau` alone: `all checks passed`, 28.5 s. It derived 52 mutants of f0014, 461 of f0024 and 1,256 of f0026, plus 4 from the record.
- `mutants.py … kills-shape-pin kills-no-in-place-mutants digest-recomputed-on-a-changed-file kills-globals-injected`: all four killed, `OK`, 103 s.
- The attack in F1. I saved `narrowed.spec.luau` and `f0014/keys.spec.luau` to my scratchpad and copied both back afterwards. `cmp` matches, `git diff --stat` of f0014 is empty, and `git status --short` is back to its 10 entries.

Scope. Every outcome in the capture, and in the `Decided with the user (2026-10-25)` line, has a Design and a Checked criterion:
- c0103's pin keeps line breaks: AC3, AC7.
- The digests are recomputed and pinned: AC2. c0128's digests are unchanged, by E2.
- A comment-join mutant is killed by each pin: AC3, AC7.
- One shared normaliser: AC1, AC2.
- The record entry: AC5.
- The CRLF-safe join helper: AC1's `joined reads …`; AC3's and AC7's CRLF runs.

The Problem and Solution are the capture's text. The only additions are the dated `Decided` line and one Non-goals bullet, which adds detail and cuts nothing.

Override check:
- `git grep -lF -e 'golden.spec' -e 'c0103/narrowed' -e 'c0128/golden' -e 'lib/pin' -e 'narrowing-pins-the-whole-file' -e 'mutants.py' -- pickman/tests z-nile/tests` finds nothing.
- `lune run z-nile/affected --` selects only itself for `narrowed.spec`, and nothing for the record.
- The only whole-file pins that collapse whitespace are c0103's and c0015's workflow probe (a Non-goal). The search was `git grep -nE 'gsub\([^)]*"%s[+*]?"' -- '*/tests/acceptance/*.luau'`.
- c0063's and c0106's narrowing specs hash raw bytes or use other probes.

In-flight work: of the worktrees whose diff touches these files, `prep-frame-roundtrip-tolerance` carries a lesson hunk that is already on main (ed43a849). The `proto-c0117/8/21` prototypes have a base from before the move. Neither is a conflict.

Earlier answers:
- **Rounds 001–003.** Every answer holds. In particular, a weakened compare is killed by the pins' own in-memory cases, and the derived mutants replace the published list. A refusal is checked by its exit, stdout and a one-line stderr. The forwarder is one code line.
- **Round 004 F1.** Holds against the shape attack: `kills-shape-pin` and `kills-no-in-place-mutants` are killed in my run. But the line-keeping edit has a positional blind spot (F1 below, low).
- **Round 004 F2.** Holds. `digest-recomputed-on-a-changed-file` is killed. The digest pin also closes a class the earlier rounds circled: no pin can add a pre-processing step of its own without moving the file's `pin.digest` off the pinned constant.
- **Round 004 F3.** Holds. `kills-globals-injected` is killed, and the environment's listed globals suffice for both pins.
- **New rules from round 004.** Two have no Rules row: "a line no edit can change fails the check", and the `kills-shape-pin` row's claim "on all three verdicts" (F4).

### F1 [low] The line-keeping edit is always made at the first editable pair of characters in a line, so a verdict that hashes only each line's start passes all of check.sh while an edit later in the line is unpinned
Where: `acceptance/kills.luau` `perturb` (lines 141–166: the loop runs `j = 1, #line - 1` and returns the first swap that changes the line); c0156.md, the Design's `kills.luau` paragraph ("one same-length edit of every non-blank line").
Evidence: on the prototype I replaced the body of `narrowed.spec`'s `exactly` with a digest of the first 10 characters of each normalised line. The cases, `DIGEST`, `pin.joined` and `pin.without` were left as they were:
```luau
local HEADS = "b927613942a7d60e394aac709cb14b6e838a929eafaa63b8f474272a7eb959cf"
local function exactly(text: string): boolean
	local out = {}
	for _, line in string.split(pin.normalise(text), "\n") do
		table.insert(out, string.sub(line, 1, 10))
	end
	return pin.digest(table.concat(out, "\n")) == HEADS
end
```
Results with that verdict:
- `narrowed.spec`: `4 passed, 0 failed`;
- `consumers.luau`: `all checks passed`;
- `kills.luau`: `all checks passed`, with "rejects all 53 mutants of …/keys.spec.luau".

Every derived mutant changes some line's first characters, or the line count. I then weakened f0014 line 35 from `t.expect(type(action) == "string" and action ~= "")` to `… or action ~= "")`. With the HEADS verdict, `narrowed.spec` and `keys.spec` gave `7 passed, 0 failed`. With the real verdict restored, the same edit gave `2 passed, 2 failed`.
Critique: I rate it low, not high. This verdict is built against the generator: it knows where the edit lands. The length and shape verdicts of rounds 001 and 004 were plausible "simplifications"; this one is not. No plausible mistake in applying the patch produces it.

It is still the fifth hole in the same black-box mechanism. The tempting fix would be a second edit per line at its last pair. That costs about +28 s, and it would still not kill a verdict that hashes each line's first and last characters.
Consequences: a black-box family can't prove that a verdict reads the whole text. Only the source can say what the verdict compares. Kills.luau already proves that the verdict decides the cases.
Recommendation: close it at the source, not with another family. `consumers.luau` should assert the one code line of each verdict as the Design prescribes it:
- `return pin.digest(text) == DIGEST` in `narrowed.spec`'s `exactly`;
- `== D24` in `exactly24` and `== D26` in `exactly26` in `golden.spec`.

Read each function's body through `pin.normalise`, so indentation can't make a false red. Add the runner entry and Rules row `consumers-verdict-heads` (the HEADS verdict above), to be killed by consumers.luau. Then say in the Guards bullet that the code review confirms the cases call those functions. Kills.luau proves the wiring for every derived mutant; a decoy function that the cases never call is something only a reader can spot.

### F2 [low] The lesson now sends designers to `pin.digest` "to tolerate formatting", and in the same text tells them to keep string contents when normalising, which `pin.digest` does not do. The Design's mitigation for that accepted risk is written only in c0156.md
Where: `prototype.patch`, the hunks for `zz-test/lessons/narrowing-pins-the-whole-file.md`: "How to apply" says "to tolerate formatting, use `pin.digest` … which keeps every line break". The next-but-one paragraph, unchanged, says "Pin the exact text …, or keep those newlines and string contents when normalising". `pin.luau`'s doc comment says only "runs of spaces and tabs within a line (collapsed to one space)". c0156.md, the Design: "A later pin that does hold such a string keeps the exact-text pin (c0150's), or changes this one rule and its digests".
Evidence: `pin.normalise('"a  b"')` collapses the run of spaces inside the string (the rule `[ \t]+` → " "; the Design accepts this risk). A designer who follows the lesson's "How to apply" for a file with such a string gets a pin that tolerates a changed `string.find` needle. The rule that would stop them ("keep the exact-text pin") is in c0156.md, which is history once c0156 is done. The lesson's `check` question still asks about spaces inside strings, which is why this is low.
Critique: the accepted risk is correct today (none of the three pinned files has such a string), but its condition is not stated where the next narrowing chore will read it.
Consequences: none beyond the text. The patch and `docs.spec` already pin these documents.
Recommendation: in the lesson's "How to apply", after "use `pin.digest`", add: "it collapses spaces inside strings too, so a file with a string holding a run of spaces or a tab keeps the exact-text pin". Say the same in `pin.luau`'s doc comment. Pin the clause with one more `has(...)` in `docs.spec`'s lesson case. The lesson's blob stays a *document* base.
Lesson: z-design/restated-rules-move-together

### F3 [low] `consumers.luau`'s comment contradicts the Design on what a later narrowing must do
Where: `acceptance/consumers.luau` lines 56–58 ("a later narrowing of a pinned file names this check in its Overrides, as it names the pin's"). Against it: c0156.md, the Design's `consumers.luau` paragraph ("so it never goes red for a later narrowing … leaves c0156's finished check.sh as the record of today's bytes"), and refute 004 F2 ("a later narrowing neither turns the gate red nor needs c0156's check named in its Overrides").
Evidence: the two texts give opposite instructions to the next narrowing chore. The script is sequestered, so the executor can't reconcile them. A reader of the promoted script (`z-nile/tests/acceptance/c0156/consumers.luau`) gets the wrong one. Item check.sh files run only through `./zn check <id>` (engine `main.luau:2738`), so the Design is right.
Recommendation: in prep, rewrite the comment to the Design's sentence: "runs at c0156's `done` only; a later narrowing updates the pin's digest and leaves this finished check as the record of today's bytes".

### F4 [low] The Design's mutant counts and two Rules claims lag the scripts
Where: c0156.md, the Design's `kills.luau` paragraph and E8 ("about 1,500 mutants (f0014 38, f0024 about 350, f0026 about 1,000)"); the Rules rows for kills.luau; Implementation step 6.
Evidence:
- **The counts.** My run derived 52, 461 and 1,256 mutants (1,769), plus 4 record entries. The 28 s time matches.
- **`kills-shape-pin`.** Refute 004 calls this row "the attack on all three verdicts", but the runner entry (`mutants.py` line 140) edits only `exactly24` and `exactly26`. `narrowed.spec`'s `exactly` is never shape-attacked. kills.luau would kill it (the same families run on f0014), but no row proves that.
- **The unchanged-line check.** The rule "a line no edit can change fails the check" (`kills.luau` line 316, `unchanged == 0`) has no Rules row or mutant. Without it, a `perturb` that silently skipped a kind of line would leave those lines unedited. Comment-only lines are the example: a verdict that drops comment text would then pass.
- **Step 6.** Its run time is not stated. Ten of the 64 mutants rerun kills.luau, at about 30 s each, so the full run is several minutes. Four of them took 103 s.

Recommendation:
- Correct the counts in the Design and E8.
- Either add `narrowed.spec`'s verdict to `kills-shape-pin` (40 lines, 5 asserts) or reword the row.
- Add a runner entry and Rules row `kills-unchanged-lines-ignored`: the `unchanged == 0` check made always true, plus `perturb` returning nil for lines that start with `--`. It is killed by "every non-blank line has an edit its pin must notice".
- Give step 6's expected duration.

Lesson candidate (for the lead): "A black-box kill check proves that a verdict decides the cases, never that it reads the whole text: its edits land somewhere fixed, and a verdict built against them passes. Pin the verdict's one comparison line in the source, and let the mutant families prove the wiring. Check: replace the verdict with a digest of what the generator edits (each line's start): does a check go red?" (c0156 design review 005 F1)

Verdict: approve
