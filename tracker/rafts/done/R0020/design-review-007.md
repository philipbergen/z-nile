# Review 007: R0020 (design mode)
Inputs: prep worktree `prep-r0200-mktree` at 98984ee (`git diff 5f7868f..HEAD`: c0053.md, check.sh, `acceptance/commands.spec.luau`, `experiments/publish.luau.txt`, R0020.md). I also read: design-review/refute-006; the prototype `proto-r0200-mktree` at a4c4ee7 (`scripts/tracker/publish.luau`); c0058, c0059 and R0021 on `prep-check-isolation` at 30cb08b (read only).

Round 6 was approved, and refute-006 fixed both of its low findings. Nothing is carried over.

How I ran things:
- **Specs**: every spec ran through `tmprun.sh`, in a clone with no origin under `$TMPDIR`, one suite at a time.
- **Mutants**: each was applied to the prototype file, then restored from a byte copy. `git diff --quiet` was clean after each one.
- **Scratch repo** (under `$TMPDIR`, real lune binary): a seed whose root holds `root file.txt` (100755), a tab name, `naïve.md`, `quote"q` and a symlink. `tracker/issues/` holds `odd name/` and an `x<TAB>y` file. There is an `active/c0002/` folder with a sibling `notes.txt`, and an R0001 raft. One `publish.commit` then changed or added five paths across every depth: `issues/<id>`, `issues/active/<id>`, a new `issues/c0003/` (with a 100755 `check.sh`) and a new `rafts/done/R0002/`. **The reference prototype is correct on all of it.** The diff is exactly the 5 paths, every other entry keeps its name, mode and blob (symlink and odd names included), `git fsck --strict` is clean, and the caller's index and status are untouched. Pinned base sha, lease push, and caller HEAD and index are unchanged from round 6, and still hold.

Mutants run, one at a time:
- **MK1** (`makeTree(step, nil, child)`): publish spec 10/14. It is killed, which confirms the E9 record.
- **Existing 100755 entries rewritten as 100644**: publish 14/14, commands 21/23. It is killed by the commands spec only.
- **The ls-tree name parsed as `(%S+)`**: publish 14/14, commands 23/23. **It survives.** See F1.

### F1 [medium] An `ls-tree` record that doesn't parse is dropped without a word, and no fixture has a name that would show it, so a whitespace-splitting parser that deletes files from `main` passes every case
Where:
- `experiments/publish.luau.txt` `makeTree`: `local meta, name = string.match(rec, "^([^\t]+)\t(.+)$")` then `if meta and name then entries[name] = meta end`;
- c0053 Rules row "The tree is built with `mktree` from the base tree, keeping every untouched entry at every level";
- the fixtures: the publish spec seeds only `src/x.luau`, and the commands spec seeds `scripts/`, `tracker/templates/`, `.gitignore` and `.gitkeep`s.

Evidence:
- **The mutant.** I changed only the name capture to `(%S+)`. Publish gave 14/14 and commands 23/23.
- **What it does.** In that mutant, any entry whose name has a space, at any level on a changed path, fails the match. The `if` then skips it, so it's left out of the rebuilt tree, and the push deletes it from `origin/main`.
- **Where that can happen.** The rebuilt levels are the repository root, `tracker/`, `tracker/issues|rafts/`, `active|done/` and `<ID>/`. Today none of them has such a name. But any future root file like `Design Notes.md` would be deleted silently by a tracker `status` move. That push goes straight to `main`, past PR review and CI.
- **The design invites it.** The same "skip what doesn't match" shape turns any parse slip into a deletion: a `trim` on the listing, a `\n` split, a changed regex, a name with a newline. A non-`-z` round trip is not the risk; it would quote and unquote correctly.
- **What isn't covered.** The row's spec cases and E9's MK1/MK2 only kill mutants that drop whole levels. No case keeps an awkward name alive.

Critique: the rule "keeping every untouched entry" has a spec case that can't fail for a plausible mutant. The fix the author will reach for is a fixture file with a space in its name. That pins one parser and leaves the skip-on-mismatch branch in place.

Consequences:
- A loud parse failure adds one more refusal path, with its own message.
- A post-condition costs one more git call. Under "every git call is checked", it must be checked too.
- A change identical to origin's content doesn't show in a diff. So the post-condition must be "changed paths ⊆ the change list", not "equal to" it. An empty diff is already the no-op branch (`tree == baseTree`).

