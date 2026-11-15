# Review 001: R0099 (design mode, raft)
Inputs: branch `raft-provenance` at d3dd0aac4df21da646518ea14c155c0b379516e8 (`z-nile/.tracker/rafts/R0099/R0099.md`, `check.sh`), origin/main 672423a05, the five member folders, `origin/proto-c0263-raft`, `origin/proto-c0280`, `origin/proto-c0282`, `origin/proto-c0283`, `origin/proto-c0284`, `origin/R0092/1/c0264`, `z-nile/engine/main.luau` (`cmd.approve`, `cmd.board`, `runCheck`), `z-nile/lib/ac.sh`, `z-nile/engine/approval.luau`, `.models.toml`, R0096.
Grouped: [c0263@1b93fc9d0c76, c0280@9db248601f55, c0282@82e8b1f127ef, c0283@57692835e816, c0284@27c0dce08c9e]

I recomputed each member's record hash with `raftplan.recordHash` over its folder in this worktree. All five match `grouped:`. The Order names the five members, each once, and no other item id. `./zn workstreams R0099` prints `parallel: no`, with the same wave order as the Order section. The `AGENT_MARKERS`/`AGENT_VARS` alias satisfies both members' specs as written: c0282's `provenance.spec` counts and loops over `AGENT_MARKERS`, and c0283's `approval.spec` reads `AGENT_VARS` with `toEqual`. The probes below ran through `./zn run --time`, from scratch scripts in the worktree's `.cache/rv99/`, which I removed afterwards.

