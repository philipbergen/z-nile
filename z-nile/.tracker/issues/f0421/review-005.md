# Review 005: f0421 (code mode)
Inputs: slice S1a, `git diff origin/main...origin/f0421-s1a` (origin/main 8be9b1075, origin/f0421-s1a d97a9d171, 36 files); `z-nile/.tracker/issues/f0421/f0421.md` "Design, slice 3" with `design-review-001.md`, `design-refute-001.md`, `guesses.md` and `check.sh` on that branch. Not run, as the brief asked: the gate and `./zn check f0421`. Run instead, each through `./zn run --time` on copies in the reviewer's scratch folder (`git archive` of both commits): the pin's lines on main's engine and on S1a's, parser probes, `go test ./internal/live` with two added probe tests, eight mutants of `models.luau` against the catalog and identity specs with a mini runner, and `stylua --check` and `selene` on the changed Luau files (both clean).

What holds, checked: the root `.models.toml` is not in the diff, and the frozen copy `root-5e8f5eaa4.models.toml` is byte for byte `origin/main:.models.toml` at 8be9b1075. main's engine gives exactly the 1399 lines of `models-pin.expected.txt`, and so does S1a's. S1a's engine reads the seed fixture and differs from the root's answers only by agent's loss of its heavy table (fewer, never more). `workcan.luau`, `work.luau`, `dispatcher.luau` and `modelstep.luau` are not in the diff, and `modelcmd.luau` changes only `sessionModel`'s texts and adds `declaredNote`, so `./zn model`'s line and exit codes, `work next`'s filter and the dispatcher's resolution are unchanged by construction. `identity` over the 315 listed ids: no pair that was one model before is two now (0 of 49,455 pairs), and 608 pairs become one model (`-fast`, `-none`, `-minimal`). No spend row on main carries such an id, so no recorded same-model answer changes today. The AGENTS.md and skill edits are text. `main.luau` gains no top-level local, and there is no new require cycle. No spec in the diff writes outside a `.cache` fixture.

### F1 [high] A registration that names no model is refused once a model is recorded, so an engine older than S1a silently takes an agy session out of the live layer
Where: `z-nile/go/internal/live/ops.go:320-325`; `z-nile/go/internal/live/live_test.go:915` (the test pins the refusal of `""`); `origin/main:z-nile/engine/workerlive.luau:382-385` (what an older engine does with it); `z-nile/engine/workerlive.luau:236-239` and `500-503`.
Evidence: probe test on the branch's daemon. An agy worker registers with `--model "gemini-4-neon-medium (declared)"` (S1a's engine), then the same process registers with no model (any engine from before S1a, which never sends one): `map[ok:false refused:model ... why:worker agy-201@h registered running gemini-4-neon-medium (declared), and a session's model is fixed when it registers: ask the person to start a new terminal on the other model]`. The older engine reads any non-zero code as a dead layer: `liveemit.markGone(); return nil`. `join()` is then nil and `workerlive.decide` returns `workLib.decide(input)` with no claims read and none taken, and prints nothing about it. The daemon is built from the main checkout's Go (`zn:58-79`) and every worktree runs its own engine, so this is the state the day after the merge: an agy session asks `./zn work next` from the main checkout (registered with its model), then from a layer worktree cut before S1a (refused, unclaimed, silent). The same refusal reaches S1a's own engine when `layersAtMain()` cannot read the table (`canFor` returns no session, so no `--model` is sent): the person is told to start a new terminal on "the other model" when there is none. The same text also refuses `"gemini-4-neon-medium"` after `"gemini-4-neon-medium (declared)"`, because the mark is part of the compared string.
Critique: E16 looked only at a new engine with an old daemon (safe: the old daemon drops `--model`; confirmed). The other direction was not walked. Sessions of claude, grok, kimi and agent send no model today, so nothing changes for them. agy is the one CLI whose table needs a session model, so it is the one that breaks. The tempting fix is to make S1a's engine handle the refusal, which it already does: that cannot help, because the engine that is refused is the old one.
Consequences: treating "no model" as "no change" means a call cannot clear a recorded model, which is what the rule wants. It also means the mark must leave the compared value: the day a reader exists for agent (`SESSION_READ` gains it) an engine sends the bare id and the other engines send it marked, and each locks the other out. A worker whose model was recorded keeps it when an older engine re-registers with a changed `--can` list, so the `registered` event must carry the kept model.
Recommendation: in `register`, refuse only when both the recorded and the sent model are non-empty and differ; a call with no model keeps `old.Model` (the idempotence test and the emitted event use the kept value). Record the mark apart from the id (a `declared` field on `Worker` and on the event), or compare the ids with the mark removed. Go cases: none after a model is accepted and the model is kept; another model is refused; the marked and the bare spelling of one id are one model; a changed `--can` with no model keeps the model on the event. State in the design what an engine from before S1a sends and gets.
Lesson: z-design/shared-file-older-engines-write
Erred: z-design
Upstream: zz-review

