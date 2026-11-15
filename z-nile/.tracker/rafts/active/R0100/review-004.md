# Review 004: R0100 (code mode)
Inputs: layer 5 (c0277), `git diff R0100/4/c0276...R0100/5/c0277` (layer 5 at d1e5db07a, layer 4 at a75d01dac, `origin/main` at f99ccb0b5). I read the files with `git show R0100/5/c0277:<path>`. Also read: c0277.md (Design, Rules and mutants, Acceptance criteria, Verification log), its check.sh, acceptance/{plan,discard,recover,guard,sweep,reready}.spec.luau and proofs/discard.spec.luau, R0100.md (Whole-raft design, Layer rules, Interfaces, Experiments, Risks) and its check.sh, and review-003.md.
Checked:
- Runs. Each ran in a scratch repository made with `git archive`, never in the worktree, and each through `./zn run`. The scratch repository has the layer-4 tree on `main` and the layer-5 tree on the branch `R0100/5/c0277`, so the affected selection is this layer's. Slow and real-time runs went one at a time.
  - `z-nile/check.sh --project z-nile --affected`:
    - Every static stage passes: format (review-003 F1's long line is split on this tree), lint (0 warnings), types and skills.
    - `GATE PASSED (affected)`: 799 passed, 0 failed, 137 spec files. All six c0277 acceptance specs are in that run. Gate wall time 59.6 s.
  - `./zn check c0277`, alone after the gate: 7/7. That includes the pinned proof `proofs/discard.spec.luau` (AC4 and AC7 check its hash).
  - The slow-tier specs that drive the commands this layer changes: `c0005/worktree`, `tooling/worktree-fetch`, `c0053/commands-sync`, `c0114/roots-cli`, `c0046/launch`, `c0068/stop`, `c0116/retired` and `c0117/dispatch-cli`, run as one `--jobs 1` run.
    - Result: 8 spec files, 88 passed, 1 failed.
    - The one red is `c0116/retired` :: "on a clone holding a retired raft, …", which fails on its nested `c0114/classified` case "no feature or defect is filed in z-nile's root".
    - Both are in the raft's Experiments list of the eight slow-tier cases that are already red on `origin/main`. This layer files no item.
  - The raft's RC2, RC3 and RC5 greps on the tree:
    - Each shared interface is defined once.
    - `local hb` is declared once, and `boardview` is kept.
    - Every pinned phrase is in `z-run/SKILL.md` and `z-work/SKILL.md`.
  - Two scratch specs of my own, in the scratch copy only, under their own `.cache` names:
    - one on `sweep.spec`'s fixture (F1);
    - one that copies `reready.spec` and prints the later lookup's stderr (F2).
- The 200-local cap. I compiled padded copies of `main.luau` with `@lune/luau`, adding one unused `local _padN = {}` per step.
  - Layer 5 has 10 spare top-level locals, the same as layer 4. `origin/main` has 4.
  - The layer adds no top-level local. Every new function is a field of `hb` or `cm`, the new constants are `hb.DISCARDED` and `hb.FRESH`, and `type Wt` costs no register.
- Sequestration.
  - Over `check.sh`, `acceptance/` and `proofs/`, the layer diff lists only `M z-nile/.tracker/issues/active/c0277/acceptance/watch.txt`.
  - That is the watch map `./zn finish` writes. It gains `z-nile/tests/lib/cachepaths.luau`, a file this layer changes. zz-review item 2 does not name watch maps yet; c0326 captures that.
  - Across the whole stack against `origin/main`, the only changes besides `R100` renames are the members' four watch maps.
- The port.
  - `heartbeat.staleMember`, `heartbeat.isMember`, the split of `hb.takeover` into `hb.takeover` and `hb.discard`, and the family lookup in `cmd.worktree` are all in.
  - `hb.judgedFor` is the one verdict read: `setStatus` and `hb.takeover` both call it.
- Design adherence:
  - **Pure part:**
    - `suffixOf`: digits from 1, no leading zero, the base escaped.
    - `nextSuffix`, `currentOf`, `baseOf`, `fresh` and `ownsBranch`.
    - `isMember`: the bare name always; a copy only on the family's branch, or, for a raft, detached or on one of its layers.
    - `discardRefusal`: c0274's reasons, and a worktree that remembers nothing is refused.
    - `staleMember`: a held claim keeps the member.
    - The marker's writer and its one reader. `discardParse` needs every header key, and `discardedText` refuses a damaged marker with its own text.
    - `discardEnded`, `keepReason`, and the optional fourth argument of `gone`. c0275's three-argument calls are unchanged.
  - **`--takeover`:**
    - It refuses in a protected checkout, without an origin, and from the worktree it would discard.
    - It finds the worktree by name, or by id. By id it takes the worktree whose memory equals the stamp on `origin/main`, then the copy a discarded worktree left, then `prep-<slug>` or the raft's own name.
    - It refuses a fresh copy, and `--item` on a branch that is not the item's own.
    - Every claim is judged with one `hb.judgedFor`.
  - **`hb.discard`:**
    - It reads the facts first, and a failed `git status` refuses before anything moves.
    - The marker is created exclusively: a temporary file hard-linked in with `ln`.
    - It renames the branch and unsets its upstream. A detached head with commits gets a branch, `discarded-<R-id>-<n>`.
    - `git worktree move` renames the directory, and `--track -b` adds the copy from `origin/<branch>`.
    - The marks and the pid files are deleted.
    - On a failure it undoes only its own steps. The marker stays when a step cannot be put back.
  - **The refusal:**
    - It runs in the dispatch before `guardRepoRoot` and `hb.begin`, for every command not on `READ_ONLY`, except `reap`.
    - `zn` changes to the checkout's top first, so `.cache/discarded` resolves from a subfolder too.
    - `goneNow` reads the marker.
    - `claimBeat` stops when the step's folder is missing or marked, and writes the step's `questions.md`.
  - **The sweep:**
    - It runs in `sync` in the main checkout, in `worktree-prune`, after `done`'s branch drop and after `stop`'s publish.
    - It returns at once when no worktree is marked, and removes nothing when `origin/main` cannot be read.
    - It never removes the folder it runs in.
    - A plain `reap` lists what is left, and the quiet forms of `reap` do not.
  - **The plain lookup:**
    - It discards, through `hb.discard`, a member that remembers a claim `origin/main` shows under another stamp or under none, when no claim it remembers is still its own, and it prints the copy.
    - When `origin/main` cannot be read, it hands the member out.
    - A family with a discarded member prints the notice.
- Skills and docs.
  - The layer 2 and 3 sentences are replaced:
    - z-design's "(never in the old worker's checkout)" is now the two-command takeover.
    - z-run's "in a worktree that holds no claim of the old lead's" is now the `--takeover` path, plus the lookup after a stop and a ready.
  - A search of the skills finds neither old sentence. z-design keeps "Never enter the old worker's checkout", which is right.
  - These carry what AC6, RC3 and RC5 pin:
    - zz-rules: the worktree and prune rows, the main-checkout list and the Discarding paragraph;
    - z-design: push after every commit, with `./zn sync --fetch` first;
    - z-raft;
    - z-stop: steps 3 and 4;
    - z-work: steps 1, 7 and 10;
    - zz-execute: Phase 0;
    - the README row.
  - F2 and F3 are about what some of them say.
