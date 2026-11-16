# Review 003: c0189 (design mode)
Inputs: prep worktree `prep-fixture-identity-guard` at 6e7fc1aa plus its uncommitted prep (`c0189.md`, `check.sh`, `acceptance/*.spec.luau`, `experiments/*`, `design-review-001/002.md`, `design-refute-001/002.md`, `harvest.md`); `./zn capture c0189` (b946a0cd, no markers). `git diff 6e7fc1aa origin/main` (0f4a540a) is empty for every Touched path and for `z-nile/tests/lib`, so the prototype's base is still today's main. I made a throwaway clone of the worktree under `$TMPDIR`, applied `experiments/prototype.patch`, and committed it (as `rev@example.invalid`, in the clone only) to a bare origin there. A second clone `T` of that origin installed the hook with `./zn hooks`. Every probe below ran there or in a small repository beside it (`rb`). `./zn promote-check c0189` fails only on the missing `hooks` module (E10). The real repository was only read (`for-each-ref`, `log`, `worktree list`). The temp folder was deleted at the end.
Dropped from design-review-002: F1, F2, F3, F4, F5. Their answers hold, and I re-ran the evidence for each in `T`/`rb`:
- F3/F4: `update-ref refs/remotes/origin/main <blob>` gives `hooks: cannot read origin/main: fatal: not a tree object` (rc 1). Deleting the ref gives `hooks: origin has no main fetched; run git fetch origin main` (rc 1).
- F5: `git tag -a annot <fixture commit>` names `refs/tags/annot` in both lines.
- F1: an older copy prints the note and exits 0.
- F2: the limit is now stated, and G4 puts it to the user.

F1 and F2 below are new defects in round 2's F1 fix (the "older reviewed copy" rule). The mechanism has now had a hole in each of three rounds, so F1's Recommendation asks what "reviewed" means and doesn't just patch the hole.

### F1 [medium] "Reviewed" is any text in `origin/main`'s whole history, including the work-in-progress commits of every merged branch, so a hand-installed weak copy (here `exit 0`) passes `--check` for good
Where: Design, the `hooks.plan` table row "our file, executable, text differs from the reference but is one `origin/main` has held"; "A legitimate fetch does not turn gates red"; `cmd.hooks` (`git log --format= --raw --no-abbrev origin/main -- <source>`); AC2, AC3 ("an older reviewed copy").
Evidence: PRs land here as merge commits (`git log --merges origin/main`: `3d5f138c Merge pull request #152 …`). In the clone:
1. On a branch `wip`, I committed a copy of the hook with `exit 0` as line 3, then restored it with one comment changed (`v3`).
2. I merged with `git merge --no-ff wip -m "Merge pull request #1"` and pushed.
3. In `T` I fetched, copied the `wip weak` blob to `.git/hooks/reference-transaction`, and ran `chmod 755`.

`./zn hooks --check` then printed `… is an older reviewed copy of origin/main's z-nile/lib/repo-hooks/reference-transaction; run ./zn hooks to update` and exited 0. That hook refuses nothing. The plain `git log --raw origin/main -- <source>` walks into the merged branch and lists `wip weak`'s blob. `git log --first-parent --raw …` lists only the merge's diff against its first parent (`444504f → b4c1e5f`, git 2.54 shows first-parent diffs for merges), and the weak blob is not in it.
Critique: the Design says a text `origin/main` "never held (a hand edit, a branch's copy)" stays red. But every intermediate text of every branch that later merges counts as held, and none of those was reviewed as a whole. That includes a raft's spend-tracked WIP commits and a mutation-test edit that was committed and reverted. The one state the rule was added to keep red, a branch's copy installed by hand, turns green once that branch merges.
Consequences: with `--first-parent`, "held" means "was `main`'s tip text at some point", which is reviewed under this repository's flow (merge commits; tracker publishes are direct first-parent commits). Three side effects:
- A PR merged by rebase on GitHub would put its intermediate commits on the first-parent chain. The flow doesn't use that, so say it.
- A shallow or rewritten `main` loses old texts. That fails closed (red, one `./zn hooks` clears it).
- An older reviewed text that was later fixed because it failed open still passes. That is the Risk "a fix to the hook cannot force itself on gates", already accepted.

