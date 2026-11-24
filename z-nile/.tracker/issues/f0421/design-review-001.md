# Review 001: f0421 (design mode)
Inputs: origin/f0421-alts d748f32d3, `z-nile/.tracker/issues/f0421/f0421.md` lines 317-596 (Design, slice 3) and 765-773 (Q-cat1 to Q-cat8); origin/main 5e8f5eaa4: `.models.toml`, `z-nile/engine/models.luau`, `modelcmd.luau`, `workcan.luau`, `workerlive.luau`, `reviewrec.luau`, `agentenv.luau`, `boundcmd.luau`, `approvewalk.luau`, `approval.luau`, `sessions.luau`, `adapters.luau`, `main.luau` (land), `z-nile/guard-bash.luau`, `zn`, `z-nile/tests/lib/fence.luau`, the model and work specs; the saved lists (agent 284 ids, agy 27, grok 4); `./zn capture f0421`; `./zn guesses f0421`.

Probes (read-only, each through `./zn run --time 60`):
- P1, the designed `identity` (C1) and `OFFERS` (C3) run over the 315 saved ids. All 15 seeded entries split correctly and exist on every CLI the prefixes give them to. Outside the seed the rule is wrong for: `gpt-5.5-extra-high` and `gpt-5.5-extra-high-fast` (family `gpt-5.5-extra`, so not the same model as `gpt-5.5-high`); `claude-4.6-opus-high-thinking`, `claude-4.6-opus-max-thinking`, `claude-4.5-opus-high-thinking`, `claude-4.6-sonnet-medium-thinking` (the effort is before `-thinking` and is not removed: each id is its own family); nine thinking and plain pairs that come out as different models (`claude-opus-5-thinking` and `claude-opus-5`, the same for `claude-fable-5`, `claude-sonnet-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-fable-5-1`, `claude-haiku-5-5`, `claude-4.5-sonnet`, `claude-4-sonnet`); `grok-4.7-build-fast`, grok's default model (family `grok-4.7-build`, an id grok does not list); `auto`, agent's default (no agent prefix matches it); `gemini-pro-orchestrator`, which agy shows as "Orchestrator (Carbon)" (the bare id is one of three variants, not their family). 21 agent ids and all 4 grok ids carry no effort. agy lists `claude-opus-5-5` and `claude-sonnet-5-5` at low, medium and high only; agent lists both at low to max. agent's own tip line reads `--model 'claude-opus-4-8[context=1m,effort=high,fast=false]'`: on agent, fast, effort and context are options of one model id.
- P2, origin/main's `models.parse` and `models.config` on the slice's forms: `[catalog]` gives `[catalog] is not read (the file has clis, activities, roles, fallback, dispatch and rounds; skill tables are gone)`; `heavy = ["a", "b"]` gives `clis.agy.heavy has no model`; `[clis.agy.substitute]` gives `clis.agy.substitute is not an alias or setting (...)`. Today agent's can-list is 12 heavy pairs with no final review, `needsSession` is false for agent, and `waiting` for the final review is `final-review/normal (ultra: claude)`.
- P3, today's engine with kimi's one model at xlight, light and heavy: it loads and delivers 21 pairs.

