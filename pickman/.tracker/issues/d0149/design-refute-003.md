# Refute 003: d0149 (design mode)

- F1: fixed: the timer folds `Touch.hold(fingers, id, …)` on the live fold when it fires (ids are never reused); adapters cases fire the timer after a lift, after focus loss and after a re-layout, each followed by a working look finger; row C12 (the press-time state) killed. consequences: the hold case found a timer-promoted finger lifted under `TAP_SECONDS` still hopped; a looking finger now never hops (row N2).
- F2: fixed: HudView remembers the knobs and centres them only when `Touch.same` says the controls moved; adapters case "a HUD refresh (a shot, a life) leaves a pulled knob… a turn centres it"; rows H9, H10 killed; the Scalability sentence corrected.
- F3: fixed: no clock is compared: the timer promotes its own finger by id (`Touch.hold`); an adapters case fires the timer 1 ms early and the view points. consequences: `Touch.tick` is gone (no other caller).
- F4: fixed: c0182 removes the touch FIRE, PICK and swipe-boost cases that cannot pass on both sides of d0149, naming the d0149 case that takes each over, and notes the stub traps (`task.delay`, both circles); `Touch.same` tolerates partial controls (fold case, row U3).
- F5: fixed: AC3 and its check.sh label describe the timer, not a per-frame tick.