Recommendation:
- Read the history with `git log --first-parent --format= --raw --no-abbrev origin/main -- <source>` and define "reviewed" in the Design as "a text `main`'s first-parent history has held".
- Add a `hooks-command.spec` case. A fixture branch commits an intermediate text, then a final one, and merges into origin's `main` with `--no-ff`. The intermediate text installed by hand is red. The final text, after a later change, is green with the note.
- Add a row with mutant "history without `--first-parent`", run.

### F2 [medium] The installed text is `git show` output trimmed and given one `\n`, so the installed file's blob id isn't the reviewed blob's whenever the source's ending changes, and round 2's red-for-every-session failure comes back
Where: `cmd.hooks`: `source = sh.git({ "show", \`origin/main:{SOURCE}\` }) .. "\n"` (`sh.git` is `sh.must`, which returns `trim(r.stdout)`). The "older reviewed" lookup: `blobIds(log)[sh.git({ "hash-object", dest })]`. `hooks-command.spec` `originText()` makes the same normalisation, so no case can see it.
Evidence: in the clone I committed the hook with one trailing blank line added (`printf '\n' >>`) and pushed it. In `T`, `./zn hooks` then `--check` gave `ok`. `git hash-object .git/hooks/reference-transaction` is `1e6b9c36…`, and `git rev-parse origin/main:<source>` is `23650c8a…`. Then I pushed a one-word comment change (v2) and fetched. `./zn hooks --check` gave `… differs from origin/main's …; run ./zn hooks` and rc=1. That is the exact state round 2 F1 removed: every session's gate (and the stop hook's) red after a legitimate fetch, and the fix is a write to the shared git directory. Nothing in the gate requires the hook to end in exactly one newline (`grep -i 'newline\|trailing\|diff --check'` over `z-nile/check.sh` and `c0043/format.spec` finds nothing). The tree path (`fs.readFile`, used in the Merging clone) reads raw bytes, so the two sources differ too.
Critique: the "older reviewed" rule compares blob ids, but the install writes a normalised text. They agree only while the source ends in exactly one `\n`. An editor that drops the final newline, or leaves a blank last line, plants the trap for the next hook change.
Consequences: installing the raw blob makes the installed file's id equal to a blob of `origin/main`, always. Comparing by blob id (`hash-object dest` against `rev-parse origin/main:<source>`) instead of by text removes the second normalisation as well. The spec's `originText()` must read raw bytes too, or it keeps hiding the bug.
Recommendation:
- Read the reference with `sh.run("git", { "cat-file", "blob", "origin/main:<source>" }).stdout` (untrimmed; a failure goes to the same `cannot read origin/main` error) and install those bytes.
- Judge "exact" and "older" by blob id.
- Change `originText()` to raw bytes.
- Add a `hooks-command` case: the source is pushed without a final newline (and with a trailing blank line), installed, then changed again on origin. `--check` stays green with the note.
- Add a row with mutant "trim and add `\n`" (the prototype as it is), run.

### F3 [medium] Existing work misses the branches whose history (not tip) holds fixture commits, in live worktrees today: a rebase, `pull --rebase`, cherry-pick, amend or `reset` onto those commits is now refused mid-operation, and E1's census is stale
Where: Chore checklist, Existing work, "Fixture-identity refs today" ("four local branches … `proto-f0147` is gone"); E1; E6; the refusal message; G4.
Evidence: read-only in the real repository today:
- `git log --branches --remotes --format='%h %ae %ce' | grep -i example.invalid` lists 23 commits. `git for-each-ref --contains <each>` counts: `proto-f0147` 10, `proto-wall-picks-base2` 7, `-base` 4, `-base3` 3, `proto-f0143-deps` 3, `-touch` 1. No remote-tracking ref holds any.
- `proto-f0147` exists again. Its tip is `29f3140b <philip.bergen@me.com>` (2026-11-01 03:00), on top of 10 `proto@example.invalid` commits, and `git worktree list` shows it checked out at `.worktree/proto-f0147`.
- `proto-f0143-deps` (tip `<p@x>`, worktree `.worktree/proto-f0143-deps`) holds 3 such commits.
- `.worktree/proto-wall-picks-touch` has the fixture-tip branch `proto-wall-picks-base3` checked out.

