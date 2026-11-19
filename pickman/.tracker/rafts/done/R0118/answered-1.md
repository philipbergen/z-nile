# R0118: questions for the user

## What should a "buy" arrival in the game place do when it cannot be sent back (a Studio play), given G10 sends every other one back to the lobby?
Code review 001 F2 (high; final review 001 F1). With Studio API access on, a Studio play of the game place takes the hour's free start in `PaidPlayTest` on its first play. Every play in the next hour is then a "buy" arrival with no lobby pass, and Studio cannot teleport, so the developer is kicked with "Start a game from the lobby.". Before this raft every Studio play worked. OC1's Studio leg cannot run as written either. The full text and each option's cost and cases are in R0118.md, `## Open to the human`:
- (a) In test mode a "buy" arrival plays, or opens the test purchase screen in place. Cost: direct joins to the Beta game place play test games free and unbounded (test records only).
- (b) Only in Studio (`RunService:IsStudio()`, guarded with `pcall` because the sequestered stub has no `IsStudio`) a "buy" arrival plays. Live and Beta keep G10. This is the executor's recommendation.
- (c) Keep it, and document in game-design.md and OC1 that a Studio play of the game place is kicked after its first game each hour while API access is on.

Answer by adding `Ruled (user, YYYY-MM-DD): <a, b or c>` to that bullet. For (a) or (b), the raft then needs one more fix commit with its cases (listed in the bullet), a re-finish and a trace refresh before `./zn done R0118`. For (c), it needs the two document lines.

## Answer
Ruled (user, 2026-11-16): (b) "Play in Studio only (Recommended)": "Only when RunService:IsStudio() is true, an arrival with nothing to pay with plays. Beta and live keep G10 as it is. One fix commit with its cases, then the layer is re-finished." Recorded on the bullet under R0118.md's `## Open to the human`, and carried out on the layer. This file is kept as `answered-1.md`, as the dispatcher keeps an answered `questions.md` (zz-rules, Dispatch), so that `questions.md`, the block signal, is gone.
