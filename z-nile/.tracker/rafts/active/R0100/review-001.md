# Review 001: R0100 (code mode)
Inputs: layer 1 (c0265), `git diff origin/main...R0100/1/c0265`. The branch is at d472c40b5: during the review the author rebased it onto origin/main 4a4183ad1. Its code, skills and docs are identical to e8632875e, the tip when the review began (`git diff e8632875e d472c40b5` changes only c0265's `spend.d` file). Also read: c0265.md, its check.sh, acceptance/{heartbeat,beat,edge,lost}.spec.luau, proofs/race.spec.luau and R0100.md.
Checked:
- Sequestration: the `--find-renames=100%` diff over check.sh, acceptance/ and proofs/ lists nothing.
- The 200-local cap: compiling padded copies with `@lune/luau` gives 4 spare top-level locals on origin/main and 11 on the layer. `boardview` is kept, and `sessionread` and `sessions` are kept as locals.
- `heartbeat.luau` requires nothing and reads no clock.
- The landing read: in a scratch repository, `heartbeat.landingArgs()` on a `--no-ff` merge returns the merge's time, and without `--first-parent` it returns the PR commit's time. `./zn done` merges onto a detached origin/main, so main is the first parent.
- Spec run: the four non-proof spec files passed 54/54, but by then the worktree had moved to layer 2 (ffd94b293, with staged edits), so that run is not evidence for layer 1 alone. The executor's log records `./zn check c0265` 5/5 on layer 1.

### F1 [low] A beat's attempt is not held to its own read of main
Where: z-nile/engine/main.luau:1703-1715 (`hb.beatOnce`), 1813 (the `--watch` tick)
Evidence:
- **Path list.** `hb.beatPaths()` lists the paths with `ls-tree origin/main`. A moment later the code reads `at = rev-parse origin/main`. `refs/remotes/origin/main` is shared by every worktree, so a sibling's fetch can land between the two reads. Then `hb.claimsOf(paths, false, at)` runs `git show <at>:<p>` on paths from the older main. If any item's document moved in that update (a `ready`, `stop` or `done` anywhere), `sh.must` raises. A plain `./zn beat` then ends with `tracker beat: …` (exit 1).
- **Watch tick.** The tick's `hb.stampNow(id)` (line 1813) sits outside the pcall that guards `beatOnce`. A raise there ends the loop instead of counting as a failed tick. The design says "a failed tick, including an unreadable `main` or an exception inside the beat (`pcall`) … the loop retries at the next tick".
- **Claim not checked.** The plan never asks whether `held` is in the claimed set at `at`. Suppose a claim ends between `cmd.beat`'s first look and the attempt's look, and its branch already exists. The beat still writes a lease on that branch and `./zn beat` exits 0. The ended stamp's branch then lives another 900 s before the pruner may delete it.

The window is milliseconds, and every outcome is safe (nothing is judged lost), hence low.
Critique: AC2 says the beat "names one main for its whole attempt". edge.spec's `movemain` case moves main after the first `rev-parse`, so it does not reach this gap. The tempting fix is to wrap `claimsOf` in a pcall and skip unreadable paths. That is worse: a claim dropped from the claimed set lets the pruner delete a lost claim's old branch, which the design keeps as evidence.
Consequences:
- Reading the paths at `at` needs an `originTree` that takes a ref, or a local `ls-tree -r --name-only --full-tree <at> -- <roots>`, with the roots read at the same sha.
- Checking `claimed[held]` adds a loss path before the write. It must say the same text as the other loss paths (`hb.lostText`).
Recommendation:
- In `beatOnce`, resolve `at` right after the fetch of main, and list the paths and roots at `at`.
- Read the item's stamp at `at` with `claimStampOf`. When it is not `held`, return `hb.lostText(id, <that stamp>), true` before planning: no write, no prune.
- Move the tick's `hb.stampNow` inside the same pcall as `beatOnce`, so a raise is a failed tick, said on stderr.

The five spec files still hold:
- In the `raceread` case the takeover lands during the beat read, before the main read. The beat now reports `taken over (now <new>)` without pushing, and the old branch is already gone (the taker deleted it).
- `racebeat` and `cobeat` act at the push, after `at`, so they are unchanged.
- No fetch is added: `rev-parse` is local, so race.spec's `mainfail` count stands.

### F2 [low] The network wrapper's child leaves the caller's process group with no lifeline
Where: z-nile/engine/main.luau:1475-1476 (`hb.BOUND`)
Evidence:
- The child runs `setpgrp(0,0)`. The wrapper installs no INT/TERM/HUP handler and holds no pipe to the child's group.
- Ctrl-C in a terminal signals only the foreground group (lune and perl). `./zn run`, at its limit or at a session's end, signals only its own group (`kill 'TERM', -$pid` in bounded.pl).
- So perl dies, and a `git fetch`/`push` or `gh pr list` stuck on a stalled connection keeps running, now outside the 10 s bound.
- It runs until `./zn reap` finds it, as an orphan (git and gh are ORPHANABLE) or as a marked process past its `ZN_BOUNDED_DEADLINE`.

The reaper is a backstop, hence low. c0275's automatic beats run this wrapper on every command in a worktree, which multiplies the exposure.
Critique: The tempting fix is to drop `setpgrp` so the child stays in the caller's group. That reopens the reason it is there: the wrapper must kill the child's whole tree (`git-remote-https` included) without killing itself, because Lune reads a signal-killed child as success (E13).
Consequences: A signal handler must exit with a status that `netRun` reads as a failure, never 0. A SIGKILL of the wrapper cannot be handled at all, so that case needs bounded.pl's pattern: a watchdog inside the child's group that waits for end of file on a pipe only the wrapper holds, and kills the group when it comes.
Recommendation:
- In `hb.BOUND`, after the fork, set `$SIG{$_} = sub { kill 'KILL', -$pid; exit 130 } for qw(INT TERM HUP)`. The 50 ms poll delivers them at once.
- Give the child's group a watchdog on a pipe from the wrapper, which kills the group on end of file.
- Add a fast tooling spec (not a sequestered one): a shim that sleeps 120 s, TERM (then KILL) the wrapper after 0.5 s, and assert the sleeper is gone within a second.
Lesson: zz-arch/children-need-a-lifeline

### F3 [low] Every quiet failure of a network call is reported as a timeout
Where: z-nile/engine/main.luau:1487-1495 (`hb.netRun`)
Evidence: `if not r.ok and sh.trim(r.stderr) == ""` turns any failure with an empty stderr into `timed out after {secs} s`. I ran the wrapper here on a command that is not installed (`./zn run --time 20 -- perl -e "<hb.BOUND>" 2 zn-no-such-cmd pr list`). It exits 127 at once and prints nothing. So on a host without `gh`, `./zn lost` says `lost: pull requests unreadable: timed out after 10 s` the moment any claim is stale. A quiet `git` failure reads the same way.
Critique: The outcome stays fail-safe (unreadable, so nothing is lost), but the message names the wrong cause (zz-arch rule 8). Matching on exit code 124 alone is the tempting fix, but a child may return 124 itself.
Consequences: The wrapper becomes the one place that says "timed out", and `netRun` needs a fallback text for a quiet failure that is not a timeout. race.spec matches `timed out after 2 s` and `pull requests unreadable: timed out after 2 s`; the wrapper's own message keeps both.
Recommendation:
- `hb.BOUND` prints `timed out after $n s` to stderr when it kills the group, and `cannot run $ARGV[0]: $!` when `exec` fails.
- `netRun` keeps stderr as given, and replaces an empty one with `<cmd> failed (exit <code>) with no message`.

### F4 [low] The workflow text is out of step with the shim, and one step is not a list item
Where: z-nile/skills/z-work/SKILL.md:19 (step 10); z-nile/skills/z-run/SKILL.md:12; z-nile/skills/zz-execute/SKILL.md:16
Evidence:
- (a) z-work step 10 still says "Heartbeats and taking over a raft someone else holds are c0265". Meanwhile the z-run shim, which defers to z-work, now tells the same session to run `./zn beat`. The raft's Risks ("z-run is a shim") asks the executor for "the matching text into z-work's step 10".
- (b) The shim says "Look at `./zn lost` before taking a raft that is not yet started … lost work comes first". It is read by `/z-run <R>`, a session with its raft named. The raft's Experiments ("z-work and the heartbeat") says the lost-first order is for an unnamed session only: "a *named* session carries its raft and stops, and the shim never tells it to take other work".
- (c) `2b.` is not a Markdown list marker, so it renders as part of step 2's paragraph.
Critique: (b) can send a named run after another raft's lost work, which no command in this layer can take over. The tempting fix for (b) is to drop the sentence, but AC5 pins `./zn lost` in z-run.
Consequences: z-work is not in c0265's Touched modules. Editing it here is a deviation to record, unless the raft document names the layer that does it (layer 5 edits z-work's steps 1 and 7).
Recommendation:
- Shim: "Without a raft named, z-work looks at `./zn lost` before a raft that is not yet started: lost work comes first. With a raft named, carry that raft." This keeps `./zn lost`, `./zn beat` and `--time 3600`.
- z-work step 10: "Heartbeats exist (`./zn beat`, `./zn lost`, c0265); taking over a lost raft is c0274 and c0277."
- Either make the z-work edit in this layer and record the deviation in c0265's Verification log, or write in the raft document that layer 5 makes it.
- zz-execute: make the beat a sentence of step 2, or renumber it as step 3.

