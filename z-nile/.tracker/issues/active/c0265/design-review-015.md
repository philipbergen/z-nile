# Review 015: c0265 (design mode)
Inputs: prep head 1c73a3af (`tracker: prep c0265 discard and recover: …`). Round 1 of the second restarted count. I read c0265.md, check.sh, acceptance/{heartbeat,beat,lost,edge,discard}.spec.luau, proofs/{dispatch,race}.spec.luau, experiments/heartbeat.proto.luau, design-review-012..014, design-refute-012..013, and the word diff `0c14c608..HEAD` of c0265.md. Only discard.spec, heartbeat.spec, check.sh, the prototype and c0265.md changed since review 014; beat/lost/edge and both proofs are byte-identical. In the engine I read `worktrees()`, `cmd.worktree`, `cmd["worktree-prune"]`, `cmd.busy` with `compact.busyRefNames`/`dirtyWorktrees`, `READ_ONLY` and the dispatch at the end of main.luau, `cmd.stop`/`cmd.ready`, and the dispatcher's `worktree()` and its callers (dispatcher.luau 222, 809-815, 1173). I also read scripts/hooks/{stop,session-end,post-edit}.sh and the z-design, z-raft and zz-execute skills' worktree lines. I ran `./zn lessons --when design` and `--skill zz-review`.
Capture: `./zn capture c0265` prints `(no capture commit: first add)`, the user's #258 rewrite. That is not a confirmed capture, so I judged scope from that commit. The title, Problem and Solution only gained `Decided with the user` lines; the new 2026-11-08 line is the user's own words.

Replays (from z-nile, with the prototype copied to `engine/heartbeat.luau` and deleted after; `git status --short` is empty afterwards):
- heartbeat.spec: 21/21 (the new nextSuffix case included). Against the unchanged engine, discard 1/6, beat 1/11, lost 2/18, edge 1/5, dispatch 1/2 and race 1/5 each pass their setup. Every other case fails on an assertion or on the missing command, not on setup.
- `./zn promote-check c0265`: OK. `bash -n check.sh`: clean. `git hash-object` of the proofs gives `6fd10bdf…` and `5ae72235…`, which equal AC4 and AC5.
- discard.spec's fixture, emulated by hand: a scratch spec under `z-nile/.cache/rev015` with fixture `.cache/rev015-emul`, both deleted after. It ran the spec's setup, then `git worktree move .worktree/prep-hello .worktree/prep-hello-1`, `git branch -m prep-hello prep-hello-1` inside the moved worktree, and `./zn worktree prep-hello`. Results:
  - the move works with a dirty file and an unpushed commit, and `branch -m` of the branch checked out there works;
  - the fresh worktree's HEAD is origin's `prep-hello` tip, and `git log origin/prep-hello..HEAD` in the old worktree shows "unpushed work";
  - `fixture.exec` runs in the moved directory;
  - **`./zn busy pickman z-nile` and a bare `./zn busy` both print nothing and exit 0** (F4).

### F1 [high] Reusing the old path for the taker hands it to every process that addresses the old worktree by path, so the waking process is not told. This defeats the purpose of the user's 2026-11-08 decision.
Where:
- Discard and recover, steps 3 and 4: old → `<name>-<n>`, fresh worktree "at `.worktree/<name>`".
- "**The old process** keeps its directory (the move keeps its working directory valid)".
- The lease and ownership: "the old process finds either a refusal or its discard notice, whichever form it uses".
- The Problem's Decided line: "That way a process that wakes up knows it has been discarded".

Evidence: the move keeps a *kernel* cwd valid. The workers here do not hold one. They name the worktree by path:
- A Claude Code session runs each Bash call in the directory it recorded as a path. The Stop hook receives that path as `"cwd"` (scripts/hooks/stop.sh line 7) and gates `git -C "$cwd" rev-parse --show-toplevel`.
- Read, Edit and Write take absolute paths (AGENTS.md and the tool rules: "prefer absolute paths").
- z-run and z-design enter by path: `cd "$(./zn worktree <R>)"`.
- The dispatcher records the step's worktree as a path, `st.worktree = cwd` (dispatcher.luau 986). The new F3-of-014 rule reads "the stamp in the memory of the step's worktree, re-read at each tick" from that path.

After `worktree prep-x --takeover`, `/…/.worktree/prep-x` is the taker's fresh worktree. A suspended session that wakes up behaves like this:
- its next `./zn sync` runs in the taker's checkout, which has no `.cache/discarded`, so the guard never fires;
- its autobeat there reads the *taker's* entry (S2, which equals origin's S2) and beats the taker's claim;
- its Edits land in the taker's tree, its `./zn commit` commits on the taker's branch, and its Stop hook gates the taker's tree;
- the dispatcher reads S2 from `st.worktree` at the next tick, sees no mismatch, and keeps beating for a step that was discarded.

