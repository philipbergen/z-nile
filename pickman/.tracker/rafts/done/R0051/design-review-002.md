# Review 002: R0051 (design mode)
Inputs: prep worktree at 996f445e plus its uncommitted edits (R0051.md, R0051/check.sh, harvest.md, f0110.md, f0110/check.sh, f0110/acceptance/{buttons,fold,adapters,hunt}.spec.luau, game-design.md, architecture.md, z-nile/skills/z-design/lessons/prep-choices-marked-and-checked.md, pickman/skills/pickman-test/lessons/drawn-from-the-visible-root.md); design-review-001.md and design-refute-001.md; `./zn capture f0110` (f880bedb); prototype `proto-f0110` at a95a0c68 (base d8a9a9a; `git diff HEAD origin/main -- pickman/src pickman/tests/place pickman/tests/lib` shows only the prototype's own changes, and its four specs are byte-identical to the sequestered ones); CI run 40235065457.
Dropped from design-review-001: F1, F2, F3, F4, F5, F6 (all answered `fixed`, and each fix holds: see below).

Rulings on design-refute-001:
- F1 fixed. `frame(name)` now walks PlayerGui → the one `Hud` ScreenGui → its children, and `expectDrawn` pins colour, transparency, border, corner, caption text, size, colour, outline and `Active`. Re-run on the prototype: M19 (`f.Parent = parent` removed) gives `6 passed, 4 failed`; M21 (FIRE `WHITE`) gives `9 passed, 1 failed`. Prototype restored (clean `git status`).
- F2 fixed. game-design.md's bullet now starts with only what the capture says, and every choice after it sits behind **(prep, R0051)**, with the cost of finger-down stated there, in f0110 Usability and in R0051 Risks.
- F3 fixed. FIRE uses `CYAN`, the Inky's colour entry names the button, and the captions are outlined.
- F4 fixed. E5 records all three runs. `gh run view 40235065457`: headSha a95a0c68, `gate (z-nile)` success, `gate (pickman)` success.
- F5 fixed. Three samples with `touches` pins were added. A Lune probe over the prototype's `Touch.buttons`, `Hud.radarBox` and `Touch.blocks` reproduces all three new Design rows (fire, hop, snap, radar), and the hop/snap intersection {225, 517, 1, 31}.
- F6 fixed. (a) The caption pair is in the HudView bullet, with the `FindFirstChildOfClass` warning. (b) Non-goals now reads correctly. (c) Both rows were added.

Also checked and sound:
- Specs on the prototype. f0110 + f0027/28/29 + f0100/01/04 + `tests/unit/Touch` + `touch-adapters` + `hud-shots` + `tests/meta/architecture`: 255 passed, 0 failed (35 files).
- The specs on the prep tree. `./zn check f0110`: AC1 to AC4 fail (0/6, 2/10, 1/10, 0/2), and AC5 and AC6 pass. This matches E3.
- `./zn audit`: 0 errors. Its only warning is R0040's, which is unrelated.
- Executability under today's tooling. R0051 is a single raft whose member is stamped with the raft's value. `status R0051 prepared` exempts it from `grouped:` (main.luau, "only an old-flow member … is exempt"), and neither that command nor `ready` asks for a coherence review when there is one member (`#targets > 2` and `#members > 1`). So it can be readied as made.
- Camera's mouse hold counts every physical touch (`ids`), button fingers included (lesson guard-what-the-engine-sees).
- During GAME OVER, Flow's full-screen `Continue` button sits under the HUD's non-active discs. A tap there also sends Fire or Hop, which the server ignores out of play, as it already does for the snap control.
- The new lessons. Both are general rules another raft could break, not restated findings.

### F1 [medium] The caption's centring and Arcade font are named in the Design but unpinned; both mutants pass
Where: f0110 Design, HudView bullet ("`label("Caption", Enum.TextXAlignment.Center, frame)`: white Arcade text"); `acceptance/adapters.spec.luau` `expectDrawn` (lines 387-410); Rules and mutants (no row).
Evidence: I ran both mutants on the prototype and restored it afterwards.
- (a) `label("Caption", Enum.TextXAlignment.Left, f)`: `adapters.spec`, `tests/place/hud-shots` and f0029's specs gave `44 passed, 0 failed, 7 spec files`.
- (b) The caption built with a bare `Instance.new("TextLabel")` instead of `label(...)`, so no `Font` is set (Roblox's default font, not Arcade), with name, background, colour and parent kept: `44 passed, 0 failed`.

On a phone, (a) puts FIRE and JUMP against the left edge of each disc, and (b) draws them in a different typeface from the rest of the HUD. The stub's enum proxy already records `{ Name = "Center", group = "TextXAlignment" }` and `{ Name = "Arcade", group = "Font" }`, so the assertions cost nothing.
Critique: round 1's F1 found that the drawn look was unpinned. The fix pinned a hand-picked list of properties, and the author's new lesson `drawn-from-the-visible-root` says to "pin what the Design names about the look". The list still leaves out two properties the same Design sentence names. The tempting fix is two more `expect` lines, which leaves the list hand-picked: the next property the Design adds (say a `ZIndex` or a font size) would go unpinned the same way.
Consequences: the spec has to read enum items. `Enum` is created inside `hudView`, but the proxy's items carry `Name` and `group`, so `c.Font.Name == "Arcade"` and `c.TextXAlignment.Name == "Center"` work without exposing it. Nothing promoted changes, and `hud-shots` is not touched.
Recommendation:
- Make `expectDrawn` follow the HudView bullet sentence by sentence. Add `c.Font` = `Arcade`, `c.TextXAlignment` = `Center` and `c.Name` = `"Caption"` (the bullet names all three).
- In Rules and mutants, either add one row per property the bullet sets or one row whose case is "every property the HudView bullet names". Add the mutants "caption left-aligned" and "caption without `label()` (no font)". Run them on the prototype and record them in E4 (27 mutants).
- Add one sentence to the bullet saying that every property it names is pinned in `expectDrawn`, so a later edit to the bullet carries its pin with it.
Lesson: z-design/spec-design-correspondence, pickman-test/drawn-from-the-visible-root

### F2 [low] The Design table is split by a blank line, so its three new rows render as loose text
Where: f0110.md, Design, "Placed on f0029's sample screens" (the blank line between the `568×320 under a 58 px top bar` row and the `320×568` row).
Evidence: in Markdown a blank line ends a table. The rows for 320×568, 500×900 and 900×500 follow it with no header or separator row, so they render as a paragraph of pipes, not as table rows. These are the three rows round 1's F5 added, and the following paragraph's "touches" claim relies on them.
Critique: the values are right (the probe reproduces them), but a reader of the rendered document sees no table for them.
Consequences: none.
Recommendation: delete the blank line.

Verdict: changes