### F2 [medium] The fixed registration binds no answer: after the refusal `work next` still answers for the model the variable now names, and without claims
Where: `z-nile/engine/workerlive.luau:401-405` and `493-503`; `z-nile/engine/modelcmd.luau:228`.
Evidence: by reading. `workerlive.decide` takes `input.capable` from `workerlive.capability(env)`, which reads `ZN_MODEL` from the command's environment, before `join()`. When the daemon refuses the registration, `register()` prints the line and returns nil, `join()` is nil, and the function returns `workLib.decide(input)`: the answer is filtered by the model the variable names now, and no claim of another worker is read. `./zn model` never asks the daemon. So `ZN_MODEL=gemini-4-argon-high ./zn work next` in a session registered on Neon prints one stderr line and then hands out Argon's review work, unclaimed.
Critique: the design's R2 says the registration fixes the model; as built it records the first model and refuses the record of a second, and nothing that hands out work reads the record. The agent that sets the variable is the case the rule exists for, and it ends up better off than before in one respect: it now works outside the claims.
Consequences: binding the answer to the record needs the registered model to win over the variable, so the commands need the daemon's answer before they filter. With the layer off (`ZN_LIVE=off`, no binary) there is no record, so the rule can only be "the record wins when there is one", and the docs line stays the only rule otherwise.
Recommendation: when the register reply is `refused: model`, `work next` answers `none` with the daemon's line as its reason (no decision is made), and `./zn model` and `--can` are left as checks of the variable. A case in `work-can.spec.luau` runs `workerlive.decide` with a stubbed register refusal and expects no unit; no case reaches that branch today. If the owner wants `./zn model` bound too, that is a design decision for question 3.
Erred: z-design
Upstream: zz-review

