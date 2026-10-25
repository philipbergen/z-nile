# Review 005: R0036 (design mode)
Inputs: branch prep-narrow-key-map at 72f6806 plus the uncommitted prep files (R0036.md, c0103.md, c0103/check.sh, c0103/acceptance/narrowed.spec.luau, c0103/experiments/narrowing.patch, f0104.md, game-design.md, design-review-001 to 004, design-refute-001 to 004); src/shared/Logic/View/init.luau, tests/acceptance/f0014/keys.spec.luau, scripts/check.sh (the stylua, selene and luau-lsp gates). Everything ran in a scratch clone outside the repo with the prep files copied in.
Re-verified: before the patch `tracker.sh check c0103` fails AC1 only (on the golden assertion). After `git apply narrowing.patch` and `stylua tests/acceptance/f0014`, narrowed.spec and keys.spec pass. `promote-check R0036` is OK and `tracker.sh members R0036` prints c0103. Round-4 F1 is fixed for the case it named: M21 (`--[[ … --]]` around the `want` loop) and M22 (`--[=[ … --]=]`) both fail the golden. A one-line stylua `want` table and a compaction-renamed id still pass. Round-4 F2 is fixed. The rulings on rounds 1 to 3 still hold.

### F1 [high] The normaliser still hides real code: a `--[[` inside a line comment or a string makes it strip whatever Luau runs before the next `]]` (fifth hole in the same pin mechanism)
Where: tracker/issues/c0103/acceptance/narrowed.spec.luau `normalised()`, the first two `gsub` calls (the long-comment strip and the line-comment strip); c0103 E3 ("nothing else is tolerated"), Rules and mutants rows 1 to 3
Evidence: The normaliser matches comments with regexes over the raw text. It doesn't lex, so it can't tell when Luau ignores a `--[[`. I reproduced two mutants in the scratch clone. In both, `src/shared/Logic/View/init.luau` was changed to `W = "Back"`.
- **B (line comment):** after the three require lines, add these lines:
  ```
  -- stylua keeps this --[[
  local FAKE = { W = "Forward", A = "Left", D = "Right", S = "Back" }
  View = { KEYS = FAKE, action = function(key: string): string? return FAKE[key] end } :: any
  -- ]]
  ```
  Luau sees two line comments and runs the stub between them. The normaliser finds `--[[` inside the first comment and strips everything up to the `]]`, so the result equals the GOLDEN.
- **C (string literal):** the case name becomes `"other keys do nothing--[[" .. (function(): string <same stub> return "" end)() .. "]]"`. The normaliser again strips everything between `--[[` and `]]`.
- **Gates:** both mutants are stylua-stable and clean under `stylua --check`, `selene` and `luau-lsp analyze` (no output). `scripts/tracker.sh check c0103` reports 3/3 PASS on each. keys.spec then tests a stub, not `View`, and the real map has W bound to `Back`.
- **Variant A:** an early `do return t.spec("f0130 key map", function(it) it("…", function() end) end) end` hidden the same way also gives 3/3. Its only symptom is a luau-lsp `UnreachableCode` warning, and the gate exits 0 on warnings.

So AC1 ("is exactly the narrowed spec … pinned token for token") can be met by a keys.spec that asserts nothing about the real map, and AC2 and AC3 then pass trivially.
Critique: This is the fifth round in a row to find a way through the pin. Rounds 1 to 3 found weakened assertions, emptied loops and stubbed requires; round 4 found block comments. Each fix widened the pin or added a special case. The rest of the normaliser only tolerates layout. The comment stripping is the one step that throws away characters, and a regex can't do it correctly without a Luau lexer (strings, long strings, comments inside comments, `\` line continuations). The tempting fix is another special case: strip line comments first, or skip `--[[` after a quote. Each such patch leaves a sixth hole. One example: a long string `[[ … --[[ … ]]` interacts with whichever strip runs first.
Consequences: If comments are no longer stripped, the GOLDEN must contain the four header comment lines too. The header ids are masked already, so a compaction still passes. Any wording change to the header then needs a golden update, which the header already demands for any change to keys.spec. `--!strict` becomes pinned, which closes the smaller round-4 note about it. What remains tolerated is only:
- whitespace runs collapsing to one space (they never join two tokens);
- a trailing comma before `}`;
- item ids.

No string in the GOLDEN depends on whitespace except the case names, so none of these can change what the spec asserts. The `require(` split in the GOLDEN literal must stay, so the architecture scanner does not trip (round 3 F1); the header has no `require(`.
Recommendation: Remove both comment `gsub` calls from `normalised()` and extend the GOLDEN with the header lines, normalised the same way. I ran this normaliser (id mask, whitespace collapse, trailing comma, trim):
- The patched keys.spec matches.
- The one-line `want` table and a renamed id match.
- B, C, M21 and M22 all differ.

Add B and C as mutants M23 and M24, marked run, in E3 and Rules and mutants rows 2 and 3. Rewrite E3's tolerance sentence to name exactly the three tolerances above. Change the narrowed.spec header ("comments and whitespace ignored") to say that comments are pinned. Re-run `promote-check R0036`, `stylua --check` and `scripts/tracker.sh check c0103` before and after the patch.

## Mechanics checked (no finding)
- Sequestration and executability are unchanged since round 4. The executor applies the patch, adds the f0014 note, runs stylua and the checks, and edits no `check.sh` or `acceptance/` file.
- Repository safety: narrowed.spec only reads files.
- Order: f0104 `depends_on: [c0103]` holds R0035 until R0036 is done.
- R0036 and c0103 are `design: reviewed`, correct before the final round.

Verdict: changes
