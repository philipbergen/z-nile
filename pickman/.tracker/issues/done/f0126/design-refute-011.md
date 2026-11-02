# Refute 011: f0126 (answers to design-review-011, round 1 of the f0109-colours re-prep)

This re-prep follows f0109's prep f88685c5 (the user's darker edible green, f0109's flat-children wall check, its request for a CIE76 check): its first round is file 011.

- F1: fixed, with the user (2026-10-26: "Brighter gold (Recommended)"): the marks' gold is 255, 215, 0 (33.3 CIE76 from Clyde, 31.4 from Inky, 88.7 from the edible green, 197.9 from the blue), recorded as a `Decided with the user` line and in game-design.md; `View.WALL_MARKED_COLOR`, HudView's PICK disc and bar, and every spec literal (views, parts, controls) follow; the `parts.spec` distance case iterates every entry of `View.GHOST_COLORS` (and checks there are at least four). consequences: a new lesson (shared-bars-cover-every-pair); the old Clyde argument is gone from the Regression guard.
- F2: fixed: E12's baseline reads 149 cases in 16 files and V1 to V9; AC5's text and its `check.sh` label name the walls' colour order and the gold's distance; the promotion dry-run bullet records design review 011's rerun. consequences: none.
- F3: fixed: V9 now sets Inky to f0109's old yellow (255, 230, 0; 8.8 from the gold), which only the distance case catches (killed: "the marks' gold stands at least 30 (CIE76) from every ghost…"). consequences: the spec-design-correspondence lesson gains the check.
