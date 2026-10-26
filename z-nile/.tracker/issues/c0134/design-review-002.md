# Review 002: c0134 (design mode)
Inputs: prep `prep-c0131-accept-header` cf5e35c5 (c0134.md, check.sh, acceptance/{header.spec,split,body}.luau, design-refute-001.md, harvest.md, zz-test/lessons/split-checks-share-one-boundary.md); design-review-001.md; `./zn capture c0134`; `./zn lessons --when design --full`. Mutants ran in a scratch clone of cf5e35c5 (scratchpad `dr-chores-2/c0134`) with the Design's header applied exactly (AC2's body diff alone: identical, as intended).
Dropped from review-001: F2 (fixed: the comment, E3 and the `base is HEAD` line say what AC2 judges).

### F1 [high] (repeat of review-001 F1) the one reader still leaves lines that neither the header check nor AC2 compares: line 1, a code line behind a `--[[ ]]` comment, and a last line without a newline
Where: `acceptance/split.luau` (`split.cut`: `n > 1` skips line 1; any line starting `--` before the body is header; `string.gmatch(text, "([^\n]*)\n")` drops a final line with no `\n`); check.sh `body_unchanged`; E4 ("A line at the boundary is in one of the two, never in neither").
Evidence: in the clone, each mutant applied to the fixed file, then AC2's own diff (`git show $base:… | lune run body.luau` vs the file) and header.spec:
- M7 line 1 replaced by `_G.c0134_mutant = true`: AC2 green, header.spec `3 passed, 0 failed`; `./zn check c0134` printed `PASS AC1 … PASS AC2 … PASS AC3 … 3/3 criteria passed`.
- M8 line 1 replaced by `--!nonstrict` (the file loses strict type checking): AC2 green, header.spec 3 passed.
- M9 a header line `--[[c0134]] _G.c0134_mutant = true` inserted at line 4 (a block comment followed by a statement, valid Luau): AC2 green, header.spec 3 passed.
- M10 `_G.c0134_mutant = true` appended as the last line with no trailing newline: AC2 green, header.spec 3 passed.
Critique: review 001 found a hole at the header/body boundary; this round finds three more in the same mechanism, because "a line that starts with `--` is a comment" and "line 1 is neither" are both untrue for Luau and for this file, and the line splitter loses the last line. Per this skill, the Recommendation questions the mechanism rather than patching each hole: the tempting fixes (compare line 1 too; add `string.split`) leave the `--[[ ]]` hole, and the next round finds the next one.
Consequences: the check must define what may change positively (a region made only of plain line comments) and compare every other byte, so no classification of "what is a comment" is needed beyond one strict pattern. The header.spec sample case and the lesson then pin that rule, not the old one.
Recommendation: change the mechanism to "the file equals its base except for one contiguous run of plain comment lines after line 1": `split.cut` splits with `string.split(text, "\n")` (keeping a final unterminated line and the trailing newline's empty element), puts line 1 in the body (so AC2 compares it), and lets the header be only lines matching `^%-%-$` or `^%-%- ` (a plain line comment: never `--[`, `--!`, or `--` followed by code); the first other line starts the body, and the body is the rest joined with `\n` byte for byte. AC2 then compares `line 1 + body` of base and working file. Add M7–M10 to Rules and mutants as `run`, each expecting AC2 red, and extend header.spec's sample case with a `--[[x]] y()` line (body, not header) and a last line without a newline (in the body). Update E4's sentence and the lesson's "How to apply" (the boundary rule must be a positive, strict pattern for the changeable part, and the splitter must keep every byte).
Lesson: zz-test/split-checks-share-one-boundary

### F2 [low] the new lesson restates the finding rather than the transferable rule
Where: `z-nile/skills/zz-test/lessons/split-checks-share-one-boundary.md`
Evidence: its rule ("cut both with one reader") is what this round shows is not enough: one reader with a loose notion of the changeable part (any `--` line, line 1 skipped, the last line lost) still leaves text in neither.
Critique / Consequences: a different raft that writes a "one reader" with the same loose rule passes the lesson's check question and still fails. None beyond the wording.
Recommendation: widen the lesson's check: "Is the part that may change defined by a strict positive pattern, and does the check compare every other byte of the file (line 1 and an unterminated last line included)? Does a mutant at each edge (first line, boundary, a comment-prefixed code line, last line) turn it red?"

Scope: unchanged from review 001: the capture's comment-only fix is met by AC1 and AC2 (once AC2 holds), nothing dropped.

Candidate lessons (for the lead): fold into zz-test/split-checks-share-one-boundary as in F2 rather than a new file.

Verdict: changes
