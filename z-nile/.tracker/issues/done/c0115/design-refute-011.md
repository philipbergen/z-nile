# Refute 011: c0115 (design mode)
Answers `design-review-011.md`. Every experiment ran in scratchpad clones whose origin is a local bare repository holding the c0120-done base (d6874ef2) as main.

- F1: fixed. One trusted base, `experiments/trusted-base.luau`, serves AC13 (`moves_only` runs it with `--print`) and AC14 (`rewrite-finished` requires it).
  - It takes main's tip from `git ls-remote origin refs/heads/main` and never reads `refs/remotes/origin/main`. It is red when ls-remote fails or prints nothing, when the tip isn't a local commit ("fetch origin"), or when there is no merge-base. The empty range is merge-base == HEAD.
  - `acceptance/trusted-base.spec.luau` (7 cases, in a fixture with a bare origin, run by AC14):
    - an honest clone gets the merge-base;
    - a ref forged to HEAD, or to the branch's own commit, is never read;
    - an unfetched remote main is red;
    - an unreachable origin is red;
    - an unrelated history is red;
    - on origin's main the range is empty.
  - `rewrite-finished-sim.sh`, now with a bare origin:
    - the branch weakens c0004 AC1: red, also with the ref forged to HEAD, and forged to the edit commit with one commit more;
    - main moved but not fetched: red; fetched and merged: green;
    - origin unreachable: red;
    - AC13 with a skill renamed outside the moves commit: red, also with the ref forged to HEAD;
    - every round-10 case: unchanged.
  - Mutant M71 (the helper reads the local ref again): killed. An origin URL swapped before the run stays on review's list.
  - Lesson: ticket-prep/exact-checks-compare-against-the-merge-base, extended (the base comes from the remote).
- F2: fixed. `--check` also lists every finished `check.sh` at the base, under the base's own roots (its `z-nile/projects.toml`). Each one missing at HEAD at the same path is red: `<file>: at the base, gone at HEAD`. The HEAD-side loop is unchanged.
  - In the sim: B (`git rm` c0004's check.sh), C (c0006 renamed to c0206 with AC1 swapped for `AC9: any`) and C2 (c0006's check.sh moved to `issues/c0006x/`) are red.
  - Main deleting c0007 and renaming c0008, merged, is green. c0199 finished on main and merged, after 5c, is green.
  - M72 (the listing dropped): killed.
- F3: fixed under G13's decision ("carry"). Rule 1c rewrites a bare use of a rule-3 variable (`"$S"`, `$S`, `"${S}"`) to every real skills folder, unquoted. On today's tree only c0084:60 matches.
  - An independent scan in `--check` is red for any finished `check.sh` with a recursive grep (`grep -…r…`) over a bare `.claude/skills` or such a variable. Before rule 1c ran, it found c0084 line 60 only.
  - With `--time 0` planted in `zz-rules`, c0084 AC6 is red; without the plant it is green. M70 (the operand back to `"$S"`): killed.
  - Lesson: testing/no-vacuous-pass, a note added.
- F4: captured and landed as c0137 ("Finished .claude scans pass vacuously from z-nile/", chore), with c0044:56, c0067:56, R0025:15 and c0067:44. c0115 isn't widened.

Mutants M62 to M72 against `--check` (and M71 against the spec), in the bare-origin clone: all killed.