### F3 [medium] A stated `family` becomes the entry's key and nothing checks it: a list entry borrows any placed entry's level, and real ids collide
Where: `z-nile/engine/models.luau:271-274` (`entryKey`), `403` (the stated family skips every check), `1477-1489` (placement by key).
Evidence: probes on S1a's engine with the seed fixture as the root.
- A closer file `[clis.claude] ultra = [{ id = "claude-haiku-5-5-xhigh", family = "claude-fable-5-2" }]` loads, and `final-review` on claude resolves to `claude-haiku-5-5-xhigh`. The same line in the root file loads too. Without `family` the same raise is refused (`... which [catalog] places at xlight ... never higher`).
- The design's own example beside its plain sibling, `heavy = ["gpt-5.5-high", { id = "gpt-5.5-extra-high", family = "gpt-5.5" }]`, is refused: `catalog places gpt-5.5-high at heavy and at heavy: an entry has one level`. Both ids are in `agent-models.txt`. The line names the wrong id and one level twice. `claude-4.6-opus-high-thinking` and `claude-4.6-opus-max-thinking` with one stated family are refused the same way.
- An entry placed with a stated family cannot be named by the single form: `heavy = { model = "gpt-5.5-extra-high" }` gives `... is not placed: place it in [catalog] first`, and it is placed.
- Mutant: `entryKey` ignoring the stated family passes all 14 cases of `models-catalog` and `models-identity`.
Critique: G4's reason is "otherwise a closer file or an unplaced id raises a model's level with no consent". The stated family is that raise, with one key. It acts on nothing in today's root (no catalog). It matters because S1a's is the parser every worktree runs when the seed lands. A second way is older and the design keeps it: a closer `[activities.final-review] all = "xlight"` loads on the seed and gives the final review to haiku.
Consequences: if a list entry is matched to the catalog by its id, a list no longer needs `family` at all, and the catalog (root only) is the one place a family is stated. The key then needs the effort of the id as spelled, so two ids of one family and one effort word (`gpt-5.5-high`, `gpt-5.5-extra-high`) stay two entries.
Recommendation: key a catalog entry by its lower-cased id with `-fast` removed, and keep `family` as data for `sameModel` only. A CLI's list entry takes no `family`: it is looked up by id (and on agent by the id without `-fast`). Cases: the closer-file raise above is refused; the two `gpt-5.5` entries and the two thinking entries load together; the single form names a family-stated entry; a repeated id in one level is refused. Put the `[activities]` re-pointing by a closer file to the owner as an open question, since the design says that key is unchanged.
Lesson: z-design/refusals-name-a-way-out-that-works
Erred: z-design
Upstream: zz-review

### F4 [medium] The `(declared)` mark is on a row only when `--model` equals `ZN_MODEL`, so naming any other id leaves the row unmarked, and the spec pins that
Where: `z-nile/engine/modelcmd.luau:133-143`; `z-nile/engine/main.luau:4997-5001` and `7702-7708`; `z-nile/tests/tooling/review-record.spec.luau:179-181`.
Evidence: `declaredNote` returns nil when the row's model differs from the variable, when the variable is unset for that one command, and when `ZN_CLI` names claude or grok. The new case expects it: a commit on `gemini-4-neon-high` in a session declared `gemini-4-argon-high` is recorded, not refused and not marked. Sessions of agent and kimi set no `ZN_MODEL` (one model each), so none of their rows is ever marked, though the engine starts and reads neither. No spec sets `ZN_MODEL` with `./zn spend`: the block at `main.luau:7702-7708`, with its `modelRead` rule, can be deleted and every case passes. `registerArgs`' unmarked branch for a CLI in `SESSION_READ` has no case either.
Critique: the design says a model the engine neither starts nor reads is marked in every spend and commit row. As built the mark says "this row agrees with the variable", which is the one thing an agent controls on both sides. A reader of the rows cannot tell a declared model from a read one by the absence of the mark.
Consequences: marking by CLI (every row of a CLI outside `SESSION_READ` whose model no session file named) marks every agent, kimi and agy row from the merge on, in the commit subject too. A row whose `--model` differs from the session's declared model then needs its own rule: refused, or marked as differing.
Recommendation: mark by what the engine knows: the row's model was not read from a session file and the CLI is not in `SESSION_READ`. Decide the differing row with the owner under question 3 (refuse is the design's rule for claude and grok). Cases: `./zn spend` on an agy session marks its row; an agent session with no `ZN_MODEL` marks its row; a claude row is never marked; the differing row does what the ruling says.
Erred: zz-execute
Upstream: z-design

