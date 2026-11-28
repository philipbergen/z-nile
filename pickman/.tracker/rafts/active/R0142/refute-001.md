# Refute 001: R0142 (code mode)

- F1: fixed: normalized `-0` bounds in `View.runsKey` with `+ 0` so `r.x0 + 0, r.y0 + 0, r.x1 + 0, r.y1 + 0` always formats zero as `"0"`; consequences: none (still equals itself on `View.walls` output and now also matches literal `+0` rects).
- F2: fixed: appended Verification log entry to `c0228.md` including the local placement/style notes; consequences: none (doc-only).
