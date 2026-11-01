# d0149: the executor's document text

## game-design.md, the Mobile section (replaces the Turns, Look, Recentring and Fire and hop bullets; the HUD bullet stays)

- **Touch circles** (d0149; the user, 2026-10-25 and 2026-10-31; they replace R0012's swipes, drag look and snap button and f0110's JUMP button): two fixed circles, each **30% of the screen's shorter side** (of the safe rectangle; 96 to 160 px), shown only on a touch screen, and two buttons.
  - **Steer circle** (lower left, one margin above the lives row, **(prep)**): pull on it from its centre. A pull left, down, up or right is `Left`, `Back`, `Forward` or `Right`, as A, S, W and D, once a pull, folded as a controller's left stick is (`Pad.steer`); two quick pulls up boost, as a double W does (f0143).
  - **Look circle** (lower right, on the power bar, **(prep)**): the pull's direction from its centre is where the view points, relative to the heading (up ahead, left a quarter turn left, down behind), at the arrows' turn rate with the pitch level, and it aims the blaster as the arrows do; letting go springs the view back to the heading. A **tap** (lifted within 0.25 s, having moved less than 12 px) only hops, on the lift: the view does not move for a tap, so a pull starts pointing once the thumb has moved 12 px or been held 0.25 s. **(prep)**: a pull under a quarter of the radius points ahead; each circle shows a knob where the thumb pulls.
  - **FIRE and PICK** (cyan and gold discs, captioned; **(prep)**: 0.45 of a circle's diameter, at least 44 px) sit left of the look circle in the row PICK, FIRE, look, on the steer circle's bottom line; each acts when the finger goes down.
  - A finger that lands outside the controls does nothing; one finger per control. There is no snap button: the look springs back on its own.
  - The controls clear each other, the HUD, the corner radar, the danger ring (f0158), the pick bar and the boon banner on every sample screen, except that PICK may draw over a few ring dots on a 480 x 320 screen under a 58 px top bar (the user, 2026-10-31).

## game-design.md, the other touch statements (review 001 F5)

- *Look* (core rules): "on touch a "snap look to heading" button recentres it" becomes "on touch the look circle points the view and springs back when let go (d0149)".
- *Wall picks*, the pick (f0126): "on touch a PICK button one margin left of FIRE, level with it and its size, added after f0110, which on narrow portrait phones takes a 70 px square of the swipe-to-turn half: user, 2026-10-25" becomes "on touch the PICK button, left of FIRE beside the look circle (user, 2026-10-25; placed by d0149)".
- *Speed boost* (f0143): "on touch, two quick swipes up" becomes "on touch, two quick pulls up on the steer circle (d0149)".

## architecture.md, the Touch row

| Touch | The phone's controls as a pure fold over begin, move and end (d0149, replacing R0012's swipes, drag look and snap and f0110's JUMP): a steer circle whose pull folds through `Pad.steer` into turn intents, a look circle whose pull points the view and whose tap hops, FIRE and PICK buttons; one finger per control, nothing elsewhere; `Touch.buttons` places them in the HUD's safe rectangle; the HUD blocks and screen-pixel conversion (R0012) |

and in the deps block, `Touch -> Hud` and `Touch -> View` removed (`Touch -> Pad` is declared in prep).