That is review 014 F1's shared checkout again, now for the very processes the rule was written for. Only a process that holds the directory open, such as a `./zn run … beat --watch` loop, is told, and that loop was already stopped by its stamp binding.
Critique: the user's words are ambiguous about which worktree carries the number: "Rename the old worktree and create a copy to continue the work and call it R123-1 R123-2". Read literally, "it" is the copy. The Design took the other reading, recorded only as a parenthesis, and that reading is the one that cannot tell a path-addressed process anything. The tempting fix is "the guard also checks something in the fresh worktree". It cannot work, because two processes in one directory cannot be told apart (review 014 F1(b)).
Consequences: when the copy takes the numbered path and the old worktree stays where it is (marked and with its branch renamed), every form of the old process is told: its path, its kernel cwd and the dispatcher's `st.worktree`. That brings new rules:
- `./zn worktree <name>` must resolve a name to its newest live copy, because z-run, z-design and the dispatcher's `worktree(ctx, id)` all enter by name;
- `worktree-prune` must treat `R0010-<n>` as the raft's live worktree, because its `^R%d%d%d%d$` match would otherwise keep the copy forever and remove the discarded `R0010` (the work to recover) when the raft is done;
- the recovery note and busy then name the old path.
Recommendation: escalate to the user, quoting the two readings. The options:
1. **The copy is numbered** (the literal "call it R123-1"). The old worktree keeps its path and gets `.cache/discarded`, and its branch is renamed `<branch>-discarded-<n>`. The copy at `<name>-<n>` takes the original branch. `worktree <name>` returns the newest undiscarded copy, and prune and the dispatcher follow. This is the only option under which every path-addressed process is told.
2. **Keep the Design's reading**, recorded as a `Decided with the user` line saying that only a process holding the directory open is told; the Design's "whichever form it uses" sentence is removed.
3. **Move the old one aside and leave the original path empty**, with the copy numbered. A path-addressed process then finds no directory: Claude Code falls back to the project directory (the main checkout), and Write recreates `.worktree/<name>/…` as a plain folder inside the main checkout. Cost: the guard must also refuse in a `.worktree/<x>` folder that is not a worktree.

Whichever option is chosen, add a discard.spec case that runs a command by the **old path** after the takeover and expects the discard notice there (option 1), or pins what the user accepted (option 2).
Lesson candidate (for the lead): zz-arch, "a moved directory's old path belongs to whoever is put there next: sessions, file tools, hooks and run state address a checkout by path". Check: "for every move or rename of a checkout, which processes name it by path, and where does their next write land?"

### F2 [high] The new "memory is dropped by the beat that observes the takeover" rule makes lost.spec fail and reopens the old owner's adoption of the taker's claim, against the user's "refuse"
Where:
- The lease and ownership: "A memory file is dropped, with the entry, by the beat that observes its claim was taken over or ended". The same paragraph says such a beat "drops the entry and never rewrites the memory".
- The carried `prepared` and `done` "refuse only when this checkout **remembers** a stamp and it differs from origin's (a checkout with no record passes, as today)".
- lost.spec 457-494.

Evidence, walking lost.spec "the old claimant's carried move is refused…" against the stated rule:
1. Line 461, `sync` in `wt`, runs the autobeat. It observes that c0010 was taken over and drops the entry, which line 465 asserts. Under the new rule it also drops `.cache/tracker-stamp-c0010`.
2. Line 467, `status c0010 prepared`: no memory, so "a checkout with no record passes". `r.ok` is true, and line 468 fails. The same happens for the rafting claim at 492.
3. Under the narrower reading (only an explicit `beat` drops the memory), line 472's bare `beat` observes the takeover and drops it. Line 476's `--adopt` then finds no memory, beats origin's S2 and writes S2. It adopts the taker's claim: line 477 fails, and line 487's "taker's branch not touched" fails with it.

