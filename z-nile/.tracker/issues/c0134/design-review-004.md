# Review 004: c0134 (design mode)
Inputs: prep `prep-c0131-accept-header` at eac696be (c0134.md, check.sh, acceptance/{header.spec,split,body}.luau, design-review-003.md, design-refute-003.md, harvest.md, zz-test/lessons/no-vacuous-pass.md); z-nile/lib/ac.sh; `./zn capture c0134`. Runs in a scratch clone of eac696be whose origin is a scratch bare copy of the repository, with the Design's header applied to `z-nile/tests/acceptance/c0131/accept.spec.luau` exactly and committed.
Dropped from review-003: F1 (fixed: each body is written to a file by a command whose status is checked, then `cmp`), F2 (fixed: the tip comes from `git ls-remote origin refs/heads/main`, must be a local commit, and the local ref is never read).

Runs (each through `./zn check c0134`, AC2's line quoted):
- The fix as designed: `3/3 criteria passed`; `z-nile/.cache/c0134-ac2/{base,now}` written, `git status --short` empty.
- M5, a code line appended and left uncommitted: `FAIL AC2 … 67a68 > _G.m = true … changed below its header`.
- M12, the same line committed and `git update-ref refs/remotes/origin/main HEAD`: `FAIL AC2`, the same diff. The local ref is not read.
- M11, `body.luau` replaced by `error("boom")` with the line appended: `FAIL AC2`, lune's `boom` traceback. The old `diff <(…) <(…)` form passed this.
- Offline, origin set to a path that is not a repository: `FAIL AC2`, `Could not read from remote repository`.
- Residual, not a finding: `git remote set-url origin <a bare copy whose main is HEAD>` over a committed body edit turns AC2 green (AC3 then failed only because my line was a syntax error after `return`). That is the same accepted, detect-by-review residual as c0115's trusted base (zz-review/sequestration-reference-not-a-ref, review 008): a swapped remote shows in the code review's own fetch and in the branch's config, and E3 doesn't claim otherwise.

Repository safety (item 9, the check.sh's own commands, which the runner can't see): ac.sh cds to the item's home (`z-nile/`) or exits, so `out=.cache/c0134-ac2` resolves to `z-nile/.cache/c0134-ac2`, the home's `.cache` that ac.sh names as the place a check.sh's fixtures go and that `.gitignore`'s `.cache/` ignores. `rm -rf "$out"` is a fixed relative path under it and runs only after that cd. No repository is created there, so the fence's "no repository in any `.cache`" holds. The git commands on the real checkout are reads (`ls-remote`, `cat-file`, `merge-base`, `rev-parse`, `show`); the `git fetch origin` is only named in a message, never run. `set -o pipefail` is set inside the function, which `check` runs in `$(…)`, a subshell, so it doesn't leak to AC3. Nothing reaches the real repository.

Lessons (item 10): the round's two harvest lines are right. The no-vacuous-pass addition is a rule another raft can fail (any `diff <(a) <(b)` of two producers), not a restated finding.

Scope (item 11): the Problem matches the capture; the comment-only header fix is met by AC1 and AC2. Nothing dropped.

No findings.

Verdict: approve