### F5 [medium] `offers` is acted on in S1a: stated, it replaces the CLI's id rule, and three places disagree about it
Where: `z-nile/engine/models.luau:316-320`, `456-479`, `516`, `1469-1475`; `z-nile/tests/tooling/models-catalog.spec.luau:311-317`; `z-nile/skills/zz-rules/SKILL.md:186`.
Evidence: the spec expects `[clis.agy] offers = ["gemini-", "claude-opus-5-5-high"]` with `heavy = ["claude-opus-5-5-high"]` to load and `code/risky` on agy to resolve to the Claude id. The design says `MODEL_OF_CLI` stays until S1b because "removing it would let agy load Claude ids, which belongs to the seed", and that S1a acts on none of the new keys. The zz-rules sentence says both "does not yet act on" and "when stated it replaces the CLI's id rule". Probes on the seed fixture: a closer file's `[clis.agy] heavy = { model = "claude-opus-5-5-high" }` is refused with `not a model of cli agy`, and the same id as a list, `heavy = ["claude-opus-5-5-high"]`, loads (the single form is checked per file by the old rule, the list form at the merge by the offers). `models = ["claude-opus-5-5-high"]` on agy is refused by the old rule though the offers hold it. A closer `offers` replaces the root's whole list, and the refusal then names a key the closer file does not have (`x/.models.toml: clis.kimi.heavy names kimi-code-k3.1-pro, which clis.kimi.offers does not hold`).
Critique: it raises no level (a closer file could already give any CLI any alias), and the unchanged root states no offers, so nothing changes today. It is a deviation recorded only as half a line of the verification log, and the single-form refusal is wrong for the seed S1b plans.
Consequences: checking every form at the merge only means a file is no longer refused by itself for a model id its own CLI table could not hold; the message must then name the file that set the level, not the last file that touched the CLI.
Recommendation: either keep S1a to its claim (read and check `offers`, and keep `MODEL_OF_CLI` as the rule until S1b), or record the deviation in the design with its reason and make it one rule: with offers on the merged walk, every form of every level and the `models` key are checked against them at the merge, and the error names the file that set the key. Cases: the closer single form above loads; `models` with offers; the closer `offers` message.
Erred: zz-execute
Upstream: z-design

### F6 [medium] An id-string list entry is not "today's single form" on claude and grok: the effort is lost
Where: `z-nile/engine/models.luau:345-349` and `1306-1310`; Design, slice 3, "Migration and rollout".
Evidence: probe. With `[clis.claude] heavy = ["claude-opus-5-5-high", "claude-opus-5-5-medium"]`, `resolveActivity(claude, code, risky)` on S1a's engine gives `model=claude-opus-5-5-high effort=nil`. `./zn model` would print `model=claude-opus-5-5-high effort=- subagent=opus`, and a dispatched step would start `claude --model claude-opus-5-5-high` with no effort flag.
Critique: the slice's safety line for S1b is "an S1a engine reads the seed's lists as first entries ... fewer models, never more". That holds for the seed fixture only because claude and grok keep their single forms there. Question 7 asks the owner whether to drop them. `spell` is S1b's, and S1a is the engine every worktree runs under the seed.
Consequences: splitting the effort off at load changes what a list entry's `model` is for claude and grok, so the duplicate key, the offers check and `modelsOf` must all read the entry's id, not its model.
Recommendation: in S1a, a list entry on a CLI that takes the effort as a flag (claude, grok) is stored as model and effort, the same Setting the single form gives, with a case that the list form and the single form resolve to equal specs. Or refuse an effort-carrying id string on those two CLIs in S1a and say so in the rollout text.
Erred: z-design
Upstream: zz-review

### F7 [medium] Mutants no case kills, and AC31's check line proves two of its four clauses
Where: `z-nile/tests/tooling/models-catalog.spec.luau`; `z-nile/.tracker/issues/f0421/check.sh` (AC31).
Evidence: each mutant applied to a scratch copy of `models.luau`; `models-catalog` and `models-identity` stayed at 14 passed, 0 failed.
- Review lists not checked against the catalog (`if cfg.catalog ~= nil and kind == "" then`).
- Review lists not checked against the offers at the merge.
- An exact `offers` id read as a prefix (`"kimi-k3"` would then offer `kimi-k3-high`).
- A repeated entry allowed inside one catalog level (only across levels refused).
- A catalog entry's `context` unchecked.
- `entryKey` ignoring the stated family (F3).
Two that were killed, for the record: the id rule dropped at the merge, and `-fast` allowed in the catalog. `workerlive.luau:401-405` (the refusal read by the engine) has no case. AC31 says the registration "carries, fixes and marks the model, and the refusals name the person"; its line runs `work-can.spec.luau` only, and "fixes" is proven by a Go test the line does not run.
Critique: the review lists are where a level matters most (agy reviews on Argon), and they are checked only by the same loop as the plain lists, with no case of their own.
Consequences: none beyond the cases.
Recommendation: one refusal case each for a review list (unplaced, above its level, not offered), an exact id that is not a prefix, a repeat inside one level, a catalog `context` out of range; a case that every id of the three listing fixtures except `auto` is held by the seed's offers. The check line for "fixes" is the lead's to escalate (F9).
Lesson: z-design/spec-design-correspondence
Erred: zz-test
Upstream: z-design

