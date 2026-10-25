# Refute 004: c0117 (answers to design-review-004.md)
Prototype: `proto-c0117` on `proto-c0116` 5fa0a8d, with simulation b57df84 and the edits on top as one commit. All experiments and mutants ran in clones under the session scratchpad. None ran in a branch, worktree or commit of the real repository.

- F1: fixed, by replacing the mechanism.
  - **Vetting.** Within a run, `vetMain` vets from the run's own in-memory copy of the watermark (`guard.mark`) to fresh `main`, whatever the shared file says. Another dispatcher's advance, or the user's `vet`, is never a trip. A step that deletes or rewrites the file is still caught by the commits it pushed: W1 and W2 now trip on `w1.lua` and `w2.lua`.
  - **Reading.** The file is read only when the run has no copy yet (at its start). It keeps the no-file check, the went-back check against the item's mirror, and a trip on a diverged file.
  - **Writing.** Writes go through `dispatcher.advanceMark`, under an flock on the watermark's folder (`runner.holdLock`), and only move the file forward: an older `main` leaves it as it is, a diverged one is refused, and `vet` forces. A file gone mid-run is written again, with a note on stderr.
  - **Docs.** §5, zz-rules and the README say the file is shared by every dispatcher of the repository.
  - **Cases (control-cli):**
    - case C: B runs while the other terminal publishes and runs A, and both exit 0;
    - W1 and W2 still exit 5;
    - `advanceMark` directly: an older write leaves the newer file, a diverged sha is refused, and `force` writes it.
  - **Mutants:** M130 (equality compare), M131 (vet from the file) and M132 (unconditional write).
  - **Consequences:** two overlapping runs each re-vet the other's commits (one `diff-tree` and two `ls-tree` per commit). G18 names concurrent dispatchers. The lesson `guard-state-out-of-reach-or-checked` is amended, and `several-writers-check-the-subject` is new.
- F2: fixed in the prototype for the dispatcher's own clock and for claude's limit. The other CLIs wait on E15.
  - **Heartbeat.** The runner keeps a heartbeat both ways. A nested step (one that inherited its author's broker) writes `<its state folder>/beat` at most once a second while its CLI prints. Every runner counts a changed `beat` under its own state folder as output. A quiet nested step still stalls, and its author with it, so nothing hangs.
  - **Claude's limits.** `adapters.STEP_ENV` sets `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` to two hours for `claude-cli` (G22).
  - **E15 (new, Phase 1).** It measures each CLI's limit on one 20-minute command. Its fallback is a background review that the author polls (the cost per poll is stated against `max_calls`), else escalate.
  - **Cases (control-cli):** with `tool_seconds = 8`, an author waits on a nested reviewer that prints for 16 s and ends `ok`, and `bashmax=7200000` is in the step's environment. A reviewer that goes quiet for 20 s leaves the step `stalled`.
  - **Mutants:** M133 (the beat ignored), M134 (no beat) and M135 (`STEP_ENV` dropped).
  - **Consequences:** a nested step's beat costs one small file write a second. The case takes about 40 s of control-cli's time.
- F3: fixed. control-cli has the rafting gate's cases. Each uses a real head through `fakecli.pullRequest`, with `auto_merge = ["raft"]` in c0096's own walk:
  - the merge: R0050's document (`issues: [c0096]`) and c0096's `raft:` line, pinned to the head;
  - it waits for:
    - code;
    - c0091's `check.sh` (c0091 isn't a member);
    - c0096's `.models.toml`;
    - a stale head.

  The reviewer's mutant (M136: the raft branch judges nothing) is killed, and so is M137 (own items taken from every raft on `main`). The reasoned row is now two run rows.
  - **Consequences:** a block-style `issues:` list parses to no members, so such a PR waits for a human (fails closed). This is said in §6.
- F4: fixed.
  - `guard-state-out-of-reach-or-checked` now says "who else legitimately writes that record" and "re-check what it guards from its own copy; never fail on the record merely differing".
  - The first paragraph of `merge-gate-checks-what-it-merges` now says "fetch the PR's head pinned to `headRefOid` and judge its commits".
- F5: fixed.
  - §8 step 4 and E10 now say the same sentence: with the user's own token the first three pass (the push, `gh pr merge` and the API merge, since the admin bypasses).
  - G20 now says that a rebase-merged PR's earlier commits each stop the chain until `vet`, or that a squash-only ruleset avoids it.
- Candidate lessons: written as `architecture/several-writers-check-the-subject` and `architecture/waiting-steps-show-liveness`.
