Reviewer: claude-opus-5-5

# Review 001: R0116 (code mode)
Inputs: layer R0116/1/c0386 at 6b90fb055 (`git diff origin/main...HEAD`, merge base ec98e4f1c; origin/main fetched at 2ca02661b, which does not touch c0371's spec, the scan or any fence spec); R0116.md and its check.sh; c0386.md, its check.sh, `acceptance/env-fixture.spec.luau`, `acceptance/narrow.py`, `acceptance/watch.txt`, `experiments/prototype.patch`.

No findings.

## What was checked
- **The value is unchanged, byte for byte.** `z-nile/tests/acceptance/c0371/check-paths-homes.spec.luau:695` is `"env " .. '-i grep -qF "src/nothing" "$F"'`. Neither literal holds an escape, so the concatenation is exactly the old `'env -i grep -qF "src/nothing" "$F"'` of the base's line 694. It stays at the same place in the list, between the `timeout -s KILL 10` entry and the `xargs -r` entry, so the loop at line 700 hands `findings` the same seven texts in the same order. The comment at line 694 does not contain the banned name, even lowercased: `bannedIn` (`z-nile/tests/tooling/repo-fence.spec.luau:63-72`) does a plain, case-insensitive substring search, and the source text now reads `env " .. '-i`.
- **Nothing else in the spec changed.** `git diff origin/main...HEAD -- z-nile/tests` is the +2/-1 at lines 694-695 and nothing more. Its changed lines match `experiments/prototype.patch` exactly. The spec's blob at the merge base and on the fetched origin/main is `30054415f642f07218d4f92e7cfaaa20a1565664`, the base the issue pins.
- **The scan is not touched.** The diff changes no file under `z-nile/tests/tooling/`, `*/tests/meta/`, `z-nile/tests/lib/` or `z-nile/lib/`. NAMES (`repo-fence.spec.luau:25-60`, `"env -i"` at line 38), ALLOWED, EXEMPT and EXEMPT_DIRS are as they are on main. The rest of the diff is tracker files: the Verification log line, `results.txt`, the spend records and `acceptance/watch.txt`.
- **Sequestration.** The name-status diff over the tracker's check.sh and acceptance paths lists only `A z-nile/.tracker/issues/active/c0386/acceptance/watch.txt`. `./zn finish` writes that file, and the zz-test skill (Capture) and lesson zz-review/finish-watch-is-generated allow it. It lists `renamed.luau` and `t.luau`, which is what the spec requires, because the layer changes no source file. No spec or check.sh changed.
- **AC2 cannot pass vacuously.** `narrow.py` asserts that the base holds the anchor exactly once and the new lines zero times, and it fails otherwise. Then it compares the whole working file's bytes with `base.replace(ANCHOR, NEW)`. Because the anchor is present, that expected text is never the base itself, so an unchanged file, or a file changed in any other byte, is red. It takes the base from `git ls-remote`, not from the local ref, and a git error raises and exits nonzero. Its five-tab ANCHOR matches the list's indentation (line 693). It runs only read-only git commands (`ls-remote`, `cat-file`, `merge-base`, `show`), so it changes nothing.
- **AC6 cannot pass vacuously.** Its first grep requires the NAMES line `^\s*"env -i",` (line 38), and a missing file fails the `&&`. The `!` guards the second pipeline only. Its limit is that it matches by name: an exemption written without any of its key strings would get past it (a directory-wide `EXEMPT_DIRS` entry for `z-nile/tests/acceptance/`, say, or a path assembled from fragments). That gap is in the sequestered design, and this layer does not open it: the diff does not touch `repo-fence.spec.luau`. I raise no finding for it.
- **AC1 is not vacuous.** `env-fixture.spec.luau` reads c0371's spec by its path, through `renamed.id`. `fs.readFile` errors if the file is missing, and the search is case-insensitive.
- **The seven fence specs really run.** `ac.sh:69` changes into the item's home (`z-nile/`). From there, AC4 and the raft's RC1 run `tests/tooling/repo-fence.spec.luau`, and AC5 changes into each of the six homes in its own subshell, chained with `&&`, and runs `tests/meta/fence.spec.luau`. Each of those six files is a one-line `require` of z-nile's repo-fence spec. Counting the z-nile spec that AC4 and RC1 both run, that is the seven. A missing spec path does not pass silently: run from `z-nile/`, a run of a missing spec ended `0 passed, 1 failed`, exit 1. A failed `cd` stops the chain.
- **Runs on this tree:**
  - `tests/tooling/repo-fence.spec.luau`: 10 passed.
  - `tests/acceptance/c0371/check-paths-homes.spec.luau`: 28 passed.
  - `asteroids/tests/meta/fence.spec.luau`: 10 passed.
  - `./zn check c0386`: 6/6. AC2's base is printed as `https://github.com/philipbergen/pickman.git refs/heads/main`, the expected origin.
  - `stylua --check` and `selene` on the changed spec: clean.
- **Repository safety.** Nothing in the diff writes anywhere, and nothing in it starts a process. The promoted `env-fixture.spec.luau` and `narrow.py` build the banned name from parts. The issue's `check.sh` writes it as `-[i]`, which `bannedIn`'s substring search does not match.
- **Design adherence.** The diff matches the Design and the prototype patch exactly. There is no deviation, and the Verification log says so.

## Judged criteria (code mode only)
- none: c0386's `## Judged` is "none" (and `### Observed` is "none"), and R0116 has no Judged criterion.

Verdict: approve
