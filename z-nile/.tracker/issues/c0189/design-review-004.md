# Review 004: c0189 (design mode)
Inputs: prep worktree `prep-fixture-identity-guard` at 6e7fc1aa plus its uncommitted prep (`c0189.md`, `check.sh`, `acceptance/*.spec.luau`, `experiments/*`, `design-review-001..003.md`, `design-refute-001..003.md`, `harvest.md`); `./zn capture c0189` (b946a0cd, no markers; the Problem's elaboration and the Solution bullets came in b7b14ea1 on main before prep, and the captured sentence is back verbatim). `origin/main` is 363c8b66, and `git diff 6e7fc1aa origin/main` is empty for every Touched path and for `z-nile/tests/lib`, so the prototype's base is still today's main. I worked in a throwaway clone under `$TMPDIR` (origin removed) with `experiments/prototype.patch` applied and committed there as `rev@example.invalid`. Small repositories beside it (`rb`, `pk`, `pk2`) held the hook from the patch. The real repository was only read (`for-each-ref`, `log`, `rev-list`, `worktree list`, `ls` of `.git/refs/heads`, `packed-refs`). The temporary folder was deleted at the end.
Runs on the prototype in the clone: `hooks-command.spec` 20/20; `repo-hook.spec` 16/16 (with the F1 fix sketch applied too); `repo-fence.spec` 10/10, with the four specs moved to `z-nile/tests/acceptance/c0189/` as `done` would place them (prep only ran it with them sequestered).
Dropped from design-review-003: F1, F2, F3, F4, F5, F6. Their answers hold:
- F1: `--first-parent` is in `cmd.hooks`, and the case "only a text main itself held…" passes. The premise it was written on is wrong, though, which is F2 below.
- F2: `cat-file blob` raw bytes are installed. The "installed bytes are the blob's" case passes.
- F3: my own census matches E1's re-run exactly. Author or committer, every ref under `refs/heads`, `refs/remotes` and `refs/tags`: `proto-f0143-deps` 3, `proto-f0147` 10, `proto-wall-picks-base` 4, `-base2` 7, `-base3` 3, `-touch` 1. No commit has a fixture committer alone. No detached worktree HEAD sits at a fixture commit. No remote-tracking ref holds one. The hint line and the rebase case are in. F1 below is a hole in that hint.
- F4: the temporary file comes from `mktemp` in `<dir>`. The row is reasoned, as recommended.
- F5: stated as a known limit, which the review allowed.
- F6: carried to the lead, which is the right route for a prep that may not write lessons.

### F1 [medium] On a branch whose tip is a fixture commit, `git rebase --abort` (round 3's way out) is itself refused, so the session is left mid-rebase while the message tells it to abort again. E6's "which no tool does" is false, and the same update makes `pack-refs` pack nothing
Where:
- The hook's `awk`: an update counts when `$1 != $2`.
- The message line "If this stopped a rebase or cherry-pick …: git rebase --abort …".
- Existing work: "Refused … `rebase`, `pull --rebase` …", "`repo-hook.spec` pins the rebase …".
- E6: "An `update-ref` of an old branch to the value it already has (old not given) is refused too, which no tool does".
- E12: "a gc refuses to pack them (… gc itself exits 0)".
- Risks: "Routes the hook cannot see".
- AC1: "allows … a no-op update, a branch that already sits at a fixture commit".
Evidence: in `rb` the hook was installed and `proto` was a branch whose tip is a fixture commit (base, `fx1`, `fx2` under `proto@example.invalid`), as `proto-wall-picks-base3` is today, checked out in the live `.worktree/proto-wall-picks-touch`. `main` had moved on.
- `git rebase main`: `Rebasing (1/2)`, then the refusal with the hint, rc 128, `interactive rebase in progress`. This is expected.
- `git rebase --abort`: refused again. The hook received `0000000000000000000000000000000000000000 b99b2837… refs/heads/proto`, which is the branch's own current tip with the old value unspecified. Its message named `refs/heads/proto` and repeated "git rebase --abort", rc 128. The rebase was still in progress and HEAD was still detached. `git pull --rebase` (with `pull.rebase=true`) behaves the same.
- By contrast, `git reset --hard` sends `<tip> <tip>` (old = new), and `stash` passes. That is why the existing no-op case, which uses `stash`, can't see this.
- The real way out today is `git checkout -f proto`, then `git rebase --quit`. I ran it: clean, `On branch proto`. `git rebase --quit` alone leaves a sequencer state, and `git switch` then refuses ("cannot switch branch while cherry-picking").
- `pack-refs`: in `pk2`, with one loose fixture-tip ref and one loose ordinary ref, `git pack-refs --all` exited 128 and packed **nothing**: both refs stayed loose. E12 recorded only "the refusal is printed; gc itself exits 0". With the fixture-tip refs already packed (the real repository today: all four are in `packed-refs`), `pack-refs` sends only the loose refs and passes, so today's repository is not affected.
Critique: the Design's rule is "a no-op update is allowed", and the hook implements it on the line's text (`old = new`). git writes a same-value update in two forms, `<v> <v>` and `0000 <v>` (old not verified), and E6 accepted the second form as refused on the claim that no tool sends it. Two tools do: `rebase --abort`, and `pack-refs` for every loose ref. So AC1's allowed side ("a no-op update, a branch that already sits at a fixture commit") is broken by a common command, and the spec stays green. Round 3's hint then turns this into a loop. The session is told to run the command that just failed. An agent following AGENTS.md stops and asks the user, the cost the chore exists to remove. A careless one goes after the hook or the shared git configuration. The tempting fix is message-only: add "if the abort is refused too, `git checkout -f <branch>` then `git rebase --quit`". That leaves the hook refusing a write that changes nothing, and leaves `pack-refs` stuck whenever a rename or copy (G4) makes a loose fixture-tip ref.
Consequences: judging "no-op" by the ref's current value instead of the line's `old` field has these effects:
- A `0000 <v>` update of a ref that already holds `<v>` passes. That covers `rebase --abort` on a fixture-tip branch, and `pack-refs` of loose fixture-tip refs (so E12's gc refusal and the "gc prints the refusal" Risk go away).
- A creation (the ref doesn't exist) and a move of an existing ref to a fixture commit stay refused.
- The read happens only on the slow path, after a fixture identity has matched: one `git rev-parse -q --verify <ref>` per update kept, so an ordinary update costs nothing more.
- During `prepared` the ref is locked but not yet written, so `rev-parse` reads the pre-transaction value. For `HEAD` in a linked worktree, the hook runs in that worktree, so `rev-parse HEAD` resolves its own HEAD.
- A same-value write creates no ref the tripwire could newly see, so nothing it catches gets through.
I sketched it as five lines before the `peeled=` step: filter `updates` to the lines whose ref's current value differs, and exit 0 if none are left. Results:
- `rebase --abort` rc 0, `On branch proto`.
- `update-ref refs/heads/newref <fixture>` rc 128.
- `update-ref refs/heads/main <fixture>` rc 128.
- A fixture commit on top: refused.
- Same-value `update-ref` rc 0.
- `pack-refs --all` rc 0, every ref packed.
- `repo-hook.spec` 16/16, because its direct-drive refusal uses the nonexistent `refs/heads/x`, so it stays red as it should.
Recommendation:
- In the hook, drop an update from the refusal when the ref already holds the new value (read on the slow path only). The Design's "What it considers" then says a no-op is "an update whose ref already holds the new name (either `old = new`, or old unspecified)".
- Correct E6 (`rebase --abort` and `pack-refs` send `0000 <current>`, and both now pass), E12 and the Risk ("gc then prints the hook's refusal" no longer holds).
- Keep the hint line as it is: `git rebase --abort` is then true for both kinds of branch.
- `repo-hook.spec` (spec, not check.sh: this is a rule of the hook): the rebase case gains a fixture-**tip** branch, where `rebase main` is refused part-way and `git rebase --abort` exits 0, the branch is checked out again at its tip, and no rebase is in progress. Add a `pack-refs --all` with a loose fixture-tip ref that exits 0. Also add a direct drive of `{ZERO} {fx} refs/heads/<existing ref at fx>` that passes, beside the existing `refs/heads/x` refusal.
- Rows and mutants:
  - "a same-value update with old unspecified is allowed": mutant "judge by the line's old field" (the prototype as it is), run.
  - "a creation at a fixture commit is still refused": mutant "skip every update whose old is zero", which the existing `update-ref`, `branch`, `tag` and `worktree add -b` cases kill. Run it to prove that.
Lesson: z-design/prove-specs-pass-on-a-prototype (round 2's candidate, carried to the lead in refute 003 F6: "for each command that creates or moves a ref, what did a logging hook receive …"). E6 judged a transaction form without logging the commands that send it, so the candidate applies to the commands that recover from a refusal as well.

### F2 [low] "PRs land here as merge commits" is false: PRs land by `gh pr merge --squash` and captures by `commit-tree` on `origin/main`, so the stated dependency of "reviewed" is the wrong one
Where: Design, "\"Reviewed\" means a text main itself held" ("PRs land here as merge commits … This relies on this repository's merge-commit flow …"); `hooks-command.spec` "only a text main itself held…" (its fixture merges with `--no-ff`).
Evidence: `git rev-list --merges --count origin/main` is 4 out of 1,210 commits. Only one merge is on the first-parent chain (`3d5f138c Merge pull request #152`, an early PR). 169 first-parent subjects end in `(#<n>)`, GitHub's squash form. zz-rules Merging step 3 says "with `gh pr merge --squash`". `cmd.land` pushes `commit-tree HEAD^{tree} -p <origin/main>`, which is one commit with nothing merged. Review 003 F1 drew its premise from `git log --merges` showing #152.
Critique: the code is right. Under squash, `--first-parent` changes nothing, and it still guards an old merge like #152 or a future `--merge`. But the Design names the wrong dependency. The thing that would put an unreviewed text on main's chain is a PR merged by rebase, or a direct push of a branch with several commits, not "a change of the merge-commit flow". The case models a flow this repository doesn't use. A later reader who trusts the paragraph could drop `--first-parent` as pointless or keep a wrong rationale.
Consequences: none for behaviour. The paragraph's last sentences (shallow or rewritten `main` fails closed) still hold.
Recommendation: rewrite the paragraph. PRs land by squash (zz-rules Merging) and captures by `./zn land`'s single commit, so main's first-parent texts are each a reviewed tip. `--first-parent` also keeps out the work-in-progress texts of a PR merged with a merge commit (#152 was one). The route that would break "reviewed" is a rebase-merge or a direct push of several commits, which the flow forbids. The spec case stays as it is (it pins the `--first-parent` rule). Its comment can say it models a merge-commit PR.

### F3 [low] The Test plan's "before the code exists" counts are stale
Where: Test plan, last paragraph ("3 of 15 pass", "`hooks-command.spec`'s set-up (1 of 18)"); Implementation step 1 ("3 of 16, 0 of 14, 1 of 20 and 0 of 10").
Evidence: `grep -c 'it('` over the specs gives 16, 14, 20 and 10, matching step 1 and E9's 60, not the Test plan's 15 and 18.
Critique: an executor checking step 1 against the Test plan sees two answers.
Consequences: none.
Recommendation: make the Test plan say 3 of 16 and 1 of 20, as step 1 does (after F1's new cases, update both).

## Other points checked, no finding
- **The new temporary-file and raw-bytes paths.**
  - `sh.run` returns stdout untrimmed (`process.exec`).
  - `replace-file.pl` writes the bytes of stdin to its own exclusive sibling and renames it onto the `mktemp` name.
  - `chmod` and `mv -f` follow. Each concurrent install moves its own complete, executable file, and the rename is atomic for a reader.
  - `git hash-object <common dir>/hooks/…` run from a **linked worktree** (where every session's gate runs) returns the blob id (`8e5556b4…` = `HEAD:<source>`), so the "older reviewed" lookup works outside the main checkout too.
- **Where `./zn hooks` runs.** `zn` always `cd`s to the checkout's root, so `ls-tree`'s and `log -- <path>`'s cwd-relative pathspecs are always root-relative. A `../zn hooks` from `pickman/` can't fall into `none`.
- **Gate contexts.**
  - `./zn land` runs its gate in the capture worktree, which shares the hooks folder.
  - The Merging clone removes `origin` before checkout (zz-rules Merging step 2), so `./zn hooks` there takes the tree's copy.
  - Fixture gates (`gate-homes`) copy no `repo-hooks/`, so the `[[ -f … ]]` guard skips the stage.
- **No tool writes a fixture identity.** `git grep -i example.invalid` outside tests and tracker folders finds only skill prose. The engine, scripts and CI never commit under it, so nothing legitimate is refused.
- **Fixtures can't inherit the hook.** `tests/lib/clone.luau` is a plain `git clone --no-hardlinks`, and nothing passes `--template` or sets `init.templateDir` to the real git directory.
- **The tripwire and the hint's "merge instead".** `fence.luau`'s HEAD rule reads only the gate's own checkout, during the run. Merging a history-holding branch in another checkout trips nothing. A squash merge of the PR keeps fixture commits off main.
- **Packed refs.** The four fixture-tip refs are in `packed-refs`, and `pack-refs` sends only loose refs (`pk`: one call for the one loose ordinary ref), so gc in the real repository is unaffected today. F1 covers the loose case.
- **Identities in the promoted specs.** `repo-fence`'s `identitiesIn` lowercases before matching, and `Mixed@EXAMPLE.Invalid` sits on no `email` line, so the promoted specs scan clean (run above).
- **Guesses G1 to G4.** Each is the user's call, with evidence, options and costs. G4 now names the history-holding branches. c0195 (captured on main during this prep: the fence's ref guard misses `git branch -c`) is the same git limit as E12, seen from the fence. A cross-reference in E12 or G4 would let whichever of the two finds a mechanism cover both. It is not required.
- **Scope.** The captured sentence is verbatim. Prep additions are marked. G3 and G4 put the narrowings to the user.

## Candidate lessons (for the lead to place)
- **zz-arch (or z-design/prove-specs-pass-on-a-prototype): a hook's "no-op" is judged by the ref's current value, not by the line's old field.** Rule: git sends a same-value update as `<v> <v>` or as `0000 <v>` (old unverified: `rebase --abort`, `pack-refs`), so a ref hook that allows no-ops compares the new value with what the ref holds. Why: c0189 design review 004 F1: the hook read `0000 <tip>` as a creation, refused `git rebase --abort` on a fixture-tip branch, and its own hint told the session to abort again. Check: for each recovery command (`rebase --abort`, `cherry-pick --abort`, `merge --abort`, `pack-refs`), what did a logging hook receive on a branch that already sits at a refused commit, and does it pass?
- **zz-review: check the premise a recommendation rests on against the flow's own rule.** Rule: before recommending a fix that depends on how changes land (merge commits, squash, rebase), read the landing rule (zz-rules Merging, `cmd.land`) and count the history (`git rev-list --merges --count`), not one example. Why: c0189 design review 003 F1 cited one merge commit (#152) as the flow, and the Design repeated "PRs land here as merge commits"; the flow is squash (review 004 F2). Check: does the claim about the repository's history hold for its whole first-parent chain?

Verdict: changes
