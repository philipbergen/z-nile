# Refute 005: f0158 (design mode)

- F1: fixed: place.spec's real-source case asserts the drawn Ring screen's `ResetOnSpawn` is false, next to its ScreenInsets, IgnoreGuiInset and DisplayOrder. The Design's adapter paragraph names the setting ("the Ring screen sets `ResetOnSpawn = false`, so a respawn keeps it"). Rules row "the ring survives a respawn" with R35 (`edge.ResetOnSpawn = false` deleted): place 2 passed, 1 failed on the prototype.
