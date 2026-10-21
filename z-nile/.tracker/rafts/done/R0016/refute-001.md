# Refute 001: R0016

- F1: fixed accade2: merged `origin/main` into the branch and re-prepped c0048 on main's `scripts/setup.sh --tools` (human decision): `setup.sh` and `SETUP.md` are main's again, `PICKMAN_SKIP_GATE` and its spec are gone, `board.yml` runs `scripts/setup.sh --tools` with only `GH_TOKEN`, c0048's spec and AC3 were rewritten (AC3 reruns main's `c0015/tools.spec`), and design review 005 (Opus) covered the change; its two mediums and two lows are answered in `design-refute-005.md`. The merge is clean.
- F2: refuted: stream reviews are a cheap first filter, not review rounds; `tracker.sh done` and `metrics` ignore `stream-review-*` files and their findings need no answers (execute-raft Phase 2B step 7). The one low finding in `stream-review-c0047-001.md` was optional.
