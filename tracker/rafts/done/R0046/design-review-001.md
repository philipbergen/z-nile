# Review 001: R0046 (design mode)
Inputs: prep worktree at fd043a6f plus uncommitted prep edits (`tracker/rafts/R0046/R0046.md`, `tracker/rafts/R0046/check.sh`, `tracker/issues/c0129/c0129.md`, `tracker/issues/c0129/check.sh`, `tracker/issues/c0129/acceptance/{submits,onagain}.spec.luau`); capture aa1c6c51 (`scripts/tracker.sh capture c0129`); prototype `proto-c0129` 4dee6b78 (base 83731666; origin/main is now 7ac10dd9, whose new commits touch only tracker spend, no `src/`, `tests/` or `scripts/` file).

What I ran:
- Both acceptance specs in the prep tree (main's code): 1 passed (AC2), 3 failed (the AC1 cases). This matches E2.
- The same specs copied into the prototype under `.cache/`: 4 passed, then removed.
- `scripts/tracker.sh promote-check R0046`: OK (9 passed type check and meta).
- `lune run scripts/affected -- src/server/Submits.luau`: 30 lines. `grep -rlF Submits tests/acceptance` finds only `f0025/sessions.spec.luau`, whose `again` is on its own recorder runs (line 188), never on the real Submits. So `Overrides: none` holds.

Scope: the capture's outcome ("Remove Submits.again or reword it, keeping Hiscores.onAgain") is designed as removal, which is one of the captured options. It is AC1 (removal) and AC2 (onAgain kept). The Problem is unchanged and nothing is dropped.

### F1 [low] The `.again(` scan misses the method and assignment forms of a hook in other server files
Where: `tracker/issues/c0129/acceptance/submits.spec.luau`, third case; Design bullet "No server source defines or calls a `.again(` hook"
Evidence: the pattern `%.again%s*%(` doesn't match `function Runs:again(s)`, `runs:again(s)`, `X.again = function(s)` or `runs["again"](s)`. In Submits itself the exports case catches every definition form. A hook re-added to Sessions with a colon would pass AC1, though.
Critique: the Design sentence says "defines or calls", and the check covers only the dotted call and definition form. The tempting fix is a longer pattern list.
Consequences: a broader pattern such as `[%.:]again%s*[%(=]` stays cheap. It must not match `Session.playAgain(` or `Game.playAgain(`, and it doesn't, because the character before `again` there is `y`. Neither file is under `src/server`, so there is no false-red risk today.
Recommendation: optional. Widen the pattern to `[%.:]again%s*%(` plus `%.again%s*=`, or reword the Design bullet and the case label to "calls or defines `X.again(`". Either way the label and the command agree (`ticket-prep/spec-design-correspondence`). Re-run the M4 mutant with a colon form if you widen it.

### F2 [low] The failing `.again(` case doesn't say which file failed
Where: `submits.spec.luau`, third case
Evidence: on main the case reports `expected deep-equal values, got table: 0x0000000c290e3a00`. The `{ path = …, calls = … }` table was meant to name the file, but `t.expect(...).toEqual` prints only a table address.
Critique: whoever re-adds a hook has to bisect `src/server` by hand.
Consequences: none.
Recommendation: optional. Assert on a string, for example `t.expect(if found then path else "").toBe("")`, so the failure prints the path.

Lesson candidates: none new. Both findings are instances of `ticket-prep/spec-design-correspondence` (F1) or plain spec ergonomics (F2).

Verdict: approve