### F5 [low] Two heartbeat format literals live outside the module that owns the format
Where: z-nile/engine/main.luau:649 (`freshStamp`), 1518 (`hb.readBeats`)
Evidence: `freshStamp` builds `refs/heads/hb/{v}`, and `hb.readBeats` hard-codes `+refs/heads/hb/*:…`. Yet `heartbeat.PREFIX` and `heartbeat.branch` exist, and `heartbeat` is required at the top of main.luau. The design's Maintainability says "`heartbeat.luau` is the one reader and writer of the heartbeat branch format" (zz-arch rule 5).
Critique: A later change to the prefix in heartbeat.luau would leave the stamp draw checking a ref no beat writes. Fresh `preparing` stamps could then collide with a live heartbeat branch again (design-review-019 F8).
Consequences: none beyond the two call sites.
Recommendation: Use `heartbeat.branch(v)` in `freshStamp`, and `` `+{heartbeat.PREFIX}*:refs/zn/hb-seen/*` `` in `readBeats`.

## Judged criteria (code mode only)
- None: c0265 has no Judged criteria. Each Checked criterion (AC1 to AC5) has code that implements it as the Design states. AC2's "one main for its whole attempt" holds for the beat commit's tree and parent and for the claimed set's contents; F1 is the remaining gap, in the path list.

Verdict: approve