### F1 [high] S1 lets an agent (Cursor) session take the ultra reviews and the final review on a model it only declares, and the session can declare it itself
Where: R2 (lines 386-393), R3 (394), the agent table (484-492), S2 "Unchanged" (431), Risks (594)
Evidence: Today agent holds one model, ignores `ZN_MODEL` and cannot deliver ultra (P2). Under the seed `ZN_MODEL=claude-fable-5-2-high` answers `final-review yes` and `code-review risky yes` (line 488). `ZN_MODEL` is read from the command's own environment (`modelcmd.envNow`, `workerlive.canFor`), so `ZN_MODEL=claude-fable-5-2-high ./zn work next`, typed by the session, is accepted. The refusal a session meets first tells it to do that: `agent runs more than one model (...): set ZN_MODEL to the one this session runs` (modelcmd.luau:73). Without intent: the person exports the variable, later switches with agent's `/model <id>`, and the variable stays. agent's default model is `auto`, which has no id to declare. The registration and every row carry the declared id (R3), so the record shows the claim.
Critique: The design files this as "one limit" that "stays open". Before S1 the claim was worth at most heavy, on agy. S1 makes it worth the final review, which the owner's approval follows. It also empties S2: no session needs a consent line when a variable does the same. The tempting fix is one sentence in a skill.
Consequences: A rule about who sets the variable needs something the engine can check. The truth can be read today for claude and grok only (`sessions.luau:110` and `:170` read the model from their session files; Cursor's transcript carries none; agy has no reader). A final review that only checked sessions deliver changes what the owner's agent list is worth.
Recommendation: In S1. (1) The registration fixes the session's model: the daemon refuses a later call of the same worker with another `--model`. (2) Both refusals say "ask the person to start <cli> with ZN_MODEL=<an id `<cli> models` prints>", AGENTS.md and z-work say an agent never sets or changes `ZN_MODEL`, and `auto` gets its own line. (3) Where a session file names the model (claude, grok), `finish`, `spend` and `commit` refuse a row whose `--model` differs; one experiment asks whether agent's and agy's session files carry it. (4) The registration, every row and the approval lines mark a model that was declared and not read: `(declared)`. (5) escalate to the user: may a session whose model is only declared deliver the final review and the ultra reviews? Options: yes, marked `(declared)` at approval (the seed does this unmarked); only a session whose model the engine starts or reads (claude subagents, dispatch, grok); as today (claude only) until a reader exists for the CLI. Cases: a second registration with another model is refused; the mark on a row; the session-file mismatch; `auto`.
Erred: z-design
Upstream: none

### F2 [high] S1 changes the root file in the same slice as the parser: every engine older than S1 then refuses the file, and every running agent session is handed nothing
Where: Slices (524-530), Migration (510-522), the seed (468), Risks (593)
Evidence: P2. Each worktree runs its own engine and reads origin/main's file (slice 2's Rollout, line 310), so on the day S1's seed merges, `./zn model`, `./zn rounds`, `./zn dispatch` and a worktree's `work next` fail with `[catalog] is not read` in every worktree cut before S1. Slice 2 met this and split the parse (step 5) from the seed (step 8) with a loop that had to print nothing (line 313; the log at line 722 counted 207 of 245 branches behind). Slice 3 has no such step. The same happens on the day the owner writes the S2 consent line, for every engine older than S2. Separately the seed drops `[clis.agent] heavy`: agent then holds 15 models, and `workerlive.capability` (workerlive.luau:289-296) hands a session with no `ZN_MODEL` nothing. A running session cannot change its own environment, so it restarts, or prefixes the variable itself (F1).
Critique: "Each merges alone with the gate green" is true of the gate and says nothing of the other worktrees.
Consequences: A parse-only step must already accept the keys later slices use, or each later key repeats the wait.
Recommendation: S1a: the parser accepts every slice-3 key (`[catalog]`, the list forms, `offers`, `[clis.<cli>.substitute]`: read and checked, substitutes not acted on) and the root file is unchanged. S1b: the seed, merged only when slice 2's loop prints nothing for S1a's commit and `./zn work status` shows no agent worker, with the restart line for agent in the PR body and under `## Open to the human` (it changes how the owner starts agent). Case: S1a's parser loads the S1b seed text and a substitute line, and answers as before.
Lesson: z-design/new-rules-migrate-existing-work
Erred: z-design
Upstream: none

