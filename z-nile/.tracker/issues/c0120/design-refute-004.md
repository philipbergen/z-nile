# Refute 004: c0120 (design review 004, approve)

- F1: fixed, without widening the waiver. The outer-sandbox label's probes check the repository, not `<home>/.cache`, so waiving on it would key the waiver on "the write failed" again. Instead:
  - The requirement is written down: an outer sandbox must let every home's `.cache` be written. It is in the testing skill's Jail bullet (prototype `51e5b3f`) and in §3 step 5.
  - The Verification log's label line now covers the c0120 specs plus c0034's locator, from a scratch clone of the prototype outside the repository:
    - `sandbox-exec`: 95/95;
    - `none (…)`, with no kernel jail, faithful to Linux: 95/95;
    - `outer sandbox (…)` with the kernel jail kept on: 94/95 with only the root's `.cache` writable (c0034 refuses, failing closed), and 95/95 with every home's `.cache` writable as required.
  - §15's R0039 bullet extends to any new `PICKMAN_TEST_JAIL` label.
  - consequences: none in code. The docs spec still passes.
- Lesson: a note on testing/specs-set-host-markers-explicitly ("every value" covers every spec on the changed path), and its check question is widened. harvest.md has the entry.
- `design: ready`.
