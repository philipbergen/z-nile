# Review 004: c0117 (design mode)
Inputs: `prep-c0117` at 9a301bd (`z-nile/.tracker/issues/c0117/{c0117.md,check.sh,harvest.md,acceptance/*}`, `design-review-003.md`, `design-refute-003.md`, the three new lessons and the amended `merge-gate-checks-what-it-merges`); prototype `.worktree/proto-c0117` at f54387c on b57df84, read only; `./zn capture c0117` (fb7fd80, no marker); `./zn lessons --when design --full` and `--skill review --full`. Every attack ran in scratch clones of the prototype under the session scratchpad (`c0117-review004/clone`, `c0117-review004/mut`), origin pointed at a path that doesn't exist, through `lune run tests/run` (the jail), in `.cache/c0117-attack4*` fixtures. Round 3's four attack specs were ported (the fake CLI's `script` mode, which the prototype now has, given `id`; the gh-`files` cases P1 and P2 dropped, since `prFiles` is gone), plus one new spec (`conc`, below) and one mutant. No real CLI, no network, no real origin, no branch, worktree or commit in the real repository.
Dropped from review-003: F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11. Each holds against round 3's own reproduction (below), within the user's "Keep same user, accept detection".

The bar this round: under "Keep same user, accept detection", a hostile agent rewriting files it can reach is a documented limit. The findings below are ordinary use that breaks, a guard with no case, and an unproven assumption on the main path.

Scope (item 11): the capture is confirmed. The new `Decided with the user (2026-10-21)` block ("Keep same user, accept detection") is dated. The watermark decision's wording now reads "kept where a well-behaved step never writes, and detected if it changes", with the old wording quoted; that is the user's later decision, recorded. The Problem is unchanged. Every captured outcome still has a Design and a criterion. F2 bears on "The dispatcher chains the steps … up to the pull request": that outcome is criterioned only with fakes that answer at once.

Guesses:
- **G16** (`max_minutes = 240`) is reasonable as a backstop. `agent` is last in the root `order`, and `max_calls = 200` binds first on any stream that counts. The ceiling is wall time, so it also runs while a cursor author waits on its own nested reviews. That is acceptable for a ceiling, and a kill is reported as "passed max_minutes". Ledger data for scale: summed execution minutes for R0012 and R0031 are 470 and 383, so the biggest items will meet it if `agent` ever runs them. Keep it a guess the user tunes.
- **G20** as rewritten is reasonable under the decision. `prMergedFrom` checks `base.ref == "main"`, `merged_at` and `merge_commit_sha`, and fails closed on bad JSON. The decision's known limit (a merge made with the user's credential passes) is stated plainly. One cost the text doesn't name: a rebase-merged PR's earlier commits are not its `merge_commit_sha`, so each stops the chain until `vet` (fail closed). One sentence is enough, or a ruleset that allows squash merges only.
- **G21** is reasonable, as round 3 said. E10 is still the proof. §8 step 4 and E10 disagree about the shared-account case (F5).

