# Refute 016: R0042
Round 016 is this re-prep's round 11. It had no high finding.

Verification on the prototype, synced: `check.sh --full` passed, both members' checks passed (11/11 and 4/4), and `promote-check`, `luau-lsp analyze` and `lessons --check` were clean. `metrics-lessons.spec` passed with the host in UTC, Pacific/Auckland, America/Los_Angeles and Asia/Tokyo.

- F1: fixed with the reviewer's tested fix. The fixture's lessons commit is `2030-06-01T20:00:00-07:00`, and `tracker.sh metrics` runs with `TZ=America/Los_Angeles`. The UTC-day mutant (`os.date("!%Y-%m-%d")`) now fails, and the intended reader passes in all four host zones. Metrics says the zone is the running process's. The row lists the mutant, and E10 records the run. consequences: none.
- F2: fixed: the fixture's rafts sit in the backlog (R0010), `active/` (R0030) and `done/` (R0020), and a row covers it. consequences: none.
- F3: fixed: the `day` case title no longer says "(UTC)", and R0030's comment says it is created the day before lessons land. consequences: none.
