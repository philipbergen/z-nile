# Answers to design review 005 (R0021)

This was the last design round the user allowed. Both answers below follow the review's own recommendations, and their cases and mutants were run. They have **not** been re-reviewed: that is stated in R0021's report to the user.

- F1: fixed as recommended:
  - **The exception is proven by probes**. `fixtureOfGuarded` now requires that `PICKMAN_FENCE_REAL_GIT` names a repository other than this checkout's own, that none of those repositories or their checkouts is writable from here, that the only writable protected paths are this checkout and its own git directory, and that the checkout lies under a ceiling entry ending in `/.cache`.
  - **The case** keeps the inherited guards and breaks one condition at a time: it clears `PICKMAN_FENCE_REAL_GIT`, or sets a ceiling holding only a non-`.cache` ancestor. Both must refuse. This also fixes the spec's own "clear only the marker" rule.
  - **AC10** now also runs, inside a permissive outer `sandbox-exec`, with an ancestor in the ceiling, and on AC9's copy under `.cache` started from a `check.sh`. Both must refuse before any spec, leaving no lock.
  - **Mutants**: K4 (any ceiling ancestor counts) is killed by the case. K5 (an unjailed outer guard is accepted) is killed by AC10. Round 4's exception itself is killed by both.
  - **Wording** is fixed in c0058's jail section, the testing skill's Jail bullet and R0021's Risks; E23 records the reproduction.
- F2: fixed:
  - **The three `bash -c` blocks** in `fence.spec.luau` run with `cwd = repo`, exit if `source` fails, and refuse unless `git rev-parse --show-toplevel` is the fixture.
  - **AC9 and AC10** first check that they can create a sandbox, and if not they say "run it outside the sandbox you are in", instead of failing with an indirect message.