### F8 [medium] AC28 is proven for a frozen copy that nothing ties to the real root file, and the pin sees library calls only
Where: `z-nile/tests/tooling/models-pin.spec.luau:24`; `z-nile/tests/lib/modelspin.luau:15`; `z-nile/tests/tooling/models-pin.watch.txt`.
Evidence: the spec parses `root-5e8f5eaa4.models.toml`. No spec compares that file with `.models.toml`, and the watch file does not name `.models.toml`. Today they are equal (`git show origin/main:.models.toml | diff - <fixture>` prints nothing), so the claim holds at this commit. A change of the root file that lands before this branch does would leave the pin green. The pin calls `models.*` only. Its two authors (`claude-opus-5-5-high`, `gemini-4-neon-medium`) carry no `-fast`, `-none` or `-minimal`, so the one deliberate change, `sameModel`, is invisible to it: it is covered by `models-identity :: sameModel` alone.
Critique: the criterion says "today's root table". The check proves "the table of 5e8f5eaa4".
Consequences: a tie must stop holding the day S1b changes the root, by a rule and not by deleting the case.
Recommendation: one case: while the real root file has no `[catalog]`, its lines through `modelspin.lines` equal the expected file (the case names S1b as the change that retires it), with `.models.toml` in the watch file. Add a `-fast` author to `CROSS` in a second expected file, or say in the spec's header that same-model answers are outside the pin.
Erred: z-design
Upstream: zz-review

### F9 [high] The build edits the sequestered `check.sh`, and the specs behind AC29 to AC31 were written by the builder
Where: `z-nile/.tracker/issues/f0421/check.sh` (+5 lines, commit d97a9d171); Design, slice 3, "Acceptance criteria (slice 3)".
Evidence: `git diff --find-renames=100% --name-status origin/main...origin/f0421-s1a -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` prints `M z-nile/.tracker/issues/f0421/check.sh`. The file's own header says "SEQUESTERED: never edit during execution". The change only adds four `check` lines; on main the file has none for AC1 to AC27. The design told the builder to do it ("the slice that creates a spec adds its `check` line"). `models-pin.spec.luau` was written with the design (0f579502b); the specs of AC29, AC30 and AC31 were written in the build (21fe831fd) and live in `tests/tooling/`, not in the issue's `acceptance/`.
Critique: this is the rule's letter, and the cause is the design, not the builder. What the rule protects is real here: F7's surviving mutants are in specs the builder wrote for its own code.
Consequences: a ruling that lets a slice add its own check lines needs a rule for who reviews them before the code is written.
Recommendation: escalate to the user: either the slice's check lines and acceptance specs are written and reviewed in the design step (S1b's, S2's and S3c's before their builds), or the owner rules that a ticket built in slices adds its check lines in the build and a reviewer checks each added line against its criterion. Nothing in the code changes for this finding.
Erred: z-design
Upstream: zz-review

