# Refute 004: f0109 (design mode)

- F1: fixed: the Design states the bar as ≥ 30 (lemon 31.4 from f0126's gold (255, 215, 0), its nearest; 45.4 from the first gold), and E1 says the same; `grep -n "≥ 45" f0109.md` finds nothing; consequences: none.
- F2: fixed: the Regression guard names f0158 (depends on f0109, edits DangerHud and View) and the two radar colours f0109's radar case excludes by literal, so changing either is an override of f0109's `place.spec`; consequences: none.
