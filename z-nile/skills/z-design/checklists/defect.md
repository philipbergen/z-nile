# Design checklist: defect

Answer each in the issue's Design before the first review round (z-design step 3).
- **Reproduction**: the smallest input that shows the wrong behaviour, as a spec case that fails on `main` today, for the reported reason.
- **Expected behaviour**: the done issue or the plain expectation it breaks, quoted, and the feature or raft it reworks (zz-stats counts it as rework).
- **Root cause**: the line or rule that is wrong, not only the symptom, and why no existing spec caught it.
- **Siblings**: every other caller or place that makes the same mistake, each fixed in this issue or captured as its own.
- **Regression guard**: the new spec case is permanent once promoted; name the existing specs the fix could turn red.
- **Smallest change**: no refactor beyond the fix; anything larger is a chore of its own.
- **Closure** (the report does not reproduce, or the user closes it with no code change): the record answers Reproduction, Root cause and Siblings, and the issue is designed and reviewed like any issue (z-design, "A closure is designed and reviewed like any issue"). It holds what was tried and under which conditions in each report (device, build, place reached, or "unknown"), what changed between the reports and how that was read (the build the user played, not only main's source), the user's own words kept apart from the author's reading, the specs that guard the path rerun by `check.sh`, and who is unblocked once it is done through its own raft.