### F10 [medium] The design this slice builds has one review, verdict changes, and by the engine's own rule it is not answered
Where: `z-nile/.tracker/issues/f0421/design-review-001.md` (7 high, 10 medium, 1 low, `Verdict: changes`); `design-refute-001.md`; no `design-review-002.md`.
Evidence: in the worktree on `f0421-s1a`, `./zn rounds f0421 --kind design` prints `f0421 design: answer design-review-001.md in design-refute-001.md (every finding gets a line)`. The answers say `fixed` with no `; consequences:` on their line, which `openlist.unresponded` requires. The ticket is `risk: risky`, `design: draft`. A serious round answered below the maximum files the next round; none was run.
Critique: F1, F2, F3 and F6 above are holes in the answers to that review's F1, F6, F8 and F2. A second round reads exactly those answers.
Consequences: none for the code.
Recommendation: put the answers in the form the engine reads and run design review round 2 on the revised slice before S1b is built; its findings on S1a's rules come back as fixes to S1a's engine before the seed lands.
Erred: z-design
Upstream: none

### F11 [low] Smaller points
Where: as named in each line.
Evidence:
- `z-nile/engine/modelcmd.luau:88-90`: `ZN_MODEL <id> is not a model of agy (...)` ends with "ask the person to start agy with ZN_MODEL set to the id `agy models` prints for the model it runs". `agy models` prints 27 ids and the table holds 5, so for 22 of them following the line gives the same line again.
- `z-nile/tests/fixtures/models/seed-s1b.models.toml:142`: agent's offers hold `"kimi-k3"`, an id agent does not list, with no trailing `-`. Probe: of agent's 284 listed ids the seed's offers hold all but `auto`, `kimi-k3-low`, `kimi-k3-high` and `kimi-k3-max`, and a list naming `kimi-k3-high` is refused.
- `z-nile/engine/modelconsent.luau:99-107`: `latest` is the last row in file order; `when` is not compared and need not rise. `needed = xlight` loads though no level is below it. Any malformed row refuses the whole file, which is the closed side.
- `[catalog] ultra = ["auto"]` loads; `sessionModel` refuses `ZN_MODEL=auto` before it looks at the table.
- `z-nile/tests/tooling/work-can.watch.txt` does not name `.models.toml`, and the new case is the third in that spec to read the real root file.
- No engine reader shows a worker's registered model (`liveview.luau` does not read it): only the daemon's own `workers` reply carries it.
- The second case of `models-pin.spec.luau` reads only the expected file: it passes with the engine deleted.
Critique: the first is the refusal a person will meet most.
Consequences: none.
Recommendation: the "is not a model of" line names the table's ids as the way out ("start agy on one of ..., or place the model in `.models.toml`") until S1b's four causes replace it; `"kimi-k3-"` in the seed; the rest as S1b and S2 reach them.
Lesson: z-design/refusals-name-a-way-out-that-works
Erred: zz-execute
Upstream: z-design

## Judged criteria (code mode only)
None: the issue lists no Judged criterion.

## Safe to merge to main today, with sessions of five CLIs running?
- claude, grok, kimi and agent sessions: yes. The table is untouched, every engine answer for it is reproduced line for line, these sessions send no model when they register, and the reworded refusals are ones they never meet.
- agy sessions: not as it stands (F1). Once the daemon is rebuilt from main (any `./zn live <op>` or `./zn app`), an agy session that has asked `work next` through main's engine is refused, silently, by every `work next` it runs from a worktree whose engine predates S1a, and works there outside the claims. The fix is a few lines of Go and their cases.
- F3, F5 and F6 change nothing today. They are in the parser that every worktree will run when the seed lands, so they are fixed in S1a's engine or S1b's rollout loop must name the commit that fixes them.

Candidate lessons (a subagent reports them, the lead files them):
- z-design: when a daemon starts enforcing a field, what does a client from before the field send, and is "absent" read as "unchanged" rather than as a change? Check: one case registers with the field, then without it.
- zz-test: a pin of a frozen copy of a live file needs a case that ties the copy to the live file for as long as the two are meant to be equal. Check: change the live file by one value; does a spec go red?
- z-design: a key an entry states about itself (`family`) must not be the key a rank check trusts. Check: can a file the rule distrusts state it?

Verdict: changes
