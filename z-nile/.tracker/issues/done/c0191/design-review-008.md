# Review 008: c0191 (design mode)
Inputs: prep worktree at 1e7e3e0b plus its uncommitted re-prep after round 007 (c0191.md, check.sh, harvest.md, acceptance/bounded, engine-cpu, hooks, runner-cpu specs changed; proof-bounded.luau, proof-limits.luau, design-refute-007.md new); design-review-007.md and design-refute-007.md; every changed acceptance file read in full; zz-review (design mode); the prototype branch R0071-no-leaked-processes (scratchpad `c0191/protodir`), cloned to a throwaway under the scratchpad with the worktree's acceptance files copied in, and deleted afterwards.
Scope of this round: round 007's fixes and what they introduced. The design was reviewed in rounds 001 to 005 and isn't re-reviewed. `./zn lessons --when design --full` wasn't re-run for this delta.
Probes (each under the scratchpad's `bounded.pl`; neither proof script run):
- `bash -n check.sh`: clean. `./zn check c0191` (300 s bound): every AC fails for the missing implementation, as expected, and bash prints `command substitution: line 17: syntax error near unexpected token 'done'` (and the same for line 26). See F1.
- the good prototype: `runner-cpu.spec`, `engine-cpu.spec`, `bounded.spec` **22 passed** in 11.5 s (3.0 s user, 5.9 s sys).
- mutants C (fence.luau jail shell: `( . cpu.sh && zn_lower_cpu "$6"; )`) and D (zn: `( zn_lower_cpu "$lim" )`) applied together: the 77 case fails ("expected 77, got 200", 200 being my wrapper's limit; the suite's jail gives 1200) and the 90 case fails ("expected 90, got 200"); the other 6 cases pass. Both rows can say `run`.
- `sh -c 'ulimit -t 1; perl -e "1 while (times)[0] < 3"'`: **not stopped**. It ended by its own bound with 3.0 s user and 4.7 s system CPU, 7.7 s in all against a 1 s limit, exit 0. The control `perl -e 'alarm 5; 1 while 1'` under the same limit died at 0.99 s with 152 (macOS 26.6.2). See F2.
- check.sh's new AC1/AC5 shell: `{ [ '$A' != '$HERE/acceptance' ] || { ulimit -t 60; …; }; }` parses, returns 0 after `done` (the test is true), returns the proof's status before it, and is reached only when the spec half passed. If `ulimit -t 60` is refused (the caller's limit is lower), the `;` goes on under the lower limit, which is right. No finding on the quoting.
- the elapsed-time assertion (`os.time() - started < 10`): the case takes about 0.5 s on the prototype, `os.time()` is whole seconds, and the mutant takes 61 s. A 10 s bound leaves about 9 s for load: two perl startups and one 0.2 s poll. That's adequate. A 30 s bound would cost nothing and still fail the mutant, so the lead may widen it, but this is not a finding.

### F1 [medium] Backticks in two check.sh labels run as command substitution: a syntax error on every run, and a mangled label
Where: check.sh, the AC1 and AC5 `check "…"` labels ("before `done` only")
Evidence: the labels are double-quoted, so bash runs `` `done` `` as a command substitution. `./zn check c0191` printed `check.sh: command substitution: line 17: syntax error near unexpected token 'done'` (and line 26), and the labels came out as "and, before  only, against real processes". `bash -n` doesn't catch it because the error happens at run time.
Critique: the file is sequestered, so the executor can't fix it. Every check run, review round and `done` would print two bash syntax errors, and an agent or reviewer may chase them as a real failure. The fix for review 007's F3 introduced it. The other backticks in check.sh are in comments, which is safe.
Recommendation: drop the backticks in the two labels (`before ./zn done only` or `before done only`), or switch those labels to single quotes. Then re-run `./zn check c0191` and confirm stderr has no `command substitution` line.

### F2 [medium] `ulimit -t` does not stop a loop that spends its time in system calls, and E1 and the Design say otherwise
Where: Design "What prep found" (E1: "`ulimit -t` works … but is SIGXCPU only"); E17 ("one earlier attempt with a `(times)` self-bound spinner failed to be stopped by `--cpu 1` and had to be killed by the outer bound"); the spec runner's 1200 s, the engine's 1800 s and the hook entry's 2 s, which are CPU-only bounds; proof-limits and proof-bounded (every spinner is a pure user-mode loop)
Evidence: my probe above. A `times`-polling perl loop under `ulimit -t 1` ran 7.7 CPU seconds, most of it system time, and was never signalled. A pure user loop died at 1 s. E17 saw the same thing and treated it as a test artefact: it switched the spinner form and didn't record a new unknown.
Critique: the issue promises that no process "can run unbounded". For the engine and the hook entry the CPU limit is the only bound. The hook's limit exists because a harness-killed hook leaves an orphaned real `lune`. A loop that polls a file, `stat`s, spawns or reads in a tight cycle (the realistic shape of a stuck poll or watcher, unlike the incident's pure-Luau loop) escapes all three limits. Every proof uses a pure user-mode spinner, so all of them pass while this gap stays. `./zn run`'s wall limit and the jail's sweeper still cover their own cases. This is an Unknowns failure (item 1): an observed contradiction of a load-bearing assumption, with no experiment, no stated gap and no fallback.
Consequences: a real fix means a wall-clock bound where only a CPU bound exists (the hook entry; the engine, or say why the engine needs none). That changes Design text and possibly a Rules row, but no scope.
Recommendation: add an experiment E18 ("does `ulimit -t` stop a syscall-heavy loop on macOS?": the probe above, a 3 s self-bound), record the result and the stated gap in E1's paragraph and in the Design's gap statement, and choose a fallback per bound:
- **hook entry:** run it under the bounded runner (`perl bounded.pl --time 8 --`) or `perl -e 'alarm 8; exec @ARGV'` inside `pre-bash.sh`, within the harness's 10 s;
- **engine:** state that it is covered only by the CPU limit and the reaper's orphan rule, or give it a wall bound;
- **spec runner:** the sweeper and the gate's own limits cover it; say so.
Optionally add one syscall-heavy spinner case (self-bounded at 3 s) to proof-limits for the hook, if a wall bound is added there.

### F3 [medium] "Then it gets removed" is recorded as decided while the design only makes the files inert, and the open question isn't in the document
Where: c0191.md line 44 ("Decided with the user (2026-11-01): '… and then it gets removed.' … once the sequestered folder is gone the promoted file is inert"); design-refute-007 F3 ("Open question for the user … reported to the lead, not decided here")
Evidence: `grep -n 'delet\|Open question\|escalat' c0191.md` finds no record of the question. `done` still promotes both proofs to `tests/acceptance/c0191/`, where they stay in the tree, runnable by hand.
Critique: the user's words were "gets removed". "Inert but present" is the author's reading, filed under a "Decided with the user" line that the user didn't decide. Scope fidelity (item 11) requires the document to say which parts the user decided. The refute moved the question to the lead's report, so the next round, the executor and z-ready can't see it.
Recommendation: split line 44. Keep the user's quote and the rule they set as decided. Record "inert after `done`; whether the promoted proof files must also be deleted is open" as an explicit open question (or a `Scope decision` line once the lead has asked). If the answer is "delete", add the mechanism (a step in the Implementation steps that removes the promoted proofs in the raft's PR after `done`, or `done` support) and its check.