Recommendation:
- **Fail on an unparsable record.** In `makeTree`, a non-empty record that doesn't match `^(%d+) (%a+) (%x+)\t(.+)$` returns `nil, "cannot read origin tree <path>: <record>"`, and nothing is pushed.
- **Check the result before `commit-tree`.** Run `git diff-tree -r --no-renames --name-only -z <baseTree> <tree>`, and check its exit status. Every path it lists must be one of `out`'s paths; any other path fails with `<path> would change: refusing`. This one check also catches MK1, MK2 and any future tree-walk bug, without the specs having to guess the bug's shape.
- **New publish spec case** ("untouched entries keep their names, modes and objects"):
  - the seed gains, at the root, `a b.txt` (100755), a tab name, `naïve.md` and a symlink; and at `tracker/issues/`, a folder `odd name/` with one file;
  - publish one new doc and one status edit under `tracker/issues/active/`;
  - assert that `ls-tree -r -z` of the base and the new commit, minus the two changed paths, are byte-identical.
- **Rules and mutants**: add these mutants to the mktree row and mark them `run`: "names split at whitespace" (killed by the case and by the post-condition) and "an unparsed record skipped".

### F2 [low] "A path whose folder is a file on `origin/main` refuses" has no Rules row and no case, and its message names only the last part of the path
Where:
- c0053 Publisher bullet: "A path whose folder is a file on `origin/main` refuses";
- `makeTree`: `return nil, \`{name} is a file on origin/main, not a folder\``.

Evidence:
- **No row, no case.** No row in the table and no case in either spec covers this rule. Without the check, `sub` is nil and a new subtree replaces the file, so the file is deleted on `main`. Deleting the `if existing and not sub` branch would pass every case.
- **The reverse case is already handled.** When the change path itself is a folder on origin, the existing `read`/`withoutStatus` checks refuse it already.
- **The message.** `name` is one path part (for example `c0010`), not `tracker/issues/c0010`.

Critique: the case is unlikely, since `allowed` fixes the folder names. But it is a stated Design rule with no row, which the Design-mode audit counts as a gap. F1's post-condition would also catch a regression here, as a second line of defence.

Consequences: `makeTree` needs the path so far, which is one more parameter.

Recommendation:
- Pass the folder path down, so the message reads `tracker/issues/c0010 is a file on origin/main, not a folder`.
- Add a publish case: `other` pushes a plain file `tracker/issues/c0010`, and a build returns `tracker/issues/c0010/c0010.md`. Expect `ok = false`, a reason naming the full path, and origin unchanged.
- Add a row with the mutant "the refusal removed (a folder silently replaces the file)".

### F3 [low] `rev-parse <base>^{tree}` is the one git call whose exit status isn't checked, and it is now the input to the tree build
Where: `publish.luau.txt`, `local baseTree = trim(git(cwd, { "rev-parse", base .. "^{tree}" }).stdout)`; c0053: "**Every git call's exit status is checked** and the result must be a hex object name of 40 or 64 digits".

Evidence:
- Before the re-prep, `baseTree` was only compared against the new tree. Now `makeTree(step, baseTree, ...)` lists it.
- A failed call yields `""` or an echoed argument. Today the error shows up only indirectly, as `ls-tree`'s "not a valid object name", so the documented rule doesn't describe the code.

Consequences: none.

Recommendation: check `ok` and the 40/64-hex shape, and fail with `cannot resolve the tree of <base>: <stderr>`. The alternative is to start `makeTree` from `base` itself (`ls-tree` accepts a commit) and compare against a checked tree id. Mark it `reasoned` in the "every git step is checked" row: `base` was just verified as a commit, so no spec can make this call fail.

### F4 [low] AC9 can be passed by a comment, or by putting the index code in a helper module
Where: `tracker/issues/c0053/check.sh`, `no_index()`.

Evidence:
- `grep -q "mktree"` matches the word in a comment.
- The ban is scanned in `scripts/tracker/publish.luau` only. A `publish.luau` that requires `scripts/tracker/plumbing.luau`, and builds the tree there with a private `GIT_INDEX_FILE`, passes AC9.
- R0021's gate scan would catch the variable later. But AC9 exists to prove now that the publisher needs no exception, and a helper module would need one.
- Today nothing else in `scripts/` names `GIT_INDEX_FILE`, `read-tree`, `update-index`, `write-tree` or `mktree` (grep on the prototype). So a wider scan costs nothing.

Recommendation: scan `scripts/tracker/` (recursively) for the banned names. Require `mktree` as a quoted git argument (`grep -qE '"mktree"' scripts/tracker/publish.luau`). Update AC9's text to say so.

### F5 [low] R0020's Order section still calls the fence prep "still R0019"
Where: R0020.md, Order & dependencies, "Where the ids stand".

Evidence:
- The bullet says "The repository fence raft is R0021 (c0058, c0059, c0060), prepped on `prep-check-isolation`".
- The next sentence says that same branch is "the repository fence, c0058, still R0019".
- On `prep-check-isolation` at 30cb08b, the fence is `tracker/rafts/R0021/R0021.md`, and `R0019` there is `main`'s "Renumber step one".

Recommendation: drop `prep-check-isolation` from the "old numbers" list. Re-check `prep-tracker-hardening` against `main`'s R0018 (beta poll), and say what is still pending.

Verdict: changes
