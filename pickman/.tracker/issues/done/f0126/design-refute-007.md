# Refute 007: f0126 (answers to design-review-007, round 2 of the re-prep)

- F1: fixed: "F and Y going down each send the pick once" asserts after the press (one pick) and again after the release (still one); rows U17 (no send on the press: killed by the between-phases assertion, which also kills the review's send-on-release X1), U18 (`Active = true`), U19 (captioned FIRE) and U20 (cyan) are killed. consequences: a new pickman-test lesson (assert-between-press-and-release).
- F2: fixed in f0126 itself rather than by a promise: game-design.md's Wall picks section gains its own "**Every input**" bullet quoting the user's rule, and AC10 greps it there (not the Platforms row f0146 rewrites); implementation step 1 checks that `Pad.BUTTONS` has no `ButtonY` row before adding it, and stops if one is there. The f0146 prep was told both (2026-10-25, through the coordinating session). consequences: the quote-other-preps-before-promising lesson gains that a promise only another prep can keep becomes a check in this issue's own steps.
- F3: fixed: the Regression guard names f0143 (its boost raises the step's speed, which Behaviour 3's cap takes as it comes, now said in Behaviour 3; its double tap of W is a movement key and wastes a pick; L3 does not clash with Y; the two issues' five shared files merge by hand) and f0109 (in its own review: its repaint and its yellow Inky are put to its prep, asked to keep marked walls gold while edible, to rebuild in the edible colour, and to measure Inky against the gold; if f0109 lands first f0126 is rebased on its colours). Usability no longer calls gold "the one colour no ghost uses". consequences: none for f0126's specs (they pin today's colours, which is the order the user set: f0109 is not before f0126 in it).
- F4: fixed. The searches for each superseded phrase over f0126.md and game-design.md, run after the edit:
  ```
  either order: 0                  either landing order: 0
  both landing orders: 0           Both landing orders: 0
  touch has no pick: 0             a gamepad button (f0146): 0
  KEYS.ButtonY: 0                  d66229c4, applies: 0
  If f0126 lands after them: 0     not prepped: 0
  one colour no ghost: 0           through `View.KEYS`: 2 (both "F through `View.KEYS`", correct)
  ```
  Step 1 checks every dependency, both narrowings and the free Y row, and runs the touch specs on d0151's and f0110's code; E11's pass is headless, and the phone is OC3. consequences: none.
- F5: fixed: `touch.spec`'s clearance case checks FIRE and JUMP against the pick's bar and banner on every screen; U21 (the bar at 0.85 of the height) is killed. consequences: none.
- F6: fixed: the accepted-risks lesson's added check is general: "where a design takes something away from the player in some cases (a control over another's gesture, a feature off on some screens), has the user been told where and chosen?". consequences: none.
