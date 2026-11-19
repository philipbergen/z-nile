# Review 005: c0189 (design mode)
Inputs: prep worktree `prep-fixture-identity-guard` at 6e7fc1aa plus its uncommitted prep (`c0189.md`, `check.sh`, `acceptance/*.spec.luau`, `experiments/*`, `design-review-001..004.md`, `design-refute-001..004.md`, `harvest.md`); `./zn capture c0189` (b946a0cd, no markers). `origin/main` is b5bde7ae. `git diff --name-status 6e7fc1aa origin/main` lists only tracker files and `z-nile/next`, so the prototype's base is still today's main for every Touched path and every spec. I worked in a throwaway clone under `$TMPDIR` with `experiments/prototype.patch` applied (`git apply`, nothing committed) and the four specs copied to `z-nile/tests/acceptance/c0189/`. Small repositories beside it (`p1` to `p5`) held the patch's hook. The real repository was only read (`for-each-ref`, `packed-refs`, `ls` of the hooks folder). `repo-hook.spec` on the prototype: 16/16. `./zn promote-check c0189`: fails only on `@znile/engine/hooks` and its types, as E10 says. The temporary folder was deleted at the end.
Dropped from design-review-004: F1, F2, F3. Their answers hold:
- F1: I re-ran the evidence. On a fixture-tip branch, `rebase main` is refused part-way and `rebase --abort` exits 0, back on the branch. `pack-refs --all` packs it. `cherry-pick --abort` after a refused cherry-pick also exits 0, with a clean tree. Mutant K1 is the prototype as it was in round 4. F2 below is a hole in the mechanism this fix added.
- F2: the paragraph now matches zz-rules Merging (`gh pr merge --squash`). `publish.allowed` and `./zn land` push only tracker files, so neither can put a hook text on main. `git rev-list --merges --count origin/main` is 4.
- F3: the counts now agree.