### F1 [high] An `approved` row never reaches main on `approve --publish`, which is the approval path for every prep the dispatcher merges
Where: R0099.md:59 (`publish.luau` … "Agree") and :99 (E1, `publish.luau`); c0283.md Behaviour 2; c0263.md:72 and :94 (`provenance.PUBLISHED`)
Evidence: `.models.toml:12` sets `auto_merge = ["prep", "raft"]`, and `cmd.approve` refuses under `ZN_DISPATCH` (main.luau:5722). So a dispatched prep PR merges before any human approves. Afterwards `ready` refuses the issue with approval.luau:123: "run ./zn approve {id}, then ./zn approve {id} --publish". On main, `--publish` (from #330, 2026-11-13, so after c0283's prep) publishes `approval.md` alone: `publish.commit(... { { path = path, content = localText } } ...)` at main.luau:5812. c0283's Behaviour 2 writes the `approved` row into `provenance.md` in the local `tracker: approve <id>` commit. That commit is never pushed, because the prep branch has already merged. c0263's validator would refuse the row in any case, since `PUBLISHED` is `unblocked`, `confirmed`, `ranked`. The raft notices this ("c0283's row travels in the prep PR and `approve --publish` publishes `approval.md` alone") and marks it "Agree". But the row travels in the prep PR only when the human approves before that PR merges, and auto-merge prevents that. Result: for every dispatched prep, `./zn who` (c0280) and the board (c0284) show no approver. This is c0263's captured outcome "Design approved by: the human who approved the design … The board shows them", and c0283's "records … in c0263's record". c0280 derives nothing for approvals ("nothing is derived for it"), so nothing fills the gap.
Critique: the tempting fix is to add `approved` to `provenance.PUBLISHED`. That would let `./zn provenance record <id> approved --actor human:anyone` publish an approval that no `approval.md` backs, which reopens the "a human ran it must be true, not just reported" decision.
Consequences: a published `approved` row needs a check that ties it to the `approval.md` row published in the same commit (same human, `design=` equal to the first 12 hex of that row's hash). `publish.luau` then gains a second writer (c0283), so the Whole-raft design's "c0263 only" changes. Rows already stranded in worktrees: none exist before c0283 lands.
Recommendation: this needs a change to c0283's design, so z-raft takes c0283 out of the raft (`./zn unfold R0099 c0283`) for a re-prep (lesson z-raft/rafted-member-changes-stay-in-the-raft), then folds it back with a new coherence review. The re-prep:
- `approve --publish` publishes `approval.md` and `provenance.md` in one commit.
- c0283 adds a validator branch in `publish.luau`: `provenance.md` may gain exactly one appended `approved` row only when the same commit appends an `approval.md` row whose `who` is the row's human and whose hash starts with its `design=`. `PUBLISHED` stays as it is for `./zn provenance record`.
- Spec cases: publish after the prep merged carries both files; an `approved` row without a matching `approval.md` change is refused; `./zn provenance record <id> approved` stays refused; a second approval appends.
- R0099's Whole-raft design then lists `publish.luau` under c0263 and c0283 and drops "Agree" here.

### F2 [high] E1b's chunked `who.fronts` breaks c0284's AC3 at real scale and misstates the cause; streaming one process keeps every member's text true
Where: R0099.md:102 (E1b), :123 (Risks, "The history read outgrows one process"); c0284.md:177 (AC3), c0280.md:103 and :192
Evidence: c0284's AC3 says "exactly one mainline log, one people log, one cuts log, one `git cat-file --batch` … for any number of items". c0280:103 says "one `git cat-file --batch` for the item's document commits". The raft's fix uses one cat-file per 400 keys, which makes AC3 false on the real tree. The spec still passes only because its fixtures are small. A spec that passes while its criterion is false is an unmet criterion, and the final trace (AC3 to code) would cite code that contradicts it.

The stated cause ("`process.exec` stalls once one process's output passes about 100 MB") is also wrong. The stall depends on how many keys go to stdin, not on output size. My probes (`.cache/rv99/p.luau`, `process.exec("git", {"cat-file","--batch"}, {stdio={stdin=…}})`):

| keys | blob | stdin | output | result |
|---|---|---|---|---|
| 3,000 | 1 KB | ~123 KB | 3.3 MB | returns |
| 4,000 | 1 KB | ~164 KB | ~4 MB | stalls (stopped at `--time 20`) |
| 6,000 | 1 KB | | 6.6 MB | stalls |
| 400 | 834 KB | | 333 MB | returns in 0.7 s |

The raft's own 6,000-key run confounded the two variables. Chunks of 400 keys happen to be safe. But the raft also says "c0284's text … becomes 'five plus one per 400'". If the executor edits c0284.md's Design or Acceptance criteria, c0284's approval contract changes, and `./zn done` refuses the member.
Critique: an executor could keep the chunks and reword AC3. That changes an approved member's criterion inside the raft.
Consequences: a streaming reader writes stdin while it reads stdout. It must close stdin and read to EOF, as `runner.luau` already does with `process.create`. Fixtures are unaffected: same one process, same `GIT_TRACE` line. A future reader with a large stdin (`who.sideTrailers`' `git log --stdin`, 8 first-parent merges today) has the same exec limit.
Recommendation: replace E1b's fix with one streamed process. `who.fronts` runs `process.create("git", {"cat-file","--batch"}, {cwd = dir})`, writes the keys from a `task.spawn`, closes stdin, and reads stdout to EOF. My probe `.cache/rv99/q.luau` did exactly this and returned 6,000 keys in 0.12 s and 20,000 keys in 0.26 s, both exit 0. That keeps c0284's AC3 and c0280:103/:192 true as written, with no member edit.
- Correct E1b's cause to "stdin key count above about 3,000, not output size".
- Delete "becomes five plus one per 400" from E1b and Risks.
- State that no member's design sections are edited (see F7).
- Add RC5 to pin AC3 at real scale. Run `GIT_TRACE="$t" "$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" board -O --out "$ZN_ROOT/.cache/r0099-rc5/board.html"` and require exactly one `built-in: git cat-file --batch` line in `$t`. First confirm on the prototype that the build makes no other cat-file call; if it does, compare against main's count plus one.

### F3 [medium] The R0096 wait stops the raft at layer 3, not at `done`, and R0096 itself waits for three chores nobody has designed
Where: R0099.md:88, :90 to :92 (Cross-raft waits), :127 (Risks, "R0096 not landed")
Evidence: the raft says "R0099 may be readied and run before it, but its last layer cannot pass `./zn done` until R0096 has landed." zz-execute step 4 finishes an issue only when "`./zn check <issue>` shows every AC as PASS", and `./zn start` "waits until `./zn finish` has made the one below a single commit". c0282 is layer 3, and its AC7 runs `tests/acceptance/c0116/claims.spec.luau` (c0282/check.sh:24), so c0282 cannot finish, and c0283 and c0284 cannot start, until R0096 lands. R0096's own Cross-raft waits say "z-ready refuses R0096 until all three [c0266, c0302, c0304] are in `done/`". `./zn find` today: c0266 `new-jolly-badger-crimson`, c0302 `new-toucan-quiet-otter`, c0304 `new-lynx-mellow-indigo`, all with empty `raft:`. Each still needs z-design, a raft and execution (lesson z-raft/grouping-cost-checks-every-wait: take each wait's status from `./zn find` at rafting time).
Critique: if the text stays as it is, a lead readies R0099, delivers two layers, and then stalls with an open stack for an unknown time, or finishes c0282 with AC7 red against step 4.
Consequences: either option below changes the Order's stated reasons, and RC2's wording if the order flips.
Recommendation: write the full chain in Cross-raft waits (R0096 ← d0298 ← c0266, c0302, c0304, all `new` and unrafted on 2026-11-14) and say the wait bites at c0282's finish. Then pick one:
- (a) Order c0263, c0280, c0283, c0284, c0282, so only the last layer waits. No member depends on c0282 (`depends_on`: c0283 [c0263], c0284 [c0263, c0280]). c0283 then defines the list, `provenance.AGENT_VARS = {…}`, which matches c0263:113 and c0280:68 ("loops over `AGENT_VARS`"). c0282 adds `provenance.AGENT_MARKERS = provenance.AGENT_VARS`. Both specs still pass (both only read the list). RC2 becomes `^provenance.AGENT_VARS = {` once plus the alias line. The claim that "c0284's spec covers every earlier row" is then held by RC0, which reruns every member's check on the final tree (lesson z-raft/order-reasons-survive-workstreams).
- (b) Do not ready R0099 until R0096 is in `done/`. This costs waiting for three chores nobody has designed.

Either way, the lead stops and reports when R0096 lags. No spec changes.

### F4 [medium] RC1 turns red on any emergent issue, and `check.sh` cannot change during execution
Where: check.sh:16; R0099.md:116
Evidence: RC1 requires `./zn members R0099` to equal exactly "c0263 c0280 c0282 c0283 c0284 ". `./zn members` lists "every issue naming this raft, including emergent ones" (check.sh:9). zz-rules, Emergent issues, step 1: `./zn new issue d <slug> --raft R0010` creates a member with `emergent: true`. The raft keeps an "Addressed during execution" section for exactly that case. One emergent issue makes RC1 fail at `done`, and the sequestered file can't be changed (lesson z-raft/plan-the-switch-over). RC1 also claims "each named once in the Order", which it never reads. `./zn start` checks that through `stack.order`.
Critique: dropping RC1 removes the only check on membership.
Consequences: the fixed RC must read each member's `emergent:` front matter.
Recommendation: RC1 passes when the five ids are all members and every other member has `emergent: true` in its document. Spec cases (run on the branch): the five alone pass; the five plus an emergent issue pass; a missing member fails; a non-emergent extra fails. Drop "each named once in the Order" from RC1's text, or test it with `layergit`'s section cut.

### F5 [medium] RC3 and RC4 run with no time bound, and RC4 opens the board in a browser on every run
Where: check.sh:18, :19; R0099.md:123 ("which fail (by the gate's bounded time)")
Evidence: `ac.sh`'s `check` runs `out=$("$@" 2>&1)` with no bound, and `./zn check` (`runCheck`, main.luau:3026) streams `bash check.sh` with none. RC3 and RC4 are not the gate, so the Risks line is false. If the history read stalls (F2), RC4 hangs `./zn check R0099` and `./zn done` for good, with a `git cat-file` child at 0 % CPU. `cmd.board` opens the page unless `-O` is given (main.luau:7415, `open` on macOS). So RC4 opens a browser window on the user's machine at every `./zn check R0099`, including headless dispatched runs. `grep -q provenanceOf engine/board.html` also passes when the function is defined but never called.
Critique: adding `-O` alone still leaves both checks unbounded.
Consequences: a bounded RC fails with exit 124 instead of hanging, which is the failure the Risks line wants. c0265's `check.sh` already uses `zn run --time`, so the pattern is accepted.
Recommendation:
- RC3: `"$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" who c0263 | grep -q idea`.
- RC4: `"$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" board -O --out "$ZN_ROOT/.cache/r0099-rc4/board.html"`, then grep that file for a `"provenance"` key in the board data, which proves a real item carries entries.
- Correct the Risks sentence to name these bounds.

### F6 [low] "None adds a top-level local" contradicts the prototypes the raft cites, and R0100's lead relies on it
Where: R0099.md:53; :68 (R0100 interface, "nothing here may add one"); E2
Evidence: compared with each prototype's merge base, `git diff` on `main.luau` adds `local mergerecords`, `local provenance` (proto-c0263-raft), `local function liveActor`, `local function recordRow` (proto-c0280) and `local lifecycle` (proto-c0282). E2 itself counts 202 against 199. Luau's limit of 200 is real for locals that hold registers: in my probe, 300 `local function`s fail at `f200`. Plain constant locals are folded and don't count (250 `local v = n` load), so the line count is not the measure.
Recommendation: replace the claim with the true additions per layer and the register headroom measured on the stack (add `local function` stubs until it fails). Give R0100's lead that number in the Interfaces paragraph instead of "nothing here may add one". RC3 stays the backstop.

### F7 [low] The stale-text note misstates the members, and the alias resolution needs a rule against editing members' design sections
Where: R0099.md:45; :43 (c0283 "rewrites the body of `hint` to loop over `AGENT_VARS`"); :102 ("c0284's text … becomes")
Evidence: c0263.md:113 already says c0283 adds "`AGENT_VARS` and `approved`, and the body of `hint` (it loops over `AGENT_VARS`…)". c0280.md:68 says the same. Neither names `approvalProblem`, `exemptParse` or `exemptRender` (grep finds none). Both, like c0283's Interfaces, say `hint` loops over `AGENT_VARS`, while the raft's resolution keeps the loop on `AGENT_MARKERS`. The two are the same table, so behaviour is the same. But a conscientious executor will "correct" the member texts, and Problem, Solution, Design and Acceptance criteria are hashed into each member's `approval.md` contract (`contract.luau:4`). Any such edit makes `./zn done` refuse the member.
Recommendation: correct line 45. Add one sentence to the Whole-raft design: executors never edit a member's Problem, Solution, Design, Acceptance criteria or Test plan; each raft-level resolution (the alias, F2's streaming) is recorded in the member's Verification log, which is outside the contract. If F3's option (a) is taken, the members' "loops over `AGENT_VARS`" becomes literally true.

### F8 [low] c0264 (R0092, active, PR #335) is a README writer of all five members' provenance text, and the raft doesn't name it
Where: R0099.md:66 to :78 (Interfaces), :63 (`zz-rules` and README)
Evidence: `origin/R0092/1/c0264:z-nile/README.md:143-151` adds a `### Provenance` sub-section with one sentence per member labelled `*designed* (c0263)` … `*designed* (c0284)`, plus Roadmap rows 176-185 marked `designed`. c0264's AC7 requires "every roadmap row and every issue-labelled sentence has the state the tracker shows". AC10 (`roadmap-unique`, promoted) allows one Roadmap row per id. R0099's members edit a different README bullet (`- **Provenance.**`), so no pinned fragment collides. But once R0099 is done, those labels are false. If R0099 lands first, c0264's AC7 goes red until its lead relabels (lesson z-raft/interface-names-every-writer, lesson z-raft/cross-raft-order-written-in-both).
Recommendation: add an Interfaces bullet for c0264 and R0092: whichever lands second updates the five labelled sentences and Roadmap rows to the tracker's state, and adds no second Roadmap row for any member. Ask R0092's lead to copy the bullet into R0092.

## Candidate lessons (for the lead to harvest)
- z-raft: a raft-level fix for a prototype failure keeps every member's acceptance criterion true as written at real scale, and states the cause it measured with the variables separated. Check: does the fix make any member's AC false on the real tree while its spec still passes on small fixtures? (F2)
- z-raft: a cross-raft wait is followed to that raft's own waits and to the first layer whose `check.sh` it turns red, not to `done`. Check: which layer's finish runs the red spec, and is every wait of the waited-on raft `prepared` or better today? (F3)
- z-design: a row a member writes in a PR has a path to main in every flow that writes it, including a prep PR merged before the human acts. Check: for each record row, which command publishes it when the PR has already merged? (F1)

Verdict: changes
