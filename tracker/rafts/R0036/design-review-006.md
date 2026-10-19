# Review 006: R0036 (design mode)
Inputs: branch prep-narrow-key-map at 72f6806 plus the uncommitted prep files (R0036.md, R0036/check.sh, c0103.md, c0103/check.sh, c0103/acceptance/narrowed.spec.luau, c0103/experiments/narrowing.patch, f0104.md, game-design.md, design-review-001 to 005, design-refute-001 to 005); tests/acceptance/f0014/keys.spec.luau, tracker/issues/done/f0014/check.sh, tests/lib/renamed.luau, tracker/compaction.txt, src/shared/Logic/View/init.luau, stylua.toml. Everything ran in a scratch clone outside the repo (its origin a scratch bare copy), with the prep files copied in.

Re-verified (not trusted):
- Before the patch, `tracker.sh check c0103` fails AC1 only, on the golden assertion. After `git apply narrowing.patch` and `stylua tests/acceptance/f0014`, it passes 3/3. `stylua --check` and `selene` are clean, `promote-check R0036` is OK, and the full `R0036/check.sh` (full gate, members, promote-check) passes 3/3.
- Round 5 F1 is fixed. `normalised()` no longer strips comments. Its only tolerances are whitespace collapse, a trailing comma before `}` and masked ids. The GOLDEN holds the four header lines. Round 5's mutant B (a stub between `-- … --[[` and `-- ]]`) and mutant C (a case name containing `--[[" .. "]]`) now both fail the golden.
- Earlier fixes still hold. The require lines are pinned (round 3 F2). The require text is built by concatenation, so the architecture scanner is not tripped (round 3 F1; promote-check OK). `members R0036` prints c0103 (round 1 F2). f0104 has `depends_on: [c0103]`, and `View.snap` is left alone (round 1 F3, F4).
- E2 still holds. With f0104's map in `View.KEYS` (arrow keys to look actions, `Space = "Jump"`, `E = "Fire"`, `Action = string`), the narrowed keys.spec and view.spec pass 9/9.

Holes hunted, none found:
- **A newline where the GOLDEN has a space.** Line comments occur only in the header, so this can only matter there. Splitting a header comment would turn its tail into code. Every tail is a syntax error, because each comment line ends in a word or `.`, and `bindings (ID)` is followed by `can be …`. Joining code onto a header comment line instead comments out a prefix of the code, starting at `local Movement`. That leaves `Movement`, `View` or `t` nil, so the cases error. Commenting out everything makes the module return nil: the runner reports "could not load spec" and AC2 fails, which I ran.
- **Code inside strings.** Luau strings can't hold a raw newline, and `\` continuations change the text. The GOLDEN has no space before `(` and no `,` before `}` inside a string, so neither tolerance can change what is asserted.
- **The id mask.** It matches only `[fdcR]%d+` tokens. The GOLDEN has `ID` only in comments and in the spec name, never in code.
- **Legitimate edits.** All of these still pass the golden: blank lines added, CRLF line endings, renumbered ids (c0103, f0130 and f0104 changed), and a whole-file `stylua` at column width 200. At the repo's width (110) the patched file is stylua-stable; its longest code line is about 93 columns. Only an unrealistic `--column-width 40` reflow fails, because it inserts whitespace inside parentheses where the GOLDEN has none. A later edit at that scale would need a golden update anyway, which the narrowed.spec header already requires.
- **Compaction.** `renamed.id("f0014")` follows the same pattern as the promoted c0063 narrowed.spec, and `compaction.txt` maps f0130 to f0014, so the header's `f0130` is the old id and is masked.

## Mechanics checked (no finding)
- Sequestration and executability: the executor applies the patch, adds the f0014 note, runs stylua and the checks, and edits no `check.sh` or `acceptance/` file.
- Repository safety: narrowed.spec only reads files (`fs.readFile`, `fs.isFile`). c0103's and R0036's check.sh run only `lune run tests/run`, `tracker.sh` and the gate.
- Order: R0035 cannot start until c0103 is done.

Verdict: approve