### F3 [high] C2 with C5 refuses what the owner ruled on 2026-11-20 and what the table accepts today: one model serving two levels on one CLI
Where: C2 (347), C5 "an entry the catalog places at another level" (369), Q-cat6 (771)
Evidence: The Problem, line 26, the owner: "running local qwen3.8 is suitable for xlight and light tasks". One model, two levels. Today that loads (P3). Under C2 the entry sits at one level, and under C5 a CLI's override may not list it at another, so `[clis.<cli>] xlight = ["qwen3.8"]` beside a catalog `light` entry is a load error. Q-cat6 hands this back to the owner as "not built".
Critique: The reason C5 gives is "a CLI cannot promote a model". That covers upward. Downward is a cost question, and the owner answered it for qwen.
Consequences: An entry keeps one catalog level (its strength) and may also be in a CLI's lower lists. "The level of this session's model" stays single, and a substitute is still measured from it.
Recommendation: C5 refuses only an override that lists an entry above its catalog level. Below is allowed, for that CLI and that kind. `alias=` stays the entry's catalog level. Q-cat6 shrinks to "with no line at all?". Rows: upward refused; downward loads and delivers (mutant: any other level refused).
Erred: z-design
Upstream: none

### F4 [high] A `review.ultra` consent reaches the final review, and AC35 passes when it does
Where: S2 keys (407-408), S2.F (423), the row "downward only, and never the final review" (563), AC35 (574)
Evidence: The consent has no activity key: it is `review = { ultra = "heavy" }`. The final review's setting is `ultra` (`[activities.final-review] all = "ultra"`), and "the review activities" in code are `REVIEW_ACTIVITY`, built from `models.PAIRS` (models.luau:93-96), which holds `final-review`. An implementation that applies the `review` consent wherever `REVIEW_ACTIVITY[act]` is true substitutes the final review. The one test named is the refusal of a `final-review` key (mutant "`final-review` accepted"), a key the grammar never had. That implementation passes it.
Critique: The rule lives at resolution and is tested at the parser.
Consequences: Every reader of capability must agree: `./zn model`, `--can`, the registration, `work next`'s filter, the dispatcher, and the light path, where the final review is the only review.
Recommendation: One rule in `resolveIn`: no substitute is applied when the activity is final-review. Cases with `[clis.agy.substitute] review = { ultra = "heavy" }` and `ZN_MODEL=gemini-4-argon-high`: `./zn model final-review` exits 1 with the waiting line; `--can` and the registration list hold `code-review/risky` and no `final-review/*`; `work next` hands no final review; a dispatched final review on a CLI with the consent ends undeliverable. Mutant: the consent applied through `REVIEW_ACTIVITY`. The question to the owner says that `review.ultra` also covers every idea challenge.
Erred: z-design
Upstream: none

### F5 [high] The merge guard does not make consent a person's act, and AC37 tests another module
Where: "Who answers" (b) (414), the recommendation (417), slice S2 (535), AC37 (576), Q-cat3 (768)
Evidence: (1) `boundcmd.luau` is the rule set of the Claude Code PreToolUse hook (`.claude/settings.json`; guard-bash.luau:2-9). agent, agy, grok and kimi run no hook (`.cursor/` is empty), and `agentenv.MARKERS` names no variable for agy. (2) The hook is pure over the command text and fails open. It cannot know which files a pull request changes, and it reads one shell line: `gh api -X PUT .../pulls/N/merge`, a `gh pr merge --auto` set earlier, a script, and `git push origin <sha>:refs/heads/main` all pass (main has no branch protection, zz-rules line 127; `./zn land` pushes that way itself). zz-rules line 183: none of these guards "is a security boundary". (3) `./zn land` already refuses every change that is not a backlog issue document (`captureScope`, main.luau:2713), so that half adds nothing. (4) AC37's check runs `wrapper-guards.spec.luau`, which tests `z-nile/bin/git` and `z-nile/bin/gh`, the dispatched step's shims, where the agent credential cannot merge anyway. (5) The guard stops every table change an agent merges (a catalog line, a new CLI, `[rounds]`); the last two changes to the root file (#766 and #785) were merged by the lead, on the owner's standing instruction to merge green pull requests.
Critique: The approval standard is the engine refusing the recording command under a marker and without a terminal on stdin (`approvewalk.refuseAgent`; `zn` lines 154-181). The stdin test is what catches a CLI that sets no marker. Form (b) uses none of it. The tempting fix is a hook that reads the diff: it stays a Claude-only seatbelt.
Consequences: A guard that reads the diff must name every edit that raises a model (F6), not only `substitute` keys. A terminal command needs a record on main, a rule for when it stops holding, and an answer for a copy of that record an agent writes by hand.
Recommendation: escalate to the user: Q-cat3, with each option told as what the owner does. (b) as designed: open a worktree, edit TOML, open a pull request and merge it by hand, for this and for every later table change. (c) a terminal command (`./zn model --consent <cli>`, the name is free) under `refuseAgent` and the launcher's stdin test, the one definition approve uses: it prints each gap with the entries that would stand in (the CLI's highest level below the gap), asks y/n once per gap, and publishes one record on main as an approval is published (CLI, kind, needed level, the stand-in entries, date; a "no" is recorded too). The engine reads it at origin/main. It stops holding when the stand-in entries or the gap change, and step 0 then names the command again. `--until <date>` and `--for <R-id>` are optional. The reviewer recommends (c): the design prices it at 150 lines, and the guard's lines go. Its record's path joins what `trackerstate` refuses outside the command. Cases: refused under each marker and under a pipe; a changed stand-in list stops it; a recorded "no" silences step 0.
Lesson: zz-arch/guards-decide-from-the-tools-resolution
Erred: zz-arch
Upstream: z-design

