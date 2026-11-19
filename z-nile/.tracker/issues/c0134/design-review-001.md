# Review 001: c0134 (design mode)
Inputs: prep `prep-c0131-accept-header` 4ce4ce18 (c0134.md, check.sh, acceptance/header.spec.luau); `z-nile/tests/acceptance/c0131/accept.spec.luau` at 4ce4ce18; `./zn capture c0134`; `./zn lessons --when design --full`. A mutant ran in a scratch clone (scratchpad `dr-chores-1/c0134`): the Design's header applied exactly, then one code line inserted.

### F1 [high] AC2 passes a code change placed between the header and the first `local` line
Where: check.sh `body_unchanged` (`awk 'f||/^local /{f=1; print}'`); Design ("Nothing below the header changes: no code")
Evidence: in the scratch clone at 4ce4ce18 I replaced lines 2–6 with the Design's header and added `_G.c0134_mutant = true` as line 7, just before `local fs = require("@lune/fs")`. `./zn check c0134` printed `PASS AC1 … PASS AC2 … PASS AC3 … 3/3 criteria passed`. AC2's body starts at the first line beginning `local `, so any line before it that isn't a `local` (an assignment, a call, a `require` used as a statement) is outside both the header (header.spec stops at the first non-comment line) and the compared body. AC3 only shows that the specs still pass. A harmful insertion could also be guarded so that it is quiet, so AC3 doesn't stop it.
Critique: the header and the body are cut by two different readers, and between them is a region neither checks (lesson zz-arch/one-reader-per-format). The tempting fix, starting the body at line 7, breaks as soon as the header has a different number of lines.
Consequences: cut both at the same point. The body is everything after the first block of comment lines following `--!strict`, the same rule header.spec's `header()` uses. Then a code line anywhere after line 1 is either in the body (compared) or ends the header early (header.spec sees a short header and fails on AC1's literals).
Recommendation: rewrite `body_unchanged` to drop line 1 and the comment block that follows it, in both the base and the working file (for example `awk 'NR==1{next} !b&&/^--/{next} {b=1; print}'`), and diff the rest. Add the mutant above ("a code line inserted between the header and the first `local`") to Rules and mutants as `run`, expecting AC2 red.
Lesson: z-design/spec-design-correspondence

### F2 [low] AC2 can only fail on the branch that makes the change; on main it compares the file with itself
Where: check.sh AC2 comment; E3
Evidence: `git merge-base origin/main HEAD` is `HEAD` on main, and an ancestor already holding the change on any later branch. So after landing, AC2 of the finished c0134 judges only the current branch's own delta to the body. On main it always passes. E3 says "holds by construction", which reads as a guarantee rather than a limit.
Critique / Consequences: lesson zz-test/no-vacuous-pass asks that "nothing to check" differ from "checked and clean". Pinning the body to a fixed sha instead would pin another spec's body forever, which the design rightly avoids (zz-test/promoted-specs-pin-rules-not-sets). So the limit is the right trade-off, but the design should say it plainly. None.
Recommendation: reword the AC2 comment and E3 to say that the check judges the branch's own change to the body and passes trivially on main once the change has landed. Optionally, print `base is HEAD: nothing to compare` when `base` equals `HEAD`, so a reader sees it.

Scope: the capture ("fix the header comment … it still describes the refusals that only refuse.spec tests … Comment only") is met by AC1 and AC2. Nothing was dropped, and leaving refuse.spec's header alone is within the capture.

Candidate lessons (for the lead):
- zz-test: when a check splits a file into "the part that may change" and "the part that must not", both sides must use one boundary reader, because otherwise the text between the two readers is checked by neither; check: does a line inserted at the boundary turn some check red?

Verdict: changes