Under either reading, a correct implementation of the Design cannot pass AC3. The behaviour is also the one the user ruled out: the old claimant's carried move passes once its memory is gone.
Critique: the memory is the record every refusal stands on. Dropping it at the moment the loss is observed removes the refusal that should follow. The rule was added to end the main checkout's memory (review 014 F4), but it was written for every checkout.
Consequences: review 014 F4's own recommendation needs no drop rule. `--adopt --stamp <S>` never reads or writes the memory, and a plain `--adopt` in the main checkout writes none: main holds no work, and beat.spec's c0095 case passes, since main's bare beat refuses for lack of memory. A worktree's memory then ends only with the commands that end the claim there (`done`, give-back, `release`) and with the worktree itself (the discard keeps it as evidence).
Recommendation: replace the drop rule with those rules, and remove the AGENTS.md / zz-rules line about main's memory, or keep it only if main still writes one. Add a beat.spec case: main runs `--adopt --stamp S1`, the item is re-claimed (S2), and `--adopt --stamp S2` beats. Add a Rules row: "observing a takeover never drops the memory".
Lesson: z-design/restated-rules-move-together

### F3 [high] The Design exempts `lessons` from the discarded-worktree guard, but discard.spec uses `lessons --tags` as the command that must be refused
Where: Discard and recover: "everything except the read-only `list`, `find`, `members`, `lessons`) refuses". discard.spec lines 116 and 143 expect `lessons --tags` in the discarded worktree to exit non-zero and say "was discarded".
Evidence: an implementation that follows the sentence runs `lessons` there and exits 0. Both cases then fail at `t.expect(r.ok).toBe(false)`. The exemption list also matches neither `READ_ONLY` (main.luau 5989: `list, audit, find, members, metrics, board, workstreams, promote-check, stamp`) nor the autobeat's exemption set ("except `beat`, `run`, `reap` and `READ_ONLY` ones").
Critique: a correct implementation cannot pass AC7. The obvious fix is to drop `lessons` from the list. But the list exists for a reason the Design does not give, probably nested `./zn lessons` in a `check.sh`. A silent read-only command also tells the waking process nothing, which is the user's purpose.
Consequences: a third command set means a third list to keep in sync (lesson exhaustive-lists-name-new-things). In a discarded worktree the gate also calls `./zn skills --check` (z-nile/check.sh 213), so the Stop hook's `--affected` gate fails there and blocks the old session's stop once. That is acceptable, but it should be said.
Recommendation: pick one rule and say why. Either every command refuses (no exemption: simplest, and the spec stays), or the exempt commands are exactly `READ_ONLY` and print the discard notice on stderr while exiting 0. In the second case, the spec probes one exempt command (notice and exit 0) and one non-exempt command (`sync`: refusal). State what the gate and the Stop hook do in a discarded worktree.
Lesson: z-design/spec-design-correspondence

### F4 [high] `./zn busy` does not name the discarded worktree, so discard.spec's busy case fails for the Design as stated
Where: Discard and recover: "`./zn busy` treats them like any worktree and branch with changes: it names them until they are removed". discard.spec 127-133 asserts that `busy pickman z-nile` names `prep-hello-1`. Rules row "`./zn busy` names a discarded worktree… | busy ignoring it | reasoned".
Evidence (run in the emulated fixture):
- `busy` names a branch only when `git diff --name-only origin/main...<ref> -- <paths>` is non-empty (compact.busyRefNames), and a worktree only when `git status --porcelain -- <paths>` is (dirtyWorktrees).
- The claim commit is on the worktree branch, because the publish fast-forwards it. The emulation's `log` shows `tracker: c0010 preparing` under the worktree's commits.
- So the branch's own changes are `pushed.txt` and `unpushed.txt`, and the dirty file is `dirty.txt`, all at the fixture root, outside `pickman/` and `z-nile/`.
- `./zn busy pickman z-nile` and a bare `./zn busy` printed nothing and exited 0.
Critique: "like any worktree" is exactly what makes busy silent here. A correct implementation of that sentence fails AC7, and the row's "reasoned" verdict was never run.
Consequences: either busy gains a rule (a worktree holding `.cache/discarded` is always named, whatever the paths, as `worktree <path> holds the discarded work of <id>`), which changes busy's contract for compaction and c0120's readiness and needs a check that no promoted busy spec pins its silence, or the spec's work goes under a project root (`pickman/…`) and the Design keeps "like any worktree".
Recommendation: pick one. If busy changes, add `z-nile/engine/compact.luau` to Touched if the rule lives there, run `tests/tooling/busy*` and c0120's specs on it, and add a Rules row for it. If the spec changes, put `pushed.txt`, `unpushed.txt` and `dirty.txt` under `pickman/` and keep the case.
Lesson: z-design/spec-design-correspondence

