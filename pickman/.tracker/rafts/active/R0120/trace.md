# Trace: R0120

Commit: 0a4d16abb8a2ba44aaa499c65885417924ddbc34

## Claims

| claim | design | test | code |
|---|---|---|---|
| f0186:P1: Boards show revives used and the free game is per game (scope change to f0145) |  |  |  |
| f0186:AC1: a run counts the paid revives it used: each continue the offer takes counts one, nothing else does, a new run starts at none, and every game over carries the count (Session's events and frames too). |  |  |  |
| f0186:AC2: a hiscore entry records the run's revives: the submission, the stored row, the rows read back, the lobby's rows, the top-10 list and the best carry them; none, old rows and junk are nil; revives never rank, order or replace. |  |  |  |
| f0186:AC3: through the real adapters, Submits hands HiscoreStore the run's revives (also after a leave) and HiscoreStore writes them into every stored row and the run's list entry. |  |  |  |
| f0186:AC4: every board's rows end with REVIVES n after the level, REVIVES 0 for none (old rows included), the lives figure is not shown, and the viewer's best line shows its revives. |  |  |  |
| f0186:AC5: the game over shows REVIVES n (REVIVES 0 for none) in RevivesView, booted and shown each frame by the client's Main, with Flow's overlay unchanged. |  |  |  |
| f0186:AC6: the price of a play shows as 5 R$ struck through, on sale for 1 R$: the lobby's buy lines and the test purchase screen for a play, as rich text; the other lobby lines and the continue's price as they were. |  |  |  |
| f0186:AC7: game-design.md states the revives, the free game per game and the sale price (lives spent gone), architecture.md declares Flow -> Lobby, and pickman's paid-play records stay in its own stores. |  |  |  |
| f0186:AC8: Logic stays engine-free, every dependency is declared, and every feature has unit specs. |  |  |  |
| f0186:AC9: None. |  |  |  |
| f0186:AC10: OC1 (Studio or the Beta experience, test mode, with f0145 working): in the lobby, after the free game is used, the line under START GAME reads "A GAME:", then "5 R$" struck through, then "1 R$ SALE"; START opens the test screen, whose price line is the same, struck through. In the game, lose the last life, CONTINUE (BUY on the test screen) once, then END GAME at the next offer: under GAME OVER's prompt it says "REVIVES 1". Back in the lobby the run's row on every board ends "REVIVES 1", other rows "REVIVES 0", and the YOUR BEST line ends with its revives; on a phone-sized window (Studio's device emulator, 390 × 844) the panel's rows are readable (E5). At the game over the REVIVES line is as bright as the SCORE line above it (not dimmed by the fade), and on the 390 × 844 window it clears the touch controls. |  |  |  |

## Source files

| file | claims |
|---|---|
| pickman/src/client/Main.client.luau |  |
| pickman/src/client/RevivesView.luau |  |
| pickman/src/lobby/client/PayView.luau |  |
| pickman/src/server/HiscoreStore.luau |  |
| pickman/src/server/Submits.luau |  |
| pickman/src/shared/Logic/Flow/init.luau |  |
| pickman/src/shared/Logic/Game/init.luau |  |
| pickman/src/shared/Logic/Hiscores/init.luau |  |
| pickman/src/shared/Logic/Lobby/init.luau |  |
| pickman/src/shared/Logic/Session/init.luau |  |
| pickman/src/shared/TestPurchase.luau |  |