Round 3 rechecked (its specs against f54387c):
- **S** (decoy move): refused ("tracker/issues/done/c0091/check.sh is sequestered: … never change it"); origin unchanged.
- **GA** (`tracker/.GITATTRIBUTES`): refused (configuration).
- **W1** (code pushed past the wrapper, watermark deleted): exit 5, "the watermark changed under this run (… the file says nothing)".
- **W2** (watermark rewritten to the new main): exit 5, the same message.
- **MT** (an item's `.models.toml` through the broker): refused ("not tracker state (configuration …)").
- **V** (`vet --dry-run` over a code commit): prints "NOT VETTED, you accept it: …" and "dry run: nothing written"; the next run exits 5.
- **B** (code, then its revert): refused per commit ("7b241c4…: c.lua is not tracker state"); `main` unchanged.
- **R** (origin repointed at a frozen copy): exit 5, "origin's configuration changed during the step".
- **P3** (500 bare tool calls): `calls 500`, `unknown "3 turns with no model_call_id"`, so the step stops as `cap-unknown`.
- Round 2's spec (A to F plus the control case): all refused or caught, as in round 3.

### F1 [high] Two dispatchers on two items, the "one dispatcher per item" model, trip each other: the run's in-memory watermark is compared for equality with a file every other dispatcher legitimately advances
Where: `dispatcher.vetMain` (`if guard.mark and mark ~= guard.mark then return "the watermark changed under this run …"`); `writeWatermark` (every top-level run's `guardStart`, `tripwire` and per-step vet advance the shared `main-seen` to its fresh `main`); §5 "What the dispatcher pins" ("A file that differs from what this run last read or wrote trips the wire"); §5 "One dispatcher per item"; G18 ("other terminals publish all the time"); the new lesson `guard-state-out-of-reach-or-checked` ("compare the shared copy with it").
Evidence (new spec `conc`, scratch clone, fake CLIs, through the jail):
- Dispatcher B runs `./zn dispatch z-design c0101`. Its step stands in for a long real step.
- While B's step runs, the user's other terminal (a clean environment: no `ZN_*` of the step, the user's PATH) does two ordinary things:
  - it publishes one tracker-only commit (`tracker/issues/c0103/note.md`) from its own clone;
  - it runs `./zn dispatch z-design c0102` (A), whose step does nothing. A exits 0, and its `guardStart` vets the new `main` and writes it to `main-seen`.
- B's step then ends. B's tripwire says `dispatch: TRIPWIRE: the watermark changed under this run (it was 933bfc4…, the file says 0238728…)`. B exits 5, and c0101's state is `tripwire`, so every later run on c0101 stops until `retry`.
- No other terminal is needed in real use. Each z-design step claims its issue (`./zn status preparing`) through its own broker, so `main` moves and that dispatcher's tripwire writes the file. Any two dispatchers running at once trip each other. So does a user's `./zn dispatch vet` while a run is live.
- A related race (reasoned): two dispatchers that vet at nearly the same time can write `main-seen` out of order. One writes `W3`, then the other writes the older `W2` it fetched first. The first dispatcher's item mirror then says `W3`, and its next run stops with "the watermark went back since this item's last run".

Critique: round 3's fix closed W1 and W2 by treating the file as the guard's record and any difference from it as tampering. But the file has many honest writers: every top-level dispatcher and `vet`. The tempting fix is to also accept a file that is a descendant of the run's copy. That reopens W2: a step that writes the new `main` into the file, over its own code push, is a descendant.
Consequences: the in-run detection has to come from what is vetted, not from who wrote the file. Vetting from the in-memory mark finds the step's code whatever the file says. The file is then only the starting point for the next run, so writes must only move it forward, and two writers must not race. Each dispatcher's next vet re-checks commits another dispatcher already vetted: one more `diff-tree` and two `ls-tree` per commit, while two runs overlap.
Recommendation: question the mechanism: compare by content, not by equality of the file.
- **Vetting.** Within a run, `vetMain` vets from `guard.mark` (in memory) to fresh `main`, whatever the file says. W1 and W2 are still caught, because the step's code commit is in that range. The file is read only when the run has no mark yet: `guardStart`, which keeps its no-file and went-back checks.
- **Writing.** The file moves only forward. Under an flock on the watermark folder, write `fresh` only when the file's current value is an ancestor of it. A file that is missing mid-run is rewritten, and the run notes it on stderr. A file that is not an ancestor and not a descendant (diverged) trips the wire.
- **Docs.** §5, zz-rules and the README say the file is shared by every dispatcher of the repository.
- **The lesson.** Amend `guard-state-out-of-reach-or-checked`: when other legitimate processes write the record, compare what it guards (re-vet from your own copy), never the record's equality.
- **Cases (control-cli):**
  - case C above exits 0 for both A and B (mutant: equality compare);
  - W1 and W2 still exit 5 (mutant: vet from the file);
  - a write of an older `main` over a newer file leaves the file as it was (mutant: unconditional write).
- **Rows:** add these to Rules and mutants; G18 names concurrent dispatchers.
Lesson: architecture/guard-state-out-of-reach-or-checked, architecture/lock-reads-live-state

### F2 [high] A headless author starts its review as one shell command (`./zn dispatch zz-review`), which outlives both the CLI's own command timeout and the runner's 900 s tool limit, and no experiment or case covers a review that takes longer than a few seconds
Where: z-design step 2 ("`./zn dispatch zz-review <id> --mode design` … (a headless run always uses it)"), the same in z-raft and z-run; `runner.run` (`limit = if adapters.toolRunning(acc) then r.toolSeconds else r.stallSeconds`; quiet counts only the author CLI's stdout); root `.models.toml` `tool_seconds = 900`; §5 "Open tool calls"; control-cli :: "a review the author starts…" (the fake reviewer answers at once); Unknowns E1 to E14 (none times a nested step).
Evidence (reasoned from the code and the CLIs' documented limits; not run against a real CLI):
- **The runner.** While the author waits on the nested dispatcher, the author's CLI prints a `tool_use`/`tool_call` start and then nothing until the command returns. The nested dispatcher's own lines go into the tool's captured output, not the author's stream. The runner's `quiet` grows and is reset only by the author's stdout. At `tool_seconds` (900 s) the runner kills the author's group, the nested dispatcher with it, and the reviewer goes with its lifeline. The outcome is `stalled`.
- **The CLI.** Claude Code's Bash tool stops a command after `BASH_DEFAULT_TIMEOUT_MS` (120 s by default) unless the model asks for more, and never allows more than `BASH_MAX_TIMEOUT_MS` (600 s by default). The prototype's claude argv and step environment set neither. The `agent` and `grok` limits are not probed.
- **How long reviews take.** This repository's ledgers hold 136 review-round rows. Their median is 4.0 minutes, the 75th percentile 8.3 and the maximum 29; 8 are over 15 minutes. A code review (`z-run`) also runs the full gate (177.8 s this round) and `./zn check` inside the reviewer. So under `claude-cli` most nested reviews outlive the 120 s default. Some outlive the 600 s ceiling and the 900 s tool limit on any CLI.
- **Why check.sh passes.** Every nested-review case uses a fake reviewer that answers in milliseconds, so AC10 passes for an implementation that can't finish a real review round.

Critique: this is the chain's main path. Every z-design, z-raft and z-run step under the dispatcher reviews this way, so the captured "chains the steps on its own … up to the pull request" stops at the first long review. It fails closed (`stalled`, the item stopped), but it fails on ordinary input. Raising `tool_seconds` is the tempting fix. It doesn't touch the CLI's own timeout, and it lets a hung tool run longer.
Consequences: the outer runner needs a liveness signal from the nested step, and each CLI's shell timeout must be known and raised or worked around. Polling from the author (start in the background, check every few minutes) keeps the stream alive. But each poll is a model call, which counts against `max_calls` on `agent`, and the skill must tell the author how to poll.
Recommendation:
- **Liveness.** A nested step touches a heartbeat file in its parent's state folder (`$ZN_DISPATCH_DIR/<nested>/beat`) on every line its own CLI prints. The outer runner counts a fresh beat as output. A nested step that is itself quiet still stalls at its own limits, so nothing hangs.
- **Claude's timeout.** The `claude-cli` step environment sets `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS` to at least the reviewer's own ceiling.
- **E15 (new experiment), per CLI:** a headless step runs a 20-minute shell command. Does the CLI kill it, at what limit, and which setting raises it? The fallback for a CLI that can't be raised: the skill starts the review in the background and polls `./zn dispatch status` (the cost per poll stated against `max_calls`); else escalate to the user.
- **Case (control-cli):** with `tool_seconds = 2`, a nested fake reviewer that prints a line every second for 5 s, and an author that waits on it, finishes `ok` (mutant: no heartbeat). A nested reviewer that goes quiet past its own limit stops as `stalled`.
- **Rows:** add a Rules and mutants row for each.
Lesson: ticket-prep/instructions-runnable-where-they-run

### F3 [high] The rafting gate merges unattended (`auto_merge = ["prep", "raft"]` at the root), but no case drives its judgment: a dispatcher whose rafting gate judges nothing passes check.sh (repeat of review-003 F5, its P2 half)
Where: `dispatcher.judgePr`, raft branch (`own` from the raft documents in the PR's head, `only`: "not one of the raft's own items"); Rules and mutants row "a rafting PR carries only its own items | none | … (reasoned: no CLI case drives a rafting PR's head; the executor adds one) | reasoned"; AC10 ("a gate merges only a PR that carries its own tracker state"); dispatch.spec drives `judged` for the prep gate only.
Evidence (mutant, scratch clone `c0117-review004/mut`): the first line of `judgePr` became `if gateName ~= "prep" then return nil end`, so the rafting gate merges any green, mergeable PR, code included. `./zn check c0117` printed **11/11 criteria passed** (exit 0). The mutant survives every sequestered case.
Critique: this is the gate round 3's P2 attacked (a rafting PR rewriting another item's `check.sh`). The design now says it's fixed but proves only the prep half. "The executor adds one" can't hold: the acceptance specs are sequestered, so an executor's own spec isn't part of `check.sh`, and its absence fails nothing. `fakecli.pullRequest` already makes real heads on the fixture origin, so the case is cheap. The rafting rule also has paths the prep rule doesn't: members read from the head's `issues: [...]`, a raft document that isn't new, and `z-nile/next`.
Consequences: none beyond the cases. If the cases find that a block-style `issues:` list parses to no members, that fails closed (it waits for a human); say so.
Recommendation: control-cli cases for the rafting gate, each with a real head through `fakecli.pullRequest` and `auto_merge = ["raft"]`:
- **Merges:** a rafting PR that adds `rafts/R0050/R0050.md` (`issues: [c0010]`) and edits c0010's `raft:` line.
- **Waits, code:** one that also carries `src/x.lua`.
- **Waits, another item's check.sh:** one that changes c0091's `check.sh`, c0091 not a member.
- **Waits, a `.models.toml`:** one that adds c0010's `.models.toml`.
- **Waits, a stale head.**
- **Mutants:** the raft branch skipped; `own` from every raft on `main` rather than the PR's.
- **Row:** turn the reasoned row into a run row.
Lesson: ticket-prep/spec-design-correspondence, testing/guard-needs-its-own-case

### F4 [low] The new lesson `guard-state-out-of-reach-or-checked` prescribes the equality compare that F1 shows breaks concurrent runs, and `merge-gate-checks-what-it-merges` still opens with "Read the PR's changed files"
Where: `.claude/skills/architecture/lessons/guard-state-out-of-reach-or-checked.md` ("compare the shared copy with it"); `merge-gate-checks-what-it-merges.md`, first paragraph (only its "How to apply" was fixed for review 003 F11).
Recommendation:
- **guard-state:** add "when other legitimate processes write the record, re-check what it guards from your own copy; never fail on the record merely differing", and add to its check "who else writes this record?".
- **merge-gate:** reword the first paragraph to "fetch the PR's head pinned to `headRefOid` and judge its commits", so the body and "How to apply" agree.

### F5 [low] §8 step 4 and E10 disagree about a shared account: "the first two pass" against "the first three pass"
Where: §8 "Verify (E10)" ("If the user's account is the bot's … the first two pass"); Unknowns E10 ("If the agent's token is the user's own account … the first three pass").
Recommendation: one wording in both places. With the user's own token, the push, `gh pr merge` and the API merge all succeed (the admin bypasses), so "the first three". Pin it in docs.spec if the README repeats it.

Repository safety (item 9): no finding.
- Every new case runs under `.cache/<name>` fixtures (`fakecli.new`, `trackerfix.new`, `.cache/c0117-trackerstate`, `.cache/c0117-wrapper`).
- Commits are made as `@example.invalid` (`trackerfix` identity, the scripts' `-c user.email=…@example.invalid`).
- Pull-request heads are pushed only to the fixture origin's `refs/pull/<n>/head`.
- The origin-repointing case changes only the fixture main's configuration.
- `ZN_WATERMARK_DIR` is set in `fakecli.zn`, which every dispatching spec uses, so no case writes the user's `~/.local/state`.
- I found no spec, `check.sh` line or script that writes the real repository or weakens a fence.
- `check.sh` only runs specs through `tests/run`, plus `./zn skills --check`, `lessons --check` and `audit` (read-only).

Lessons (item 10): each design lesson's check was asked of the draft. F1 repeats `lock-reads-live-state`: the in-run guard holds a copy that other processes update. F2 repeats `instructions-runnable-where-they-run`: a headless author can't run a long review as one command. F3 repeats `spec-design-correspondence` and `guard-needs-its-own-case`. The four lessons new or changed since round 3 each generalise beyond c0117. `authority-config-is-not-tracker-state` and `sequestered-files-judged-per-item` are good as written; the other two need F4's edits.

Candidate lessons (for the lead):
- A guard's record with several honest writers is checked by what it guards, never by equality. Check: who else legitimately writes this record (another run, the user's command), and does the guard re-check its subject from its own copy instead of failing when the record moved?
- A step that waits on another step must show it is alive to whatever watches it. Check: when this step runs a long child (a nested review, a gate), what resets the parent's stall clock, and what is the CLI's own limit on one command?

Verdict: changes
