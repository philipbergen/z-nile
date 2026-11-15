# Refute 016 (c0265): discard-and-recover round 2 answered (no high finding; the answers add rules and cases, so another round follows)

- F1: fixed: the Problem's gloss, the Assumptions' takeover bullet and the review-count note describe the numbered-copy reading; two more readings are listed for veto (the "rename" is of the branch and a marker, not the directory; the "copy" is a new worktree on the pushed branch, unpushed commits and dirty files stay in the old worktree with a cherry-pick command offered).
- F2: fixed: the claim memory is read from `.tracker/stamp` and falls back to `.cache/tracker-claim-<id>`, which holds the stamp today; the landing-day limit (a worktree runs its own engine) is said, the executor lists active worktrees; `--item` also needs the lost verdict.
- F3: fixed: one rule: `--adopt` in a worktree writes the memory; in the main checkout and with `--stamp` it writes none.
- F4: fixed: `.cache/fresh` records the epoch, refuses a second takeover while younger than STALE and is written by the no-worktree path too; discard.spec asserts the fresh refusal (prep-fresh) and the claim-less refusal (prep-plain, plain-created).
- F5: fixed: `./zn worktree --takeover <id>` finds the worktree by its claim (discard.spec's second takeover uses it); a raft takeover discards its `ws-` streams; the dispatcher takes over before a step on a lost claim; z-raft and z-design name the by-id form.
- F6: fixed: the busy assertion names the renamed branch `prep-hello-discarded-1`; the note's first line is `discarded worktree: <path>` and the spec asserts the old path.
- F7: fixed: the discard deletes the old worktree's beat entries and running loops/ticks re-check the marker each tick.
- F8: fixed: the renamed branch's upstream is unset; the spec asserts it.
- F9: said in the Design where it is a rule (stream worktrees, hooks get the refusal, `release` ends memory like `stop`); a stale test title and a non-failing assertion are the executor's tidy-up.
