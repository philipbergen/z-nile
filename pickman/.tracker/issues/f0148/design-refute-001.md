# Answers to design review 001 (f0148)

- F1: fixed: `Best.choose` stores level 1 for no level or a level not allowed (START GAME showed level 1); best.spec and adapters.spec cases; rows B4, B4b.
- F2: fixed: both `Bests` adapters open the store on first use inside a pcall and keep it once opened; a stub mode where `GetDataStore` throws: both places boot, no picker, level 1, and the store is used once it opens; rows A12, A13.
- F3: fixed: `Sessions.made(fn)` tells (player, session) once a session exists, never for a player who left during the wait; adapters.spec case; row A14; the Regression guard records that f0145's `Continues` listens there; f0145's prep session was told (2026-11-01).
- F4: fixed: the lobby Main's wiring pin accepts `Starts")?.start(` after `.choosing(Bests.choose)`, which f0145's spelling satisfies with `require("./Starts").choosing(Bests.choose)` before it; `Starts` keeps the level of a press that did not go for the next press that goes (so f0145's server-side press after a purchase carries the picked level); lobby.spec case; rows L10, L11.
- F5: fixed: the keys are bound with `ContextActionService:BindActionAtPriority` at `High`, above the camera, sunk only when they stepped; lobby.spec case; rows L7, L7b.
- F6: fixed: E6 (Phase 1, pass/fail, with a fallback) for the per-key write timing; `Best.raise` returns nil when nothing rises, so no write; row B11.
- F7: fixed: a case for a player who leaves during the start's wait (no session, `made` not told); the claim is not remembered for a player who left (a reasoned row: memory only).
- F8: fixed: put to the user, "Lobby now, portal later"; the Problem has the decision and c0188 records that the portal must carry the picker.
- F9: fixed: session.spec cases with the start below the level reached (extra life at 10,000 × 3 on level 6; a new run on 3 after reaching 6); rows S6, S7.
- F10: fixed: game-design.md records "Through the store" and "Lobby now, portal later"; the playAgain rule moved into the (prep) clause, with why it rarely applies.
