# Design checklist: chore

Answer each in the issue's Design before the first review round (z-design step 3). CI, test and tooling fixes are chores even when they fix a bug.
- **No behaviour change** for players: say which behaviour stays exactly as it is, and which spec shows it.
- **Overrides**: every promoted spec the chore changes, named on its `Overrides:` line with what it still pins (a chore may change promoted specs in its own raft).
- **Existing work**: which prepared, active or mid-prep items, open branches and sequestered `check.sh` files fail the new rule or layout on the day it lands, and what each does then (lesson z-design/new-rules-migrate-existing-work).
- **Shared state**: any file `main` keeps writing during the raft (a counter, a map, a registry) stays untouched by the branch, and the tooling picks the live copy from the base it fetched.
- **Restated rules**: every skill, AGENTS.md line and comment that restates a changed rule changes with it, and the new wording is pinned.
- **Moves**: a move is its own renames-only commit, so the review can read it with rename detection.
- **Guards**: any change near the repository guards, the publisher or the gate fails closed (zz-arch skill).