### F6 [high] Two table edits raise a model's level with no consent key
Where: C5 "An entry the catalog does not hold is allowed, at the override's level" (369), C4 "a closer file's level replaces that whole level" (362), S2 "nothing lets a session raise its own capability without the owner's line" (431)
Evidence: (1) `[clis.agy.review] ultra = ["claude-sonnet-5-5-low"]`. Sonnet at low is unplaced (line 461) and agy's prefix `claude-sonnet-` offers it, so C5 accepts it at ultra. Sonnet at medium is light. The same works with `gemini-3.8-flash-low` or any unplaced id. C5's own words for this are "a substitute nobody consented to". (2) A `.models.toml` in an issue's folder with `[catalog]` restating `heavy` and `ultra` moves any entry to ultra for that issue; the duplicate check passes.
Critique: Rank is decided in three places (the catalog, a closer catalog, an override-only entry). A guard on `substitute` lines guards one door of three, and a guard on the whole file is F5.
Consequences: Overrides limited to catalog entries mean every model a CLI runs is ranked once, in the catalog, which is Q-cat1's job anyway. A catalog a closer file cannot raise removes rank per project.
Recommendation: An override holds catalog entries only (an unplaced id is refused with "place it in [catalog] first"). A closer file's `[catalog]` may remove or reorder a level's entries and never adds to a level or moves an entry up; or `[catalog]` is read from the root file only. F5's consent is then the one way a model works above its catalog level. A row and a mutant for each.
Erred: z-design
Upstream: none

