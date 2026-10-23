# Refute 012: c0115 (design mode)
Answers `design-review-012.md` (approve, three lows). Every experiment ran in scratchpad clones whose origin is a local bare repository.

- F1: fixed. `trusted-base.luau` reads the URL with `git ls-remote --get-url origin`, which applies `insteadOf`.
  - `--print` prints it on a second line, `from <url>`. `rewrite-finished` prints `main's tip read from <url>`. AC13's `moves_only` echoes it.
  - c0115.md's AC13 text and §8 name the limit: an origin swapped before the run is review's to catch, under the user's "detect, not prevent".
  - `trusted-base.spec`'s honest case also checks the URL line (7 passed).
- F2: fixed in the scan only, as recommended. `linkScans` counts `.claude/skills` as bare when it is followed by an optional `/` and then a non-name character, or by the line's end, so `../.claude/skills/` and `…/skills/*` count. Rule 1b is unchanged.
  - `rewrite-finished-sim.sh` gained the two c0198 forms (finished on the branch: `grep -rn x ../.claude/skills/` and `…/*`). Both are red, with "a recursive grep still reads the .claude/skills links".
  - All 23 cases end as expected.
- F3: fixed. c0137's Problem names c0069 `check.sh:41` and the search that finds all five:
  - the search: `git grep -nE '(^|[ "(])\.claude([ /"]|$)' -- 'z-nile/.tracker/*/done/*/check.sh'`;
  - rerun at d6874ef2, it lists the five plus R0025:19, which is RC2's grep pattern, deleted by c0115;
  - landed on main with `tracker.sh land` (gate passed).
- Lesson: the reviewer's candidate is a new lesson, review/lists-paste-their-search. F1 and F2 add notes to ticket-prep/exact-checks-compare-against-the-merge-base and testing/no-vacuous-pass.

`design: ready`. c0115 waits for c0114 and c0120 to land before it is readied.
