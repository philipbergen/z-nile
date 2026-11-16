# Refute 001: R0051 (answers to review-001)

- F1: fixed 037afbd8: the unit case "the fire button is level with the hop button where it clears the snap control, raised where it does not" asserts the visible rule on two screens: 1920×1080 level (fire.y = hop.y), 400×300 raised (fire.y < hop.y, its bottom exactly one margin above the snap control); mutants "always raised" and "always level" each fail it (7 passed, 1 failed). consequences: unit spec only, no code change; buttons.spec (AC1) unchanged; 
=== f0110 check.sh
PASS  AC1: the hop button is Roblox's legacy jump button, the fire button sits one margin left of it clear of the snap control, and on every sample both are at least 44 px and miss the HUD and the radar (but for the pinned overlaps)
PASS  AC2: in Touch's fold a finger down on the fire or hop button acts once at once and never looks or turns, one finger per zone, snap then fire then hop then the halves, and without the new rectangles the fold is unchanged
PASS  AC3: Controls sends the aimed shot for a fire tap and Hop.INTENT for a hop tap from the hook's rectangles, HudView draws non-active outlined FIRE and JUMP discs under its Hud ScreenGui on touch screens at Touch.buttons and reports them, and Main wires HudView.buttons
PASS  AC4: end to end on a phone, a dropped shot, a look drag and a fire tap eat the ghost on the right, and a hop tap starts the hop
PASS  AC5: the existing touch, key, HUD, blaster and hop specs still pass
PASS  AC6: Logic stays engine-free and every dependency is declared
---- 6/6 criteria passed still 6/6.