### F7 [high] S3c: "a refresh only narrows, so it cannot raise what a session delivers" is false
Where: S3c (536-541), AC38 (577), Q-cat4 (769)
Evidence: Two rules turn fewer offers into more capability. (1) R2: a CLI whose lists hold one model needs no `ZN_MODEL`, and its session is taken to run that model. A `.cache/models/agent.txt` listing only `claude-fable-5-2-xhigh` leaves agent one model, at ultra: every agent session, whatever it runs and with nothing declared, delivers the ultra reviews and the final review. (2) S2: a substitute exists only when the CLI has no entry at the level, so a list without that level's entries makes the gap an existing consent then fills. `.cache/` is where agents write every day, and the list is whatever a program named `agent` first on PATH prints. Not stated: whether an override entry the cached list lacks is a load error on that machine (C5 refuses "an entry the CLI does not offer").
Critique: Narrowing is monotone for "which entries" and not for "is the list empty" or "does it hold one".
Consequences: A list used for diagnosis only keeps its use (F9's over-claims) and loses its risk.
Recommendation: The cached list never feeds resolution: `--refresh` prints the differences (entries the table gives the CLI that its list lacks; ids it lists that the table does not place) and `--gaps` shows them. If it must narrow: the gap test and the several-models test read the table without the cache, a missing entry only leaves what a session delivers, a list with no id counts as failed, and nothing under `.cache` can be a load error. `.cache/models/` joins AGENTS.md's list of what `./zn` writes. The spec starts a stub on a fixture PATH, never a real CLI. With that, Q-cat4 is the design's to decide.
Erred: z-design
Upstream: none

### F8 [medium] `identity` and `spell` are wrong for ids the CLIs print, and AC31 cannot see it
Where: C1 (341-346), AC31 (570), Risks (595)
Evidence: P1. What follows from it: R1 would take "Opus 5 thinking" as another model to review Opus 5's text and record `same-model=no`. A session on agent's Haiku 5.5 with thinking (`claude-haiku-5-5-thinking-low`, which agent names "Claude Haiku 5.5 Low") is "not placed", while `claude-haiku-5-5-low` ("No Thinking") is taken as claude's Haiku at low. `spell(grok, "grok-4.7-build-fast")` starts `--model grok-4.7-build`. AC31 tests the ids someone picks.
Critique: Effort is the second axis for the 15 seeded entries. The lists show four: effort, fast, thinking and a variant word, spelled per family (`extra-high`, effort before `-thinking`).
Consequences: A rule that refuses what it cannot split needs a way to state the family by hand.
Recommendation: `identity` is defined over table entries and checked at load: an id whose remaining family still holds `fast`, `thinking`, `extra` or an effort word is refused, naming the rule, unless the entry states its family (`{ id = "gpt-5.5-extra-high", family = "gpt-5.5" }`). `-fast` is removed only for a CLI whose spelling has it as an option (agent, citing its tip line). `ZN_MODEL` matches an entry by its exact id or that id with `-fast`, never by a family computed from the variable. `spell` for claude and grok is the entry's stated model and effort. The three saved lists are committed as fixtures; AC31 runs `identity` over every id and pins the list of known edges.
Lesson: zz-test/measure-hand-written-readers-on-the-corpus
Erred: z-design
Upstream: none

### F9 [medium] `OFFERS` as engine prefixes is not "it will just work out of the box"
Where: C3 (348-361), C4 "an id no CLI offers" (362)
Evidence: The edits, counted. A new model in a known family: one catalog line, which under the seed reaches agent, and any other CLI only at a level where it has no override (claude has all four, and also needs R1's list of current versions). A new family (the owner's qwen, or one agent adds): the catalog line is refused as "an id no CLI offers" until an engine change adds the prefix, and after that by every older engine (F2's wait again). A new CLI: `CLIS`, `RUNTIMES`, `OFFERS`, its spelling kind, `SESSION_VARS`, `agentenv.MARKERS`, the usage strings, and an override of the promoted `c0117/models.spec.luau`, which pins `RUNTIMES`. Prefixes also over-claim (P1): a catalog line `claude-opus-5-5-xhigh` at ultra (Opus at xhigh is the design's own example of an ultra alternate, line 505) makes agy "have" ultra, which agy does not list. agy's risky reviews then wait for "agy running claude-opus-5-5-xhigh", and an existing `[clis.agy.substitute]` line names "a level the CLI does have": a load error for every CLI. A second `grok-` entry makes every grok session need `ZN_MODEL`.
Critique: The prefix list is the same claim as a table line, kept where a change needs code and a rollout.
Consequences: Offers kept as data need a seed, and nobody can check a line for claude or kimi, which list nothing.
Recommendation: `offers` is table data: `[clis.<cli>] offers = [...]`, ids or prefixes ending in `-`, seeded from the saved lists (ids for agy and grok; prefixes for agent, claude and kimi). The engine holds no family list. A catalog id no CLI offers loads, and `--gaps` names it. A consent for a gap that no longer exists is inert, and `--gaps` says so. The `.models.toml` comment says a catalog line does not reach a CLI's level that has an exclusive override.
Erred: z-design
Upstream: none

### F10 [medium] The owner's sentence against the seed, and placements made by inference that are not asked
Where: the seed (433-463), Q-cat1 (766), G-cat 6
Evidence: "sorting of all the available models": 15 entries are placed. Of the owner's nine agent models three are refused (`gemini-4-carbon-medium`, `gpt-5.6-sol-medium`, `muse-wonder-1.0-high`, line 492), and of agy's nine, five. "in a preference order": for a one-model session (agent, agy, grok, kimi) order does nothing, only membership counts (R2), and claude's tables are exclusive, so the order acts on `./zn dispatch --cli agent` and on the waiting line only. "override preference order for specific CLIs": built as exclusive membership (C5). Placed from a name: `cursor-grok-4.6-high` at xlight ("the version before grok 4.7"), against line 453 ("invents no ranking"). Placed by family: `claude-fable-5-2-high` at ultra, which lets a final review run one effort below today's xhigh; `claude-opus-5-5-medium` at heavy; `claude-sonnet-5-5-high` at light. Q-cat1 asks about the unplaced models only.
Critique: Each is marked G in the table, and none is a line the owner is asked to rule.
Consequences: none
Recommendation: Q-cat1 becomes the whole table: every entry not taken from today's file, with its reason and what it changes (Fable at high: final reviews at high effort on agent), and the owner's three unplaced agent models. One more question, which the default hides: is a session on an unplaced model refused (the design), or does it work at xlight with a notice? The design says where order acts.
Erred: z-design
Upstream: none

### F11 [medium] S1 welcomes the owner's agy Opus session only at high, and the refusal for any other effort is false
Where: R2 (392), agy's seed (469-479), Q-cat8 (773)
Evidence: agy lists Opus at low, medium and high. `ZN_MODEL=claude-opus-5-5-medium`: the catalog places it at heavy and agy offers it, but agy's exclusive `heavy` list leaves it out, so no list holds it and the line says `is not placed in [catalog] at any level agy has: ask the owner to place it`. It is placed. Four causes share that line: an id the CLI does not run, an unplaced effort, a placed entry an override leaves out, a placed entry the CLI does not offer.
Critique: The owner's session is the reason for the slice, and whether it works depends on an effort the design does not know.
Consequences: none
Recommendation: agy's `heavy` lists hold both catalog efforts of Opus and its `light` lists both of Sonnet, so Q-cat8 is not needed. One refusal per cause, each naming the file and the key that would change it, and one case each.
Lesson: z-design/refusals-name-a-way-out-that-works
Erred: z-design
Upstream: none

### F12 [medium] Consent as designed differs from the owner's sentence in five ways that are not asked
Where: S2 (397-424), `--gaps` (418-421), G-cat 9
Evidence: (1) "find the highest model it has": the line names any lower level, so `review = { ultra = "light" }` on agy, which has heavy, loads. (2) Distance: `ultra = "xlight"` on a CLI that has only xlight lets it review risky tickets and challenge ideas; guessed "any", not asked. (3) "okay with that as a substitute": the consent names a level, so an entry added to that level later is covered with no new yes. (4) There is no recorded "no": step 0 repeats the gap at every start. (5) Once consent is given `--gaps` prints nothing, and a headless worker substitutes with no notice and no end. Also: nothing says a writing key never enables a review (C6 falls back from the review list to the plain one, which invites it; no row); two gaps of one CLI print two `review = { ... }` lines, which pasted together are a repeated TOML key; "takes effect at the next read of origin/main" is at each worker's next fetch, and a dispatched run keeps its pinned table.
Critique: The owner asked to be shown a model and asked once. The line consents to a level, forever.
Consequences: A record that lists entries stops holding when they change, so the owner is asked again after a table edit.
Recommendation: With F5's record: the stand-in is computed (the CLI's highest level below the gap) and the record lists its entries; distance is a question to the owner (one level, or any); a "no" is recorded; `--gaps` also prints each substitute in force with its date; writing and review are separate records and resolution says so (row and mutant: a writing consent that enables a review).
Erred: z-design
Upstream: none

