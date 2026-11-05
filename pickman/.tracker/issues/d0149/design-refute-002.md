# Refute 002: d0149 (design mode)

- F1: fixed: Controls compares the controls by value (`Touch.same`, pure, a fold case moving each number of each control); an adapters case hands back an equal copy and the held steer finger keeps steering; rows C10 (identity) and U1, U2 killed. consequences: a real move still lets go (C9).
- F2: fixed: no per-frame loop: a look finger going down schedules one `task.delay(Touch.TAP_SECONDS, …)` that folds `Touch.tick`; f0126's controls.spec now fails only its touch cases (in the Overrides), its F and Y cases pass. E4 rerun after this round: 1420 passed, 74 failed, the overridden files. consequences: rows C8 (tick dropped) and C11 (delay 0) killed; the adapter stub gains `task.delay`.
- F3: fixed: f0143's place.spec phrase "two quick swipes up" is in the Overrides and in c0182's list. consequences: none beyond c0182.
- F4: fixed: c0182 has one Non-goals section; its Solution keeps every file (a removal carries its `check.sh` line in a tracker PR); its list carries f0143's phrase. (F2 needs nothing of c0182 now: f0126's keyboard cases pass.)
- F5: fixed: the Unknowns preamble names the prototype commit by its message; mobile.md says a tap only hops and a pull points once moved 12 px or held 0.25 s.
