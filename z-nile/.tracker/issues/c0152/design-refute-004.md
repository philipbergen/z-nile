# Refute 004: c0152 (design mode)

- F1: fixed (prototype bb94742a):
  - The probe's trigger now holds a queue of commits, one pushed per trial.
  - New cases: (a) four tracker moves prepared, a no after exactly three trials ("kept moving during the check (3 trials)"); (b) two tracker moves, then spend rows only after the third trial: ok, three trials, `judged main` the last commit.
  - New Rules row "at most three trials; after the third, a notrial-only move is ok and any other is a no", with Y1 cap 2, Y2 no cap and Y3 a no after the third whatever the move, all killed.
  - Rule 3, AC1 and zz-rules now state both outcomes after the third trial.
  - zz-rules gives one instruction: on "kept moving" (and on "moved during the check … can't be judged here") run merge-check again; every other no falls back to the old rule.
  - Consequence: none beyond the cases.
- F2: fixed:
  - A `notrial` path counts only while its item's document is still in that folder in the merged tree: the PR's copy when the PR changed that folder, else main's (`liveItem` in `judge`). Otherwise the trial runs again.
  - Case: the PR moves c0901 (no spend.md) to `done/`, and the probe pushes a first `c0901/spend.md` at the old folder. The result is a no, never ok.
  - As run, that second trial stops at `git merge-tree`, which reports main's file in the renamed folder as a conflict. The reviewer traced an audit failure instead; the case accepts either no and pins "never ok".
  - Y4 (notrial by glob alone) killed.
  - Consequence: this doesn't narrow the user's decision; it refuses the skip only where the row belongs to no live item.
- F3: fixed: zz-rules' step 4 and the row now say "about 2–3 minutes idle and 10 or more under load, up to three trials: run it in the background (or with no timeout) and wait for its verdict line". The Design cites E5b's 599 s, and docs.spec pins the new phrase. Beside the user's decision the Design adds the reviewer's note: a PR that changes spend-reading code can merge over a row it never ran against, which the decision accepts. Consequences: none.
