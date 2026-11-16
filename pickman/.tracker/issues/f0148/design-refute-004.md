# Answers to design review 004 (f0148)

- F1: fixed: the yielding-hook case now makes the first teleport fail, waits out the cool-down, presses with no level and expects the hook to get 2 (the level pressed while it waited); row L12 (the kept level cleared after the hook), killed.
- F2: fixed: the Regression guard's order bullet says c746326c recorded the `depends_on` on f0145's prep branch (past tense), and what its lead still changes when it resumes.
- F3: fixed: the lobby client's wiring pattern accepts `LobbyPicker")?.new()` (an inline require or a local bound to it); LobbyView's exact `.start()` stays, because f0146's promoted spec pins it.
