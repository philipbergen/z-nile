# c0155 design refute 004

- F1: fixed: the own-action case also asserts `Pad.action(key) == Pad.BUTTONS[key]` for every key of the real map (Controls resolves a press through `Pad.action`). consequences: a Rules row and mutant M16 (`ButtonY = "Pick"` in the map, `Pad.action` answering `Jump` for it), run and killed; base 6 passed, M1–M16 killed.
- F2: fixed: E1, E4 and the output line give 6 cases and M1–M16, "rerun after each design round"; the lessons line names zz-test/narrowing-keeps-each-members-check and zz-test/pin-call-site-arguments. consequences: none.