### F1 [medium] A refused `checkout --detach`, `switch -c`, `reset --hard` or fast-forward `merge` has already put the fixture commit's files in the index and working tree. The next ordinary commit (which the hook allows) records them and reverts newer work. The message says nothing about this, and its "merge instead" advice fast-forwards into the same refusal
Where:
- Existing work: "Refused … `git checkout --detach <branch>`, `git switch -c <new> <branch>`, … `git merge --ff-only <branch>`, … `reset` onto one".
- E6: "(exit 128 each …)".
- The hook's message, which has a hint line for a rebase or cherry-pick only.
- The Problem: "the session that tries is told at once what to do instead".
Evidence (`p1`, `p3`, with the patch's hook; `main` = base + `m`, `fx` = base + `f` under `proto@example.invalid`):
- On `main`, with an unstaged edit to `a`, `git checkout -q --detach fx` gives rc 128 and HEAD stays on `main`. `git status --short` then shows ` M a`, `A  f` and `D  m`. `git commit -qam "my work"` under `real@normal.test` gives rc 0, and `git show --stat HEAD` lists `a | 1 +`, `f | 1 +` and `m | 1 -`. So the fixture commit's file landed on `main` and `main`'s newer file was deleted, under an ordinary identity.
- `git switch -q -c new fx` (rc 128) leaves the same `A f` / `D m` state on `main`, and `new` is not created.
- `git merge --ff-only fx` and `git reset --hard fx` on a branch at base (rc 128 each) leave `A  f`.
- On a branch `behind` that is an ancestor of `fx`, a plain `git merge fx` prints `Fast-forward`, is refused, and leaves `A  f`. `git merge --no-ff -m m fx` passes.
- Recovery: after the refused checkout, `git reset -q --merge` gives rc 0. The status is then only ` M a`: the user's own edit stays, and `f` and `m` are back as in HEAD.
- But after a refused **commit** of staged work (`p4`), the same `git reset --merge` deleted the staged edit to `a` and the new file `n`. So a hint that names `reset --merge` for every refusal would destroy the work of the most common refused command.
Critique: git updates the index and working tree before it writes the ref, so the refusal comes too late to keep the tree clean. The hook can't undo that. Every one of these commands targets the old `proto-*` branches, which live in other sessions' worktrees today. A session that runs one sees "refused", reads "commits under your own identity", and does exactly that. The resulting commit is allowed and silently carries the prototype's tree. That is a wrong result made more likely by this change. Before the hook, the checkout simply succeeded. E11 printed only exit codes, so nobody saw the leftover state. The "merge instead" advice is right for the rebase it was written for (both sides have moved). Existing work's "a `merge` of one into another branch … allowed" is wrong when the merge is a fast-forward. The tempting fix is to add "`git reset --merge`" to the message, which destroys a refused commit's staged work (above).
Consequences: the hook can't tell a commit from a jump by the ref line alone (both are `<old> <new> HEAD`). It could compare `new^` with `old`, but that is a new rule with merges and roots as edge cases. A hint that names the commands it applies to needs no new rule. Every tree-changing route writes `HEAD` (directly, or through a symbolic `HEAD` beside the branch line), so printing the line only when `HEAD` is among the refused refs keeps it off fetches, `update-ref`, `branch` and `tag`. It still shows on a refused commit, so its text must say it is not for a commit.
Recommendation:
- Add one message line, printed only when `HEAD` is among the refused refs: "If this stopped a checkout, switch, reset or fast-forward merge (not a commit), git has already changed your files: `git reset --merge` puts them back and keeps your own edits. Merge a prototype branch with `git merge --no-ff`; look at one with `git worktree add <dir> <branch>`."
- Correct Existing work: "a `merge` of one into another branch" becomes "a `merge --no-ff` (or any merge that is not a fast-forward)". Also say what a refused checkout, switch, reset or `--ff-only` leaves behind.
- Correct E6 to record the leftover state.
- `repo-hook.spec` (a spec, not check.sh: this is a rule of the hook's message): in the old-branches case, from the worktree on `legacy` before its ordinary commit, `checkout --detach` a fixture commit that is not its tip. Expect rc ≠ 0, the new hint line, then `git reset --merge` and an empty `git status --porcelain`. A direct drive of a fetch refusal must not print the line.
- Rows: "the checkout hint is printed when HEAD is refused", with mutant H18 (the line missing), and "and only then", with mutant H18b (the line always printed), killed by the fetch case. Both run.

### F2 [medium] Round 4's "the ref already holds the new value" is read in the hook's own worktree, but `git worktree add` writes the new worktree's `HEAD` from the caller's process. From a checkout sitting at a fixture commit, `git worktree add --detach <dir> <branch>` (or `<dir> <sha>`) passes, though Existing work and AC1 say it is refused
Where:
- The hook: `[ "$(git rev-parse -q --verify "$ref" 2>/dev/null)" = "$sha" ] || printf …`.
- Design, "What it considers" ("during `prepared` the ref is locked but not yet written").
- Existing work: "Refused … `git worktree add --detach <dir> <branch>`".
- AC1: "any update of `HEAD` …".
- Rows K1/K2.
Evidence (`p2`, the patch's hook behind a logging wrapper that prints `pwd`, `GIT_DIR` and `git rev-parse HEAD`):
- From `main`: `git worktree add --detach ../w2a fx`. The hook ran in `p2` with `GIT_DIR` unset and `HEAD` = main's tip, and received `0000… cd462983… HEAD`. Refused; no `w2a`.
- After `git switch fx` (so the calling checkout's HEAD is the fixture tip `cd462983`): `git worktree add --detach ../w2b fx`. The same first transaction, `0000… cd462983… HEAD`, again ran in `p2` (`pwd=…/p2`, `GIT_DIR=unset`), and `rev-parse HEAD` there returned `cd462983` = new. The update was dropped as "already holds", and the hook passed. Only the later `<v> <v> HEAD` transaction ran in the new worktree's context (`GIT_DIR=…/.git/worktrees/w2b`). Result: `git worktree list` shows `w2b cd46298 (detached HEAD)`.
- `git worktree add ../w2c cd462983` (a sha) behaves the same: created, detached at the fixture commit.
- Today, `.worktree/proto-wall-picks-touch` has `proto-wall-picks-base3` (a fixture tip) checked out, so a session there gets the same result.
- No case covers it. `repo-hook.spec` drives `worktree add -b` only, from `main`.
- Variant I ran: the current-value test skipped for `HEAD` (and the per-worktree `refs/bisect/`, `refs/worktree/`, `refs/rewritten/`), so `HEAD` keeps only the line's `old = new` test. `repo-hook.spec` 16/16, including the fixture-tip `rebase --abort` and `pack-refs`. All three `worktree add` runs above are refused, and no folder is left.
- (A first try put a `case … esac` inside the `$( … )` loop: macOS's `/bin/sh` rejected it, and the hook then refused everything. That is E4's bash 3.2 trap. Use `[ … ]` tests there.)
Critique:
- `HEAD` is the one ref name whose value depends on which worktree reads it. The hook reads it where git ran the hook, which for `worktree add` is the caller, not the worktree being written. Review 004's consequence ("For `HEAD` in a linked worktree, the hook runs in that worktree") holds for commands run inside the worktree, not for this one.
- This is the second hole in the hook's no-op rule (review 004 F1 was the first). So the mechanism should be narrowed to what it is for. Both tools that need it (`rebase --abort`, `pack-refs`) send `0000 <v>` for a **branch** (a shared ref, the same from every worktree), never for `HEAD`. `HEAD`'s same-value writes all come as `<v> <v>`, which the `awk` already passes.
- Why medium, not high: the ref that gets through is a worktree's detached `HEAD`. The tripwire reads only refs (`for-each-ref`), its own checkout's `HEAD` and worktrees under `.cache`, so no running gate trips on it. The commit is also already the caller's `HEAD`. The Problem's outcome holds. The stated rule (AC1, Existing work) does not.
Consequences of excluding `HEAD` from the current-value test:
- `git checkout --detach` while on a fixture-tip branch is still `<F> <F> HEAD` and passes.
- A rebase started on a **detached** `HEAD` at a fixture commit can't be aborted (the abort really moves `HEAD` from the new base back to the fixture commit). Review 004's census found no detached worktree `HEAD` at a fixture commit. With this fix, `worktree add` can't make one, so only one made before the hook could hit it. Say that in Existing work, beside the abort sentence.
Recommendation:
- In the hook, apply the "already holds" test only to refs under `refs/` outside the per-worktree namespaces (`refs/bisect/`, `refs/worktree/`, `refs/rewritten/`). `HEAD` stays judged by the `awk`'s `old = new`. Write it with `[ … ]` tests, not `case`, inside the `$( … )` loop.
- Design, "What it considers": say why (git may run the hook in another worktree than the one whose `HEAD` it writes).
- `repo-hook.spec` (a spec: a rule of the hook): in the old-branches case, from the worktree on `legacy` (its `HEAD` at the fixture commit, before its ordinary commit), `git worktree add --detach <dir> legacy` is refused and leaves no folder and no new `git worktree list` entry.
- Row: "a worktree add at a fixture commit is refused even from a checkout already at it", mutant K3 (the current-value test applied to `HEAD`: the prototype as it is), run.
Lesson: zz-arch/guards-decide-from-the-tools-resolution (the hook resolves `HEAD` in its own context, not the one git is writing).

### F3 [low] Two texts no longer match the hook: Scalability says "no loop over refs in the shell", and the row for H7 names a case that doesn't kill it
Where:
- Scalability: "on `prepared`, one `awk`, one `git rev-list` and a subshell: no loop over refs in the shell".
- Rules and mutants: "a no-op update (old = new) is allowed | repo-hook :: …a branch that already sits at a fixture commit | H7 …".
Evidence:
- The slow path runs `git rev-parse` once per update of the transaction (`changed=`), then once per kept update (`peeled=`), in `while read` loops.
- H7 (the `$1 != $2 &&` removed) on the prototype: 15/16, failing only "an object that is not a commit, a pseudo-ref and a symbolic update are allowed…". That case's line `{fx} {fx} refs/heads/same` names a ref that doesn't exist, which git never sends with `old = new`. "…a branch that already sits at a fixture commit" passes under H7, because the current-value test now allows every real `<v> <v>` too.
Critique: the cost claim matters to the user (CPU load). It is still cheap: the loop runs only after a fixture identity has matched, and `pack-refs` in the real repository sends 24 loose refs, none of them a fixture tip. But the text says something else. With round 4's rule, H7 is an optimisation (it saves a `rev-parse`), and the row presents it as a behaviour with a real-input case.
Consequences: none for behaviour.
Recommendation:
- Scalability: "on the slow path only (a fixture identity matched), one `git rev-parse` per update in the transaction".
- Row H7: name the case that kills it and say the input is synthetic (git sends `old = new` only for a ref that holds it), or mark it `reasoned` as a cost guard that is equivalent for every input git sends.

### F4 [low] `git commit --amend` of a fixture commit under the user's own identity is refused again, and the message's "commits under your own identity" doesn't say that `--amend` keeps the author
Where: the message's last line; Existing work ("`commit --amend` of one" refused).
Evidence (`p5`): on a branch whose tip is a fixture commit, `git commit -q --allow-empty --amend -m …` as `real@normal.test` gives rc 128 (the author stays `proto@example.invalid`). `git commit --amend --reset-author …` gives rc 0, with the author `real@normal.test`.
Critique: a session that does what the message says and retries is refused again, with no new advice. That is the round-4 loop on a smaller scale.
Consequences: none beyond a longer message line.
Recommendation: the last line says "… or commits under your own identity (`git commit --amend --reset-author` to take over a prototype commit) …". Add an assertion in the old-branches case that a refused amend's message contains `--reset-author`, with mutant H19 (the words missing), run.

## Other points checked, no finding
- **The round-4 rule against the fence chain.** `z-nile/lib/git-hooks/reference-transaction` pipes the same input to the repository hook from the same process, so `rev-parse` reads the same repository. `repo-hook.spec`'s fence case passes.
- **Locks during `prepared`.** `refs/heads/not-yet` is refused and the existing `stays` passes on direct drive, so `rev-parse` reads the value from before the transaction (files backend, git 2.54).
- **Cost in the real repository.** 24 loose refs and 93 packed lines. The four fixture-tip branches are packed and `proto-f0147` (ordinary tip) is loose, so `pack-refs` and `gc` take the fast path.
- **Main since the base.** 77+ commits, all tracker files and `z-nile/next`. No spec or Touched path moved, so the prototype's evidence holds on today's main.
- **Guesses G1 to G4.** Each states the choice, the evidence and each option's cost, and recommends one. All four are the user's. G2 (push not refused) and G4 (`branch -m`/`-c`) are git's limits, stated as risks. F2 adds nothing to them: it is fixable in the hook.
- **Scope.** The captured sentence is the Problem's first line, verbatim. The title was reworded on main before prep (b7b14ea1), as rounds 1 to 4 noted. The narrowings are G3 and G4, put to the user.
- **Repository safety.** Every spec builds its repositories under the home's `.cache` and copies the hook in. `check.sh` runs only spec files. Step 3 forbids `./zn hooks` in the worktree. Nothing reaches the real git directory.

## Candidate lessons (for the lead to place)
- **zz-arch: a ref hook that reads a ref resolves it in the hook's own context, which is not always the context of the ref being written.** Rule: `HEAD` (and `refs/bisect/`, `refs/worktree/`, `refs/rewritten/`) are per worktree, and git runs `worktree add`'s first `HEAD` write in the caller's process, so a hook decides from them only through the transaction's own fields (`old`/`new`), never with `git rev-parse <ref>`. Why: c0189 design review 005 F2: round 4's "the ref already holds the new value" read the caller's `HEAD` and let `git worktree add --detach <dir> <fixture>` through from a checkout already at that commit. Check: for each ref this hook reads back, is it shared by every worktree, and did a logging hook that prints `pwd` and `GIT_DIR` show every command that writes it running in the worktree it writes?
- **z-design/prove-specs-pass-on-a-prototype: a refusal probe records the state the refused command leaves, not only its exit code.** Rule: for a hook that refuses mid-command, run `git status --short` (and the next likely command) after each refusal. Why: c0189 design review 005 F1: E11 recorded "exit 128" for `checkout --detach`, `switch -c`, `reset --hard` and `merge --ff-only`. Each had already rewritten the index and working tree, and the next ordinary commit recorded the prototype's tree. Check: after each refused route in the experiments, what do `git status` and an ordinary `git commit -a` do?

Verdict: changes