### F13 [medium] The substitute is not bound to the approval, and its note is undefined for the ids real rows carry
Where: "Recorded and shown" (425-430)
Evidence: An approval's contract is the document, `check.sh`, the acceptance specs and `guesses.md` (`approval.collect`, approval.luau:48-75). Spend rows are not in it. An approval given before the code review is not changed by a substituted review, and `done` lands it. `substituteNote(model, own, needed)` needs the level of the recorded model; the tracked rows carry `claude-opus-5-5` (74 rows), `claude-fable-5-2-medium` (64), `claude-fable-5-2` (53) and `claude-opus-5-5-xhigh` (34): no effort, or an unplaced one, so `own` has no value. A review below its level with no consent gets the same note as a consented one, or none. The note has four writers (`spend`, `commit`, a dispatched review, `idea`: reviewrec.luau:3-5) and one row ("the spend path"). The brief is read out by the walkthrough's model, not printed by the engine.
Critique: "So the owner approves knowing it" holds only when the approval comes after the review.
Consequences: A guess recorded after an approval makes it stop holding (zz-rules, the guess row), so a substituted review after an approval sends the ticket back to the owner once.
Recommendation: A substituted review records a guess on each issue it reviewed (`guesses.md` is in the contract; `./zn guesses` and the queue print it). `own` is defined for an exact entry, an unplaced effort of a placed family, an id with no effort, and an unknown family. A review below its level with no consent gets its own note, and `done` refuses it. One case per writer.
Lesson: z-design/results-land-on-every-path
Erred: z-design
Upstream: none

