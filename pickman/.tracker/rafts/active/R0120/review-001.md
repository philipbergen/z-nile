# Review 001: R0120 (code mode)
Inputs: fd99edb5437f8df776ab39bb9d317c23023df572 (branch R0120/1/f0186, PR #593), diffed as `git diff origin/main...HEAD` against origin/main 9e7906b35 after `./zn sync --fetch`; f0186.md, its check.sh and acceptance specs, R0120.md.

Checks run by the reviewer on that commit:
- `z-nile/check.sh --affected`: GATE PASSED (pickman 2021 passed, 0 failed, 283 spec files; the other projects select nothing).
- `./zn check f0186`: 8/8 criteria passed.
- Sequestration (`git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'`): one line, `A pickman/.tracker/issues/active/f0186/acceptance/watch.txt`. It is the watch map `./zn finish` writes, and its eleven paths are exactly the eleven source files the layer changes (Main.client, RevivesView, PayView, HiscoreStore, Submits, Flow, Game, Hiscores, Lobby, Session, TestPurchase). No spec or check.sh changed (lesson zz-review/finish-watch-is-generated).

What was traced by hand against the Design:
- Count (§1): `Game.continue` adds one only after its phase and lives guard, so a continue outside the offer or with bad lives counts nothing. `playAgain` resets it with `lost`. Both `GameOver` emitters (the last life with no offer, and the offer's countdown, which `decline` and `Session.depart` reach through `timer = 1`) carry `revives`. `refuse` emits none. `tagged` copies the field. `Session.frame` sends nil for none. No other code builds a `Game` table (searched with `grep -rn "waiting = 0,\|offer = 0," src`: only `Game.new`).
- Store (§2): every place f0145's `lives` is copied in Hiscores (`grep -n "lives" src/shared/Logic/Hiscores/init.luau`: commit, rows, lobbyRows, onStep, topRun, ordered, both bestRun branches, topRows) now copies `revives` too, through `Hiscores.revives` wherever the value is read or sent. `best` carries it. `valid`, `qualifies` and the sorts do not read it. Submits passes it as the seventh argument, and HiscoreStore puts it on both attempts.
- Display (§3 to §5): `Lobby.lines` and `bestLine` end with `revivesText`. `panel` copies `revives` and drops `lives`. `Lobby.Row` keeps `lives` (E7). `livesText` and `LIVES_MARK` are gone. `Flow.revivesLine` returns nil outside the game over. RevivesView matches the Design's sentence: DisplayOrder 1, Arcade font, yellow, TextScaled, placed at (0.2, 0.64) with size (0.6, 0.05), clear of FlowView's prompt at 0.58 to 0.63. Main boots it and shows it each frame. `payLine`'s buy line, TestPurchase's play price and both `RichText` settings are as designed. The rich text carries only constants and numbers. LobbyView, which draws player names, stays plain text.
- Every play-price display was searched with `grep -rn "ROBUX\|R\\$\|payLine\|salePrice" src`. It finds PayView and TestPurchase, which now show the sale price, and `Flow.OFFER`, the continue's price, which stays plain (G3).
- Architecture: `Flow -> Lobby` is declared, and the graph is acyclic (Lobby requires Pay and Travel only). Logic stays engine-free (AC8 green).
- Performance: one integer per run, and nil on the frame while a run has no revives. RevivesView sets two properties per snapshot, as FlowView already does.
- Repository safety: the diff adds no script and no check.sh. Its unit cases are pure. Nothing writes outside the runner. The verification log's commands are the gate, `./zn check` and the spec runner.

### F1 [low] The sequestered gameover spec pins only RevivesView's height and DisplayOrder, not the rest of the look the Design names
Where: pickman/.tracker/issues/active/f0186/acceptance/gameover.spec.luau, "RevivesView draws the line at the game over and hides it in every other phase"; Design §4, `RevivesView.start` ("Arcade font, yellow, TextScaled, at (0.2, 0.64), size (0.6, 0.05)", `ResetOnSpawn false, IgnoreGuiInset true`)
Evidence: The case asserts the label's Text and Visible, `Position.y >= 0.63`, `Position.y + Size.y <= 1` and `DisplayOrder > 0`. It does not assert Font, TextColor3, TextScaled, Position.x, Size.x, IgnoreGuiInset or ResetOnSpawn. A RevivesView with `TextScaled = false` (the line drawn at the engine's default size of 14 px), `ResetOnSpawn = true` (the gui lost on a respawn) or `Position.x = 0` passes AC5 unchanged. The code in this layer sets every one of those properties as the Design says, so nothing is wrong today.
Critique: The lesson's rule is to pin every property the Design's sentence names. The gap only matters for a later edit of RevivesView. The author cannot edit the sequestered spec, and should not try to.
Consequences: A non-sequestered case that duplicates the stub harness costs a spec file and its watch, for a view whose look OC1 already checks by eye.
Recommendation: No change in this layer. When the spec is promoted, keep it as it is. If RevivesView changes later, that issue's design should pin the properties of its own sentence.
Lesson: pickman-test/drawn-from-the-visible-root
Erred: pickman-test
Upstream: z-design

## Judged criteria (code mode only)
f0186 has no Judged criteria ("### Judged: None."). Its look on a screen is OC1, which is Observed and run by a person after the merge.

Verdict: approve