In `rb` (hook installed), a branch `proto` was base, then a fixture commit, then an ordinary commit, with `main` moved on:
- `git rebase main` stopped at `Rebasing (1/2)` with the hook's refusal (`a5ed3059 (author proto@example.invalid): HEAD`), rc 128, and left `interactive rebase in progress`.
- `git reset --hard HEAD~1` onto the fixture commit was refused.
- `git merge --no-ff main` passed.

Critique: a prep session updating its prototype branch onto a new `origin/main` is the ordinary move (this prep re-applied its own prototype from 8f533112 to 6e7fc1aa). After this lands, that move fails half-way through for the sessions above. The message tells them to use a scratch clone or their own identity, but not how to get out of the stopped rebase. The design lists only the four fixture-tip branches and says `proto-f0147` is gone (lesson z-design/new-rules-migrate-existing-work).
Consequences: the commands that replay commits keep the author, so every one of them is refused on these branches: `rebase`, `pull --rebase`, `cherry-pick`, `commit --amend` of such a commit, and `reset` or `checkout --detach` onto one. Merge-based routes pass: `merge`, and `merge --squash` committed under the session's own identity. Abort routes pass too, since `rebase --abort` returns HEAD to the ordinary tip.
Recommendation:
- Re-run E1 at the end of prep and paste the search above with its output.
- Existing work names the history-holding branches and the refused and working routes.
- The hook's message gains one line: "If this stopped a rebase or cherry-pick of older prototype commits: `git rebase --abort` (or `git cherry-pick --abort`), then merge instead of rebasing, or move the prototype to a scratch clone."
- `repo-hook.spec` gains a case where a rebase of a branch with a fixture commit under an ordinary tip is refused, names `HEAD`, and carries that line, plus a row with mutant "hint missing", run.
- G4's options name these branches too: their owners may rebuild them, or keep them and merge only.

The new line is message text, not new refusal logic.

### F4 [low] Two concurrent `./zn hooks` installs share one temporary name and can leave the hook non-executable, which git then skips
Where: `cmd.hooks` install: `tmp = <dir>/.reference-transaction.new`; `sh.writeReplacing(tmp, …)`, `chmod 755 tmp`, `mv -f tmp dest`; Rules and mutants row "the new file replaces the old one atomically … reasoned".
Evidence: `replace-file.pl` creates its own unique temporary file with mode `0644`, then renames it onto `tmp`. The race:
1. A: `writeReplacing` writes `tmp`.
2. A: `chmod 755` on `tmp`.
3. B: `writeReplacing` renames B's own 0644 file onto `tmp`.
4. A: `mv tmp dest` moves B's 0644 file into place.
5. B: `chmod` fails (ENOENT) and B reports `could not install`.

