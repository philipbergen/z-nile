# Design refute 007

- F1: fixed: cli.spec's ended-loop case restores the copy after the dropped-line refusal and asserts `status prepared` refuses naming design-review-002 (the window starts there), then prepares once an approving design-review-002 is written; Rules row and mutant M74 (the gate counting from round 001). consequences: none beyond the prototype's window read, which already uses the Loops line.
- F2: fixed: the Edge case now says an unmarked older ticket is an `idea` pick and `--guess` marks it (G34); idea.spec "an unmarked older ticket is an idea pick too: the guess run marks it" with two unmarked fixtures (after and before c0260). consequences: M75 added.
- F3: fixed: c0260's `dropConfirmed` drops a marked issue's guess-mode line and keeps the unattended line; capture.spec calls it on both, and its clean case asserts no Confirmation problem of any kind (the fixture's other c0260 rules are not this issue's to pin). consequences: M76 reasoned until c0260 lands.
- F4: fixed: the reasoned row no longer lists `status prepared` among the unwired callers (M71 is its row), and a reasoned row names `--guess` refusing over an unruled open line. consequences: none.