### F14 [medium] AC29 contradicts the pin, an existing pin of the real root file turns red, and the slice has no override line
Where: Migration (517-522), AC28 and AC29 (567-568), Regression guard (607-644)
Evidence: The pin holds `deliverers` and `waiting` for every activity and level. With the seed agent delivers xlight, light and ultra, so "claude, grok, kimi and agy answer as pinned" cannot hold for those lines. `z-nile/tests/tooling/models-review-table.spec.luau` already reads the real root file and pins it: lines 76-85 (agent's ten rows, `agent final-review - - -`), the case "claude, grok, agent and kimi resolve every activity at every level exactly as they did before" (line 321), and lines 303-307 (`code-review/normal (heavy: claude, agent, kimi, agy running gemini-4-argon-high)`, `code-review/risky (ultra: claude)`, `final-review/normal (ultra: claude)`). S1's seed turns each red, and the design does not name the spec. Not pinned at all: `./zn model`'s printed line (where `substitute-for=` goes, and whether it is absent or `-`), the session refusals (`model-cmd.spec.luau:314` and `:319`, `work-can.spec.luau:544`), the parser's key lists (`models-activities.spec.luau:265`, `rounds.spec.luau` AC3). `lune run z-nile/affected -- .models.toml` selects 18 promoted specs, and the Regression guard has no line for slice 3.
Critique: The proof of "no change" is a new spec on a copied fixture, beside an older one on the live file that the same slice breaks.
Consequences: none
Recommendation: AC29 pins the per-CLI resolution lines and lists by name the cross-CLI lines that change. A "Slice 3 overrides" block says `Overrides: none` after a suite run on a prototype of the seed, and names the tooling cases whose pinned words change, `models-review-table` first.
Lesson: z-design/confirm-overrides-with-a-suite-run
Erred: z-design
Upstream: none

### F15 [medium] Rules with no row, no `checked` column, no spec written, no experiment
Where: Rules and mutants (548-564), AC28 to AC38 (566-577), Unknowns & experiments (598-605)
Evidence: No row for: the catalog's stacking; the other refusals of C4 and C5; `offers` narrows; `-none` and `-minimal`; `spell`; `ZN_MODEL` matched by identity and effort (mutant: effort ignored, so Opus at low passes as the heavy entry); `ZN_MODEL` unset; the bare level; `subagent=-` for another version; rows carrying the declared entry on `spend`, `commit` and dispatch; "only when the CLI has no entry at the level"; writing against review consent; the final review at resolution (F4); `--gaps`; the guard; all of S3c. The table has no `checked` column and nothing was run. `check.sh` holds no check and no spec exists, so the builder writes each spec with its code. The slice lists no experiment. Unproven and free to try: agent accepts `--model claude-opus-5-5-high` as it does today's `claude-opus-5-5[effort=high]` (adapters.luau:516); whether agent's and agy's session files name the model; which variable an agy or agent session sets; that an older daemon drops `--model` at register.
Critique: Eleven criteria rest on specs their builder will write.
Consequences: none
Recommendation: `models-pin.spec.luau` and its expected text are written in the design's pull request (it is green on main today). The rows are added with a `checked` column. The free probes are run and recorded. E10, which needs a real session, stays out of every Checked criterion.
Lesson: z-design/spec-design-correspondence
Erred: zz-test
Upstream: z-design

### F16 [medium] R1's choice of reviewer depends on the folder the command runs in
Where: R1 (383)
Evidence: `./zn model` reads the writers through `reviewrec.spendWriters(item, phase, ".")`: the working tree's spend rows (modelcmd.luau:239). Build rows are on the layer until it lands, so from the main checkout, where z-work runs, there are none and R1 takes the level's first entry; in the layer's worktree it takes another. Today that difference is one printed field. With lists it is the model that reviews.
Critique: A preference that holds in one folder is not a rule.
Consequences: none
Recommendation: R1 reads the writers from the layer tip, as the note at line 762 says `work next` can; or the command exits 2 outside the worktree that holds the rows when the level's list has more than one family. Case: one raft asked from both places gives one answer. The design also says where R1's "list of current versions" is kept and who changes it.
Erred: z-design
Upstream: none

### F17 [medium] The Problem has no 2026-11-24 decision line, and the eleven guesses are not recorded
Where: Problem and Non-goals (19-34), G-cat (579-590)
Evidence: `./zn capture f0421`: Non-goal 1 is "No fallback to another CLI or another model when the configured one cannot be delivered". S2 is that, with consent. The owner's three statements are quoted inside the Design, not as `Decided with the user (2026-11-24)` lines in the Problem. `./zn guesses f0421` prints `f0421: 0 guesses, not approved`, so the approval walk shows none of G-cat 1 to 11.
Critique: The final review traces claims to the capture, and the capture says the opposite of S2.
Consequences: none
Recommendation: Three `Decided with the user (2026-11-24): "<their words>"` lines in the Problem. `./zn guess f0421 --step design` for each G-cat and for the choices F10 and F12 list.
Lesson: z-design/never-narrow-captured-scope
Erred: z-design
Upstream: none

### F18 [low] Smaller holes
Where: C4 and C5 (362-372), R2 (386-393), the tables (482-503), Slices (524-541)
Evidence: (1) Two spellings of one entry: the catalog's `{ id, context }` and an override's `{ model, effort?, context? }`. The design does not say how `{ model = "claude-opus-5-5", effort = "high" }` is compared with `claude-opus-5-5-high`, or that `{ model = "claude-opus-5-5-high", effort = "high" }` is refused. (2) Today's `[clis.<cli>] models = [...]` key is not mentioned beside `offers`. (3) A person who started agent with `--model 'claude-opus-5-5[effort=high,fast=true]'` has no listed id for `ZN_MODEL`. (4) The owner's split (Neon writes, Argon reviews) holds on agy and not on agent, where a Neon session reviews normal code (line 486). (5) S1 at "about 450 lines" holds the parser's two tables and ten refusals, resolution, `modelcmd`, the Go change and four specs.
Critique: Each is a question the builder would have to ask.
Consequences: none
Recommendation: State (1) to (3) in C4, C5 and R2. Put (4) to the owner in one line. Size S1 again after F2 splits it.
Erred: z-design
Upstream: none

Verdict: changes
