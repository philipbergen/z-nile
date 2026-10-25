# Refute 001: R0015

- F1: fixed 652e459: `Main.client.luau` now takes `RULES = assert(Session.GAME_CONFIG.play, …)`, exactly the design's rules with no silent fallback; the now-unused `Game` require is gone.
- F2: fixed 652e459: `HudView`'s ScreenGui has `DisplayOrder = 1` and `FlowView`'s has `DisplayOrder = 0`, so the score and lives draw over the dying and game-over fade deterministically (part of OC1 in Studio).
