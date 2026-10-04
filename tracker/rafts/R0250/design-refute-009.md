# Refute 009: R0250 design review 009

- F1: fixed: f0500, f0600 and R0900 in land.spec now carry `slug:` (`elsewhere`, `ready`, `draft-raft`), as `store.find` requires. The reviewer's stand-in run showed that every case then reaches `tracker.sh land`. The run is recorded in c0780's Unknowns & experiments. consequences: none (fixture text only). The fix is minor (no new rule, interface, spec case or Rules row), so by c0770's rule the review stops here, with round 4 of 5 for c0780 and c0790 as the final round.