### F4 [low] "Once" survives in six places that F3 of round 007 said to reword
Where: c0191.md AC5 ("and, once, in a check-run script"); check.sh AC2 label ("the one-time proof"); file headers of bounded.spec (line 13), engine-cpu.spec (5), runner-cpu.spec (5), proof-bounded (4: "runs it once") and proof-limits (5: "runs it once")
Evidence: grep above. The refute says the labels, comments, Test plan, decision line and steps were reworded. The AC5 criterion and the five file headers weren't.
Recommendation: replace each with "only before `./zn done`, by check.sh". The acceptance files are sequestered, so do it now.

### F5 [low] proof-limits' fallback kill has no identity check, unlike proof-bounded's
Where: `proof-limits.luau` `recordedGone` (`kill -KILL pid` after 25 polls)
Evidence: proof-bounded's `cleanup` only signals a pid whose `ps` command line is its own `sleep 6x.x` or the runner. `recordedGone` KILLs whatever process holds the recorded pid after 5 s. This script runs unjailed. The pid would have to be reused within the window, so the risk is small, but it breaks the rule proof-bounded's header states for unjailed proofs.
Recommendation: before the KILL, check the pid's `ps -o command=` for the stand-in's file (`{dir}/z-nile/guard-bash.luau` or `{dir}/z-nile/engine/main.luau`).

### F6 [low] Figures and records that disagree with the files
- proof-bounded header and Test plan line 239: "every spinner stops itself after 20 CPU seconds". The perl spinners use `alarm 20`, which is wall clock. Only the Lune spinner uses `os.clock()`.
- Test plan: `docs.spec.luau` "10 cases" (the file has 11 `it`) and `reap.spec.luau` "17 cases" (18). Both predate the re-prep.
- E17 says "Mutants B, C, D are `reasoned`/shown by the reviewer's recipe", while row 326 says `run` and row 268 says "reasoned for the 90 case". This round ran C and D on the final files (above). Update E17 and both rows to `run`, citing this round. B is still unrun.
- Implementation step 4: "Verify: AC4 passes (`./zn check c0191` runs it …)". This contradicts the preamble ("verify steps 1 to 4 … through their spec commands"), and AC4 is a script, not a spec. Give its own command (`./zn run --time 180 -- lune run <A>/reap-e2e.luau`), or allow the `./zn check` run at step 4 in the preamble.
Recommendation: correct each one.

Candidate lesson (for the lead to file): z-design: an experiment result that contradicts a recorded finding (here, a spinner that the CPU limit did not stop) is a new unknown with its own experiment, not something to work around by changing the test input, because E17 changed the spinner form and the gap it showed went unrecorded. Check: "did any experiment in this round behave differently from what E-n claims, and is that difference recorded?"

Verdict: changes