- The dispatcher.
  - `claimBeat` gains a fifth optional argument.
  - Its loop polls once a second. It returns when the step's folder is gone or marked, after it calls `onDiscard`.
  - The `questions.md` that `onDiscard` writes stops the chain the way any question does (`proofs/discard`).
- Repository safety and bounded commands.
  - The layer adds no spec, `check.sh` or script, and no guard file changes.
  - The c0277 specs build their fixtures under `.cache/c0277-*`.
  - Every new remote read goes through `hb.netRetry`, and nothing new starts in the background.
- Lessons searched: `porcelain`, `quoted path`, `restated rules`, `git output parse`, `fixture names`.

### F1 [high] The sweep removes uncommitted work whose path `git status --porcelain` quotes or writes as a rename, so a discarded worktree loses work that exists nowhere else
Where: z-nile/engine/main.luau:5995-6012 (`hb.unrecovered`, the uncommitted-file loop); :5947 (`git worktree remove --force`); :5974 (the ref the commit count reads); :5807 (the note's list of dirty files)
Evidence:
- **The reader.** `hb.unrecovered` reads `git -C <path> status --porcelain`: format v1, without `-z`. It takes `string.sub(line, 4)` as the path (6000). Git does not print every path as it is. Probed with git 2.54 through `./zn run`:
  - A path with a space or a non-ASCII byte is quoted and C-escaped: `?? "pickman/my notes.txt"`, `?? "\303\274n\303\257.txt"`.
  - A staged rename is printed as `R  old -> new`.
- **The fall-through.** For such a line, `abs` names no file and no folder, and `origin/main:<rel>` does not resolve. So the branch `elseif fs.isDir(abs) or inMain.ok` (6009) does not count the line, and it reads as "a deletion that main lacks too": recovered.
- **The removal.** The sweep then runs `git worktree remove --force` (5947), which deletes untracked and modified files. The comment above that line says "every uncommitted file and commit was found in main above". That claim is what breaks.
- **Reproduced on the layer-5 tree** with a scratch spec on `sweep.spec`'s fixture, run in the archive copy only (`.cache/r004-probe`):
  - Two preps were claimed, each in its own worktree.
  - `prep-spaced` left an untracked `pickman/my notes.txt`.
  - `prep-ren` pushed a 40-line `pickman/doc.txt`, then ran `git mv` to `doc2.txt`, added a line and staged it.
  - `git status --porcelain` there read `?? "pickman/my notes.txt"` and `R  pickman/doc.txt -> pickman/doc2.txt`.
  - Both were taken over (`worktree <name> --takeover`). Both claims were given back from the copies, and `./zn sync` ran in the main checkout.
  - Its stderr: `removed discarded worktree …/prep-ren-discarded-1` and `removed discarded worktree …/prep-spaced-discarded-1`.
  - Neither file exists afterwards. Both held work that existed nowhere else: an untracked note, and an edit that was only staged.
- **The same test misses three more cases:**
  - An untracked folder whose name needs quoting: at the quoted path there is no folder, so it is removed as well.
  - A staged version that differs from the work-tree copy (`MM`). Only the work tree is compared, so the staged content goes with the worktree.
  - A commit the old process made on a detached HEAD in the renamed folder after the discard. The count reads `d.branch` only (5974), so that commit is not counted.
- **Why the gate is green.** `sweep.spec`'s uncommitted case uses `pickman/untracked.txt`, a name git prints unquoted, so AC5 passes with this reader.
- **The note.** The discard's note (5807) lists the same quoted strings and `old -> new`. That is cosmetic: the files stay until the sweep.
Critique:
- **The promise.** AC5 says a discarded worktree is removed "unless it holds unrecovered work". The Design's "Assumption to veto: nothing unrecovered is ever removed" and zz-rules' "removal never loses work" say the same.
- **Where it bites.** The sweep runs on every `./zn sync` in the main checkout, and on `stop`, `done` and `worktree-prune`.
- **Why nothing else catches it.** `--force` turns off git's own refusal to remove a dirty worktree, so the content test is the only guard. Any path git quotes (a space, an accent, a quote mark) and any staged `git mv` is deleted, and nothing is printed.
- **The tempting fix** is to strip the quotes. That still misreads C escapes (`\303\274`, `\"`), the rename arrow, and any name that contains ` -> `.
Consequences:
- **Output shape.** With `-z`, every entry ends in a NUL, and an `R` or `C` entry carries a second NUL-terminated path: the original.
- **A rename is two facts.** The new path is judged by its content. The old path is a deletion that `origin/main` still has, so it counts as unrecovered. That fails closed: a worktree whose only change is a pure rename is kept and listed by `reap`, never deleted.
- **One reader.** The note's list must use the same parse.
Recommendation:
- **One reader.** Add one pure reader of `git status --porcelain -z` in `heartbeat.luau`, for example `heartbeat.statusEntries(z): { { xy: string, path: string, from: string? } }`. Use it in both `hb.unrecovered` and `hb.discard`'s note.
- **Recovered only on an explicit yes.** In `hb.unrecovered`, a path counts as recovered only in one of two cases:
  - It is a file whose work-tree blob equals `origin/main:<path>`, and whose staged entry, when it has one (`git rev-parse :<path>`), equals it too.
  - It is absent from both the work tree and the index, and `origin/main` lacks it.
- **Everything else is unrecovered:** a folder, a path that does not resolve, a conflict entry, the old path of a rename that main still has, and a read that fails.
- **Commits.** Count commits from `HEAD` as well as from `d.branch` (`rev-list --count <d.branch> HEAD --not --remotes=origin [pushed]`), and run the merge-tree test over both.
- **Cases.** c0277's acceptance specs are sequestered, so the cases go in a new spec that is not, for example `z-nile/tests/tooling/discard-sweep-paths.spec.luau`, with its own `.cache` name (c0049) and its watch map.
  - Each of these must be kept and listed:
    - an untracked file with a space;
    - an untracked file with a non-ASCII name;
    - an untracked folder with a space;
    - a staged rename with an edit;
    - a staged change whose work-tree copy equals main;
    - a commit made on a detached HEAD after the discard.
  - A clean worktree must still be removed, so that the reader does not simply keep everything.
  - Add pure cases of the reader.
- **The comment.** Fix the comment at 5946.
Lesson: zz-arch/guard-no-is-explicit

### F2 [medium] A session that stopped its own raft and readied it again is told both to continue in the copy and that it was discarded and must stop
Where: z-nile/skills/z-run/SKILL.md:12; z-nile/skills/z-work/SKILL.md:16 (step 7); z-nile/skills/zz-execute/SKILL.md Phase 0 step 1; z-nile/engine/main.luau:6114 (the family notice); c0277.md Design ("A process that is routed to the lookup is told (review F1)")
Evidence:
- **The z-run shim contradicts itself in two consecutive sentences.**
  - The first: "After you stopped a raft yourself and readied it again, the plain `cd "$(./zn worktree <R-id>)"` does the same on its own: … the lookup discards it and prints the numbered copy, where `./zn beat <R-id> --adopt` works."
  - The second: "A session whose worktree is gone, or whose `./zn` commands all refuse with `this worktree was discarded`: you were discarded. A named session … says so and stops."
  - After that lookup, the session's worktree is gone: it was renamed `<R>-discarded-1`. So the second sentence's condition holds for the very session the first sentence told to continue.
- **z-work step 7 says the same, and names this exact case.** "…or the folder you were working in is gone, or a lookup tells you your old path was discarded, you were discarded (a taker took your claim over, **or the raft was stopped and readied again**) … A named session says so in one line and stops." zz-execute Phase 0 has the same pair of sentences.
- **z-stop step 4 says the opposite.** "A lead who stops and re-readies its own raft continues in a numbered copy of its worktree … like any taker."
- **Every later lookup tells that lead it was discarded.** The second scratch spec ran `reready.spec`'s own path (`ready`, `beat --adopt`, `stop`, `ready`, the lookup, `--adopt` in the copy) and printed the stderr of the lookup after it. It reads: `notice: …/.worktree/R0020-discarded-1 was discarded (R0020 was taken over); …/.worktree/R0020-1 is the taker's. If your work was in …/.worktree/R0020-discarded-1, you were discarded: clear your context and pick up something new.`
  - Nobody took R0020 over: the same lead stopped it and readied it.
  - The folder the notice names is the one that lead worked in. It was only renamed, and `pwd -P` in a shell that stayed there reads that path (E5).
- **The notice names the renamed path, not the old one.**
  - The Design specifies `notice: <old path> was discarded … If your work was in <old path>, you were discarded`. The code prints the renamed path.
  - The marker's header has no old path: its only paths are `discarded worktree:` (the renamed one) and `copy:`. So the old path cannot be printed.
  - The Verification log does not record this deviation.
- **When it happens.** z-work step 8 says Kimi, Grok and Cursor sessions cannot clear, and "Carry on" in the same session. A person who runs z-stop, z-ready and then `/z-run <R>` in one Claude session lands here too.
Critique:
- This is the flow AC7 exists for. A session that follows step 7 stops a raft it should continue. Or it learns to ignore the "you were discarded" notice, which is the one signal the lookup gives an old lead that really was discarded.
- **Tempting fix 1: print the original path in the notice.** The re-readying lead's work was in that path, so it would read "you were discarded" on every lookup.
- **Tempting fix 2: drop "or the raft was stopped and readied again" from step 7.** That leaves no rule for an old lead whose raft someone else stopped and readied (z-stop step 5, a lost raft).
Consequences:
- **The deciding fact.** The rule needs a fact the session itself holds: whether it ran `./zn ready <R>` after the stop. The lookup's own discard notice ("… so it was discarded; <copy> is the numbered copy to work in") already marks that moment.
- **Agreement.** The skills and the two notices must say the same thing.
- **Pins.** RC3, RC5 and AC6 pin these phrases, and they must stay: `you were discarded`, `does the same on its own`, `never run \`./zn worktree <R>\``, `drops the raft id`, `with no raft`, `--adopt`, `picks up something new` and `numbered copy`.
Recommendation:
- **One rule, worded the same in z-work step 7, the z-run shim and zz-execute Phase 0:**
  - A session that itself ran `./zn ready <R>` after the stop continues in the copy the lookup printed, and runs `./zn beat <R> --adopt` there (z-stop step 4).
  - Any other session whose worktree is gone, whose commands refuse with `this worktree was discarded`, or whose path the notice names, was discarded. It stops, or drops the raft id, as now.
- **The notice wording.** Either of these:
  - Change the marker and the notice:
    - Record the old path in the marker as an optional header key, `was: <old path>`. `discardParse` still reads a marker without it.
    - Print `<old path> (now <renamed path>) was discarded …; unless you readied <R> again yourself, if your work was in <old path> you were discarded`.
    - Word "taken over" as "taken over or stopped and readied again".
    - Add a case in a spec that is not sequestered. `discard.spec` still passes: it pins only `you were discarded` and the renamed path.
  - Or keep the renamed path, and record the deviation and its reason in the Verification log.

### F3 [low] Comments, the Design and the restated rules say things the code no longer does
Where: z-nile/engine/heartbeat.luau:522; c0277.md Chore checklist, Guards (line 170), and Design ("costs no network call", line 148); z-nile/skills/zz-rules/SKILL.md:48 (the main-checkout list), :96 (the prune row), :202 (Heartbeat and lost work); z-nile/skills/z-stop/SKILL.md:13 (step 3)
Evidence:
- **heartbeat.luau:522.** The module comment says "the old worktree stays at its path with a marker, its branch is renamed". That is the hand-off's reading, which the Design rejected (Readings, 1). The code renames the directory.
- **c0277.md, Guards.** It says "the sweep removes only what `git worktree remove` removes without force and a branch whose commits are all on origin". The Design's sweep bullet and the code use `--force` (main.luau:5947), and they delete a branch whose change is only in main by content (the merge-tree test).
- **zz-rules, prune row.** It says "keeps the rest, never forces", next to the sweep's forced removal.
- **zz-rules, Heartbeat bullet.** It says a detached head with commits "gets that branch", meaning `<branch>-discarded-<n>`. The code names it `discarded-<R-id>-<n>`.
- **z-stop step 3.** It says `stop` "removes the worktrees discarded for this raft". `hb.sweepDiscarded` removes every discarded worktree whose items are no longer live, whatever raft or prep they belong to.
- **zz-rules, main-checkout list.** It names `--takeover` and the sweep as what renames or removes worktrees there. A plain `./zn worktree <name>` run from the main checkout now also renames a worktree and its branch (`hb.discard`).
- **c0277.md, Design.** It says a member whose claims are all its own "costs no network call". The lookup calls `hb.beatPaths()` (main.luau:6076, a bounded `git fetch origin main`) for every member that remembers a claim. That is a second fetch, after the lookup's own `git fetch --prune origin`, on every z-run `cd "$(./zn worktree <R>)"`.
Critique: c0180 and the next takeover item will read these lines. A reader who trusts "never forces", or "removes only what `git worktree remove` removes without force", will not look for F1's hole.
Consequences:
- Nothing beyond the text, unless the second fetch is dropped.
- If it is dropped, the lookup reads `origin/main` as its own fetch left it (`originTree()`), and a failed fetch leaves a stale read.
- That is the same staleness as any read after the plain lookup's unchecked fetch. The unreadable case still hands the member out.
Recommendation:
- **heartbeat.luau:522.** Fix the comment.
- **c0277.md.** Correct the Guards line, or record in the Verification log that the sweep forces and judges by content.
- **zz-rules:**
  - Say "never forces" of the raft worktrees only, and "the sweep removes with `--force` after its content test".
  - Name `discarded-<R-id>-<n>` for a detached head.
  - Add the plain lookup's discard to the main-checkout list.
- **z-stop step 3.** Say "removes every discarded worktree whose work has ended, those discarded for this raft among them". That keeps the pinned phrase `discarded for this raft`.
- **The second fetch.** Drop it (read `originTree()` after the lookup's own fetch), or record its cost in the Verification log.
- **Pins.** None of the other strings is pinned:
  - AC6's zz-rules words are `Discarding and recovering`, `-discarded-`, `.cache/discarded`, `.cache/fresh`, `family` and `discards it as a worktree of a claim already over`.
  - z-stop's are `--takeover`, `numbered copy`, `discarded for this raft` and `returned`.
Lesson: z-design/restated-rules-move-together

### F4 [low] The Verification log leaves out three things the raft and the issue ask of this layer
Where: c0277.md Verification log (2026-11-14), against R0100.md Risks ("Existing worktrees on the day layer 5 lands (design-review-002 F7)") and Experiments ("The slow tier"), and c0277.md Implementation steps (step 1) and Unknowns & experiments (U1)
Evidence:
- **The worktree list.** The log names two "active worktrees at the time". The repository has 24 worktrees under `.worktree/` that hold claim memory (`.cache/tracker-claim-*`). Among them:
  - `prep-automatic-heartbeats` remembers c0275, which is now active under R0100's stamp;
  - `raft-provenance` remembers R0099;
  - `raft-d0298` remembers eight rafts;
  - `prep-agents-md-pipeline-only` has 6 uncommitted files.

  Once this lands, the first plain lookup of each one whose claim is over discards it. Risks F7 asks the executor to list the active worktrees and their owners in the PR.
- **The slow tier.** The raft's Experiments and c0277's Implementation step 1 ask the layer-5 executor to run its six slow specs and those of layers 1 to 3 once before `finish`. The log records only `./zn check c0277` and the affected gate. My run, in Checked, covered eight of them: 88 passed, and 1 failed, the case that is already red on main.
- **U1.** Implementation step 1 makes U1 the executor's first probe: a real Claude Code session whose project folder is renamed. The log records neither a result nor the fallback it took.
Critique:
- The PR body is where the owners of those worktrees learn that their next lookup renames their folder.
- The slow tier is the only run of `c0005/worktree` and `tooling/worktree-fetch`, and this layer rewrote `cmd.worktree`.
Consequences: none.
Recommendation:
- Add the 24 worktrees and the items they remember to the Verification log and the PR body. Mark which claims are over now (those worktrees are discarded at their first lookup) and which worktrees hold uncommitted files.
- Record the slow-tier run, including the four specs of layers 1 to 3 that my run did not cover (`c0067/ready`, `c0116/claims`, `c0117/control-cli`, `tooling/dispatch-guards`).
- Record U1's result, or the fallback taken: the marker is the signal.

## Judged criteria (code mode only)
- None. c0277 has no Judged or Observed criteria.
- Each Checked criterion passes on the layer-5 tree. Here is the code each one rests on; the code matches c0277's Design except where F1 to F3 say otherwise:
  - AC1: the pure rules in `heartbeat.luau`.
  - AC2: `hb.takeover` and `hb.discard`.
  - AC3: the note, the kept branch and the kept folder.
  - AC4: `hb.refuseDiscarded` before `hb.begin`, `goneNow` and `claimBeat`.
  - AC6: the docs.
  - AC7: the plain lookup and `heartbeat.staleMember`.
- AC5 passes `check.sh`, but the implementation does not meet it for the paths in F1.

Verdict: changes