### F5 [medium] `--takeover` refuses a worktree with no claim memory, which leaves lost rafts that never adopted, including every active raft on landing day, without a takeover path
Where: Discard and recover step 1 ("a worktree that holds no claim memory refuses too (nothing to take over)"). The order for a raft. The lease and ownership ("a raft worktree made after `ready`" has no memory until z-run's `--adopt`).
Evidence:
- Today's raft worktrees hold no `.cache/tracker-stamp-<R>`, because `setStatus` writes it for issues only (the Design says so).
- A z-run that entered `.worktree/R0010` and died before `beat R0010 --adopt` leaves no memory either. So does a readied raft whose worktree was made but never started, which the Design itself calls lost ("reads lost 15 minutes later").
- For each of them, `./zn lost` lists the raft and `worktree R0010 --takeover` refuses "nothing to take over". The skills forbid plain `./zn worktree`, which would enter the old checkout. The taker has no documented next step, against the Problem's "The next worker resumes it".
Critique: the memory is a fine signal when it is present. Its absence is the day-one state and the crash-before-adopt state (lesson new-rules-migrate-existing-work).
Consequences: judging by the item the name belongs to (`R0010` is that raft; `prep-<slug>` is the issue with that slug) plus every remembered claim covers both states. But a second taker running `--takeover` right after the first, before the first has claimed, would then see the item still lost and discard the first taker's fresh worktree. The fresh worktree therefore needs a marker of its own (for example `.cache/takeover-of <stamp>`), which a second takeover treats as a live claim until 900 s have passed.
Recommendation: state that rule and the marker. Add discard.spec cases for a raft worktree with no memory whose raft is lost (taken over) and for a second takeover right after the first (refused).
Lesson: z-design/new-rules-migrate-existing-work

### F6 [medium] Other routes into the old worktree remain: the dispatcher, z-raft's rafting worktree and a raft's stream worktrees
Where: dispatcher.luau 222-225 (`worktree(ctx, name)` calls plain `./zn worktree <name>`; 811 `prep-<slug>`, 813 `raft-…`, 815 the R-id). z-raft line 13 (`./zn worktree raft-<slug>`, "any short slug, for example `raft-backlog`"). zz-execute Phase 2B step 2 (`./zn worktree ws-<issue> --from <raft branch>`). The Design's skills paragraph and AC6, which name `--takeover` for z-design and z-run only.
Evidence:
- `./zn dispatch c0300` on a lost prep makes its z-design step in the reused `.worktree/prep-<slug>` (cmd.worktree returns an existing path and ignores `--from`). That step's first `./zn` beats the old memory and revives the claim (review 014 F1(a)). If it then follows z-design's new `--takeover` line, it moves the directory it is standing in.
- A lost rafting claim's taker in z-raft has no `--takeover` instruction. If it reuses `raft-backlog`, it enters the old checkout.
- A lost raft's old `ws-<issue>` worktrees are neither discarded nor listed. The new z-run's `./zn worktree ws-<issue> --from <raft branch>` returns the old stream checkout, and the old stream subagents keep working there.
Critique: the user's rule covers "a process that wakes up" for every worker, not only for the two interactive skills.
Consequences: the dispatcher needs either to call `--takeover` when the step's item is lost (the verdict it already reads, lazily) or to refuse lost items until c0253 does. A raft's `--takeover` must also discard its `ws-*` worktrees, or list them in the recovery note.
Recommendation: state each path. Add AC6 greps for `--takeover` in z-raft and for the `ws-` handling in z-run or zz-execute. Add a dispatch case or a stated rule for the dispatcher (the proof is pinned, so a new `acceptance/` case is the cheaper choice).
Lesson: z-design/results-land-on-every-path

### F7 [medium] The recovery note's unpushed-commits command fails in the common prep case, where nothing was pushed
Where: Discard and recover steps 3 and 4 ("the commits not on `origin/<branch>`", `git -C <old> log origin/<branch>..HEAD`; "else from `origin/main`").
Evidence: z-design pushes only when it lands (step 5, "push, PR"), so a prep that died mid-design usually has no `origin/prep-<slug>`. Then `git log origin/prep-<slug>..HEAD` errors with "unknown revision", and the note that matters most to "try to recover the work" (every commit is unpushed) is missing or fails the command. discard.spec only covers the pushed case.
Recommendation: when `origin/<branch>` is absent, use `origin/main..HEAD`, and say so. Add a discard.spec case for a prep with an unpushed branch: the fresh worktree is at origin/main, and the note lists the old commits.

### F8 [medium] AC7's spec pins only the live refusal: `--takeover` on a parked, unknown or multi-claim worktree is unpinned, and those are the cases where a wrong discard destroys a working session
Where: Rules row "a live or parked claim cannot be taken over by `--takeover` … | discard :: a live claim cannot be taken over…". Step 1 ("every one must be lost or already ended … `parked`, or why it could not tell").
Evidence: discard.spec tests only a 60-second-old claim. An implementation that judges with `judge` alone (no `settle`: stale counts as lost), or that treats a failing `gh` as `[]`, passes AC7. Yet a prep waiting on its review or the user, with an open PR, is parked: the most common long-silent state. A rafting worktree remembers the raft and its members' claims, and "every one must be lost" with two claims is never exercised.
Recommendation: add cases for a parked claim (a PR in the fake gh's list), refused with "parked" and nothing moved; for gh exiting 1, refused with "could not tell"; and for a worktree holding one lost and one live claim, refused. Name parked and unknown in AC7's label.
Lesson: zz-test/guard-needs-its-own-case

### F9 [medium] AC6 still greps z-design for `--from origin/prep-`, which the Design no longer prescribes
Where: check.sh line 26 (`g "--from origin/prep-" "$R/skills/z-design/SKILL.md"`). The Design's skills paragraph now says "take over a lost prep with `./zn worktree prep-<slug> --takeover` (never plain `./zn worktree`…)" and "continue a lost prep from `origin/prep-<slug>`". The `--from` form was removed from Assumptions ("Takeover").
Evidence: `grep -n 'from origin/prep' z-nile/skills/z-design/SKILL.md` finds nothing today. An executor who writes the skill text the Design gives fails AC6. To pass it, the executor must add a `--from origin/prep-` line that contradicts "never plain `./zn worktree`".
Recommendation: drop that grep, or replace it with one for the sentence the Design now gives. Sweep the rest of AC6 against the skills paragraph (`re-adopt` is still there). Add `worktree <name> [--takeover]` to the usage-text grep on line 21 (lesson exhaustive-lists-name-new-things).
Lesson: z-design/restated-rules-move-together

### F10 [medium] Review 014 F3 and F5 were answered in text only: the co-beater silence and the dispatcher's step-made-claim stamp have no case and no row
Where:
- The lease and ownership ("What is **said** … a failure whose git message does not contain `(stale info)` … retry silently").
- The dispatcher ("or, for a step that makes its own claim, the stamp in the memory of the step's worktree, re-read at each tick").
- beat.spec, lost.spec and both proofs are unchanged since review 014, and no Rules row names either rule.
Evidence:
- beat.spec's T0+1000 case rejects the worktree's remembered lease against main's T0+600 commit, but asserts nothing about stderr. An implementation that prints every rejection passes, and so does one that silences every failure.
- dispatch.spec's fake step never claims mid-step. An implementation that keeps `--stamp` empty for such steps, so they are never beaten, passes AC4.
- "Re-read at each tick" is also the path F1 shows reading the taker's memory.
Recommendation:
- Add a beat.spec case: another terminal's newer commit of the same stamp, then a worktree beat that lands with empty stderr; plus a non-lease failure, which is said.
- Add an `acceptance/` dispatch case in which the fake step claims mid-step and a beat of its stamp arrives after the claim, so the pinned proof need not change.
- Add a row for each.
Lesson: z-design/spec-design-correspondence

### F11 [low] Leftover gaps
- Review 014 F7's lows are still open:
  - `--watch` on a stamp that was lost before it started exits 1 (lost.spec 485), while `stop-restamped` exits 0. Say that the binding check runs before the first tick.
  - An empty sha after a failed attempt should be passed as `nil`.
  - `release` is missing from "When the branch is deleted".
  - zz-rules' Run state already calls a dead-supervisor dispatch run "lost".
- `heartbeat.nextSuffix(name, taken)` gives one name. For a raft the directory is `R0010-<n>` and the branch `R0010-<slug>-<n>`. Say that `taken` holds both, each mapped to its suffix, so that a stray `R0010-<slug>-1` branch moves the number on.
- Say whether `--adopt --stamp` reads the memory. The text says only that it "writes none".
- The verdict in step 1 and the move in step 3 are not atomic. An old process that beats in between is still discarded, and the taker's later claim is then refused as alive. Re-judge just before the move and state the outcome.
- `.cache/discarded` lives in the old worker's own checkout, which can delete it (lesson zz-arch/guard-state-out-of-reach-or-checked). Say that the stamp check is the backstop (the memory differs from origin's, so `prepared`, `done` and `beat` still refuse); this holds only once F2 is fixed.
- `worktree-prune` already keeps `R0010-1` and `prep-x-1` as "named worktree" (main.luau 3787). The new "kept: holds the discarded work of <id>" text needs only a check for `.cache/discarded`. Say so.

Verdict: changes