The result is a non-executable `dest`, so git ignores the hook (fail-open, with git's `ignoredHook` hint) until a gate's `--check` goes red for every session. Step 9 tells every other session to run `./zn hooks`, so concurrent runs are plausible right after the merge.
Recommendation: use a per-process temporary name in `<dir>`, such as `.reference-transaction.new.<pid>` or a `mktemp` there, and say so in the Design. Change the reasoned row to "a concurrent install never leaves a non-executable hook (unique temporary name)"; it stays reasoned.

### F5 [low] The reference is the local `refs/remotes/origin/main`, which any session can move; that limit isn't stated
Where: "Why `origin/main`" ("read … from the local remote-tracking ref (no network)"); Risks.
Evidence: `git update-ref refs/remotes/origin/main <commit>` (I did it in `T` for the F3/F4 re-run), or `git fetch origin <branch>:refs/remotes/origin/main`, moves the reference. Then `./zn hooks` installs that commit's hook text for every worktree, and `--check` accepts any text in its history. Lesson zz-review/sequestration-reference-not-a-ref and zz-arch/guard-state-out-of-reach-or-checked ask for the published tip, or a stated known limit where the same OS user can rewrite the record.
Recommendation: state it in Risks as a known limit: the tripwire's threat is careless sessions, and an `update-ref` of `origin/main` is a deliberate act. Alternatively, have the install path only (not `--check`, which must stay offline) confirm with `git ls-remote origin refs/heads/main` that the local `origin/main` is the published tip or one of its ancestors (`merge-base --is-ancestor`), refusing otherwise, and add a case and a row. Either is acceptable; record which.

### F6 [low] Round 2's candidate lesson (probe every ref-writing command with a logging hook) was harvested only as a source for a lesson whose rule and `check` don't carry it
Where: `harvest.md` ("design-review-002 F2: z-design/prove-specs-pass-on-a-prototype"); `z-nile/skills/z-design/lessons/prove-specs-pass-on-a-prototype.md`.
Evidence: `grep -n -i "logging hook\|branch -m\|writes refs"` over that lesson finds nothing, and `git status` in the worktree shows no lesson file edited. The lesson's `check` asks whether the specs ran on a prototype. The finding was a different miss: E2 concluded "every route" after probing a sample of commands.
Recommendation: the lead adds a note to that lesson, or writes the round-2 candidate as its own lesson, with its rule and its `check` ("for each command that creates or moves a ref, what did a logging hook receive, and is each one refused, allowed on purpose, or a stated limit?").

## Other points checked, no finding
- **Fail-open paths in `cmd.hooks`/`hooks.plan`.**
  - `none` arises only when origin/main has been read successfully and has no file.
  - A failed `ls-tree`, a missing `origin/main` with an origin, a failed history read, `show` and `hash-object` (all `sh.must`) each exit non-zero.
  - `refuse` never reaches the write.
  - `older` needs exactly one problem.
  - A dangling link is `link`.
  - The `command`-scope `core.hooksPath` that the fence sets is dropped.
- **Mutant I doubted, run.** I made the history read default to `HEAD` (`git log --raw -- <source>`, no `origin/main`) and ran `hooks-command.spec` on the prototype in the clone. It is killed: 17 passed, and 1 failed at line 239 ("origin/main moves").
- **Interplay with the fence and the tripwire.**
  - The fence's hook decides first and chains only what it allows. `repo-hook.spec` pins that.
  - The tripwire snapshots no hooks folder (`fence.luau` `snapshot`: config, branch, HEAD, `.cache` worktrees, fixture refs), so `./zn hooks` running during another gate trips nothing.
  - `engine.copy` copies no `.git`, and fixture clones copy no hooks, so no spec fixture inherits the hook.
  - The Merging clone has no `origin` after `git remote remove origin`, so it installs its own tree's copy, which is the head under test.
  - CI runs `setup.sh --tools` only, which exits before `./zn hooks`.
- **Specs and the real repository.** Every write in the four specs is under `<home>/.cache/c0189-*` or a `trackerfix` fixture. `git clone` and `git init` are given absolute fixture paths. `core.hooksPath` is set only in a fixture's local config. The fence-hook case names only the fixture as protected.
- **Guesses.** G1 (a guard widened), G2 (the push route), G3 (a narrower reading of "any ref update") and G4 (other sessions' branches) are each the user's call. Each carries its evidence, options and costs. F3 adds to G4's evidence.
- **Scope.** The captured Problem sentence is verbatim. The title only gains detail. The pseudo-ref narrowing (G3) and the rename/copy limit (G4) are put to the user, not decided.

## Candidate lessons (for the lead to place)
- **zz-arch: "a version the reference has held" means its first-parent history.** Rule: when a guard accepts any text a branch has held, read it with `--first-parent`. Why: c0189 design review 003 F1: `git log origin/main -- <file>` walked into merged branches, so a WIP `exit 0` hook committed and reverted on a PR branch passed `--check` as "reviewed". Check: could a text that was never `main`'s tip be in the set this guard calls reviewed?
- **zz-arch: compare an installed copy with its reference by blob id, and install the raw bytes.** Rule: a guard that installs from git and later looks the installed file up by `hash-object` installs untrimmed bytes. Why: c0189 design review 003 F2: `sh.git` trims, the install added one `\n`, and a source with a different ending installed a file whose id no commit has. Check: does the installed file's `git hash-object` equal the blob id it was read from, for a source with no final newline and one with a trailing blank line?

Verdict: changes
