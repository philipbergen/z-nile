# Refute 002: c0150 (answers to design-review-002)

- F1: fixed: the lesson's "How to apply" now says to pin the exact text (ids masked, LF line endings), with c0150's `narrowed.spec` as the model and c0103's whitespace collapse as the counter-example. consequences: none.
- F2: refuted: the rule the removed `"F"` guarded, that F is not bound to an existing action, is the general rule "a key beyond the ten binds an action of its own", whose row already holds code mutants K2 (`Z = "Forward"`) and K3 (`G = "Jump"`); the reviewer's own F mutants (`F = "Fire"`, `"Snap"`, `"LookUp"`) are instances of it and were killed by the same case. The one survivor, F bound through `View.action` only, binds nothing in the game (Controls binds `View.KEYS` names), as the review says. No row, case or spec changes.
- F3: fixed: the check.sh AC1 label and the digest case's title say "more keys allowed each with an action of its own". consequences: none (labels only).
