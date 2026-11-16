# Review 003: c0191 (design mode)
Inputs: prep worktree at de3ad691 plus its uncommitted prep files (c0191.md, check.sh, acceptance/ 8 files, experiments/ref-*, design-review-001/002, design-refute-001/002, harvest.md); zz-review, z-design (+ checklists/chore.md), zz-arch, zz-test; `./zn lessons --when design --full` (140 lessons); the prep documents of c0132 (prep-sweeper-killed-under-load), c0157 (prep-gate-contention), c0165 (prep-reuse-test-results), c0166 (prep-relevant-review-lessons) and c0180 (prep-hybrid-inprocess-gate); the Monitor tool's schema as this harness loads it; the live `ps` table (read only).
Capture: round 2 found that `./zn capture c0191` prints only the template commit (58b946db) and that the real text came in b7b14ea1. So this is not a confirmed capture by the tool's own marker rule. I judged scope against b7b14ea1's Problem and Solution, which the document keeps word for word.
Dropped from design-review-002: none. These round-2 fixes hold against the documents, specs and reference code: F1 (tool shells with their trees), F2 (stand-in `ulimit`), F3 (no allow entry), F7, F8, F10, F11, F12, F13 and F14. F4 and F5 hold only in part (low findings below). F6 does not hold (F1 below). F9's parent-death rule is built, but the trap its consequences named is open (F4 below).
Probes: pure calls into copies of `ref-boundcmd.luau.txt` and `ref-reap.luau.txt` in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/c0191-review-r3/`, each under a 40 to 60 s alarm. I also ran the classifier over 859 unique real Bash calls (`calls.jsonl` in that folder). They were extracted read-only from the 12 smallest of this project's 25 session transcripts, with each call's `run_in_background` flag. No spec was run, nothing was signalled, and no reaper was run.

Lessons pass:
- Asked of the draft:
  - zz-arch/guards-decide-from-the-tools-resolution: F1;
  - a new refusal in a command is checked against every caller that builds its arguments: F1, F2;
  - a guard scan allowance is as narrow as the need: F3;
  - every product choice a prep makes is marked: F5;
  - spec-design-correspondence: F6;
  - a promoted case never compares measured times closer than a loaded machine's start-up jitter: F8;
  - a rule enforced in several places is one function: F9;
  - every review round's fixes rerun the whole regression sweep: F9.
- Applied well: guard-no-is-explicit, children-need-a-lifeline, read-paired-facts-at-one-moment, new-commands-run-in-a-copy (reap-e2e's dry-run gate holds), stand-ins-answer-only-named-arguments and no-vacuous-pass. On the last two: the stand-in `ulimit` reaches the shell it claims. `zn` is a non-interactive `bash` script, so it reads `BASH_ENV`. In runner-cpu the nested run cannot nest the jail, so its `bash -c` line runs bare, and `env -u PICKMAN_SWEEP_ONLY` keeps `BASH_ENV`. A default of 86400 therefore turns both specs red.
- `harvest.md` maps round 2 to existing lessons and one one-off, which is fair.

Candidate lesson for the lead (zz-review, as a subagent I write no lesson file): "A hook or guard that refuses agent commands is measured against real session history before it ships, with the refusal rate and the false refusals recorded; check: what share of last week's calls would this refuse, and which of them were routine?"

### F1 [high] The background rule refuses the gate, `./zn land` and every `./zn` or check.sh call that redirects or pipes its output, because the scanner reads `2>&1` as a `&` separator; 28 of the 30 real background calls in the sample are refused
Where: ref-boundcmd `split` (a `&` always ends a command); the TRIVIAL list in `boundcmd.check` (no `tail`, `tee`, `head` or `grep`); Design ("a **background Bash call** ... that is not the gate, the wrapper, a `./zn` command or a check" is refused, so those forms pass); AC2 ("passes the gate's commands"); boundcmd.spec's background ALLOWED list (only bare forms).
Evidence: with `{ background = true }`, each of these is refused by `background`:
- `z-nile/check.sh --full > .cache/full.log 2>&1`
- `cd /x/wt && z-nile/check.sh --affected 2>&1 | tail -20`
- `./zn check c0191 2>&1 | tail -5`
- `./zn land 2>&1`
- `lune run tests/run -- tests/x 2>&1 | tee .cache/log`

`2>&1` splits into the word `2>`, then a separate "command" `1`, and `1` is not TRIVIAL. `tail` and `tee` are not TRIVIAL either.

In the transcripts, the background calls agents actually make include `./zn land 2>&1 | tail -4` (6 times), `./zn land > …/land7.log 2>&1; echo "exit=$?"; tail -3 …` and `gh pr checks 95 --watch … 2>&1 | tail -8`. Of 30 unique background calls, 28 are refused, and 14 of those are `./zn` or check.sh calls the Design says pass. Round 2's F6 named exactly these gate forms as what the fix must keep passing. The spec's ALLOWED cases test only `z-nile/check.sh --full` bare, so the defect passes `check.sh`.
Critique: the rule refuses the commands it exists to let through. The refusal then sends agents to wrap `./zn land` and the full gate in `./zn run --time ≤3600`. That puts the gate under a CPU limit equal to its wall time and the runner's 125 heuristic (summed child CPU). The tempting fix is to add `1`, `tail` and `tee` to TRIVIAL. That hides a scanner bug behind a list: `&>log`, `>&2` and `2>&-` would each need their own entry.
Consequences: the scanner must treat `>&`, `<&`, `&>` and `&>>` (with an optional fd number or `-`) as part of a redirection word, never as a separator. Pipelines then need a rule: a background pipeline is bounded when its first command is, and every later stage ends at end of input. That covers `tail` (unless it follows), `tee`, `head`, `grep`, `sed`, `wc`, `sort` and `awk`. The follow rule still refuses `tail -f`.
Recommendation:
- Make the redirection operators part of the word in `split`.
- Add to TRIVIAL, for later pipeline stages only, the commands that end at end of input (`tail` without a follow, `tee`, `head`, `grep`, `sed`, `awk`, `wc`, `sort`, `cut`, `tr`).
- boundcmd.spec: add background ALLOWED cases for the five commands above and for `./zn land > log 2>&1; echo "exit=$?"; tail -3 log`.
- Add background REFUSED cases: `./zn list 2>&1 | perl -e '1 while 1'`, `sleep 600 &> log`, and `tail -f log 2>&1` (follow).
- Add a foreground case: `lune run p.luau 2>&1` is still refused.
- Add a Rules row "redirections are words, not separators", with the mutant "`&` always ends a command".
- Record a new experiment, E15: run the hook over a sample of this project's session history (the method above), with the refusal counts by rule and the listed false refusals, rerun after the fix.
Lesson: zz-arch/guards-decide-from-the-tools-resolution, z-design/new-refusals-reach-every-caller

### F2 [medium] The interpreter rule refuses about one Bash call in five in this repository's real work: 152 of 859 sampled calls are `python3 - <<'EOF'` file edits and `python3 -I -c` reads, all refused as "unbounded"
Where: Design, `boundcmd` Refused list ("`python`, `python3`, … unless `--version`/`--help`"); Existing work (the search covered skills and documents, not what agents run).
Evidence: the classifier over the 859 sample calls gives `unbounded:python3` 152, `unbounded:lune` 6 (all real probes, true positives) and `background` 26. Most of the python3 calls are in-place edits of documents and specs in prep and execution sessions, for example `python3 - <<'PY'\np='z-nile/.tracker/issues/c0194/c0194.md'\ns=open(p).read()…` and `python3 -I -c 'import json;print(json.load(open(".claude/settings.json"))…'`. Each takes milliseconds. The refusal's suggested command (`<zn> run --time 60 -- python3 -`) also drops the here-document, so the agent has to rebuild the call.
Critique: the captured idea refuses "a bare `lune run`, or other long-running interpreter call". The Design reads that as every interpreter call. That choice was made without measuring its cost, and the cost is a refused turn on roughly a fifth of all calls, in every session and subagent. That is the pressure that gets a hook switched off, and it hides the 6 real refusals among 152 false ones. The tempting fix is to exempt `python3 -` and `-c` outright. That lets `python3 -c 'while True: pass'` through, a gap the `perl -e` rule already closes for Perl.
Consequences: inline scripts can be scanned the way `perl -e` is. Refuse `-c` text or a here-document body that contains `while True`, `while 1` or `itertools.count`, or `subprocess`/`Popen` without a timeout; pass the rest. A file script (`python3 probe.py`) stays refused. That keeps the incident's shape (a probe file) and passes inline edits. The other choice, keeping every python3 call refused, is a cost the user should accept knowingly.
Recommendation:
- Escalate to the user with E15's numbers. Option (a): scan inline python (`-c` and `-` with a here-document) for loop and subprocess forms, as `perl -e` is scanned, and refuse only on a hit. Option (b): keep refusing every python3 call and record the measured refusal rate as accepted.
- Record the choice as a `Decided with the user` line.
- For (a), add boundcmd cases on both sides: a here-document edit passes, `-c 'while True: pass'` is refused, `python3 probe.py` is refused.
- Either way, make the refusal text keep the here-document, or say plainly that the call must be rerun with its input.
Lesson: z-design/new-refusals-reach-every-caller, z-design/new-rules-migrate-existing-work

### F3 [medium] `TOOLING` passes a scratch copy of the engine or runner, passes the bare engine with no CPU limit, and passes `scripts/cicd`, which runs the minutes-long `runtime-test` that the same list refuses
Where: ref-boundcmd `toolingMatch` (any path ending in `/<entry>`), `TOOLING` (`z-nile/engine/main`, `scripts/cicd`); Design ("`affected`, `roots`, `cicd` and `scripts/affected` are short tooling", "`z-nile/engine/main` is reached through `./zn`, which gives its engine a CPU limit").
Evidence: probes, each `ok`:
- `lune run /tmp/evil/scripts/cicd`
- `lune run /tmp/tests/run`
- `lune run …/scratchpad/cr4/z-nile/engine/main -- check …`, the incident's shape: a reviewer probing the engine's `check` in a scratch copy, now passing whenever the copy keeps the engine's path

A bare `lune run z-nile/engine/main -- …` (relative, in TOOLING) skips `zn`, so it gets none of `ZN_ENGINE_CPU`. The loop that leaked was in engine code. `pickman/scripts/cicd.luau` runs `scripts/deploy-beta` and `scripts/runtime-test` (its lines 204, 225 and 235). So `lune run scripts/cicd` passes bare while `lune run scripts/runtime-test` is refused and pickman-test is told to wrap it in `--time 600`.
Critique: the allowance is wider than its need (a path in this checkout) and includes two entries that are neither short nor limited. That contradicts the Design's own description of the list. The tempting fix is to drop the suffix match, which brings back round 2's F5 false refusal of an absolute path into the gate's own tooling.
Consequences: the entry already knows `ZN_CHECKOUT`, and the PreToolUse payload carries `cwd`. An absolute target can pass only under the checkout or one of its `.worktree/*`. A relative target can pass only when `cwd` is inside them. A scratch copy is then refused with the wrapper named.
Recommendation:
- Drop `z-nile/engine/main` from TOOLING (agents run `./zn`).
- Move `scripts/cicd` out, with the same wrap advice as `runtime-test` (pickman-test, docs.spec).
- Accept a TOOLING path only under `ZN_CHECKOUT`, its `.worktree/` folders, or a relative path from a `cwd` inside them.
- boundcmd: add REFUSED cases for `/tmp/x/z-nile/tests/run`, `lune run z-nile/engine/main -- list` and `lune run scripts/cicd`; keep the in-checkout absolute case in ALLOWED.
- Update the Design's TOOLING paragraph and its comment.
Lesson: zz-test/narrow-guard-allowances

### F4 [medium] The new parent-death rule silently kills `./zn run … &` started in a foreground call as soon as the call returns, and the hook passes that call (round 2 F9's named consequence is still open)
Where: ref-bounded.pl (`getppid() != $origppid` → stop, exit 129); boundcmd (`./zn …` passes whatever follows); round 2 F9 Consequences ("The hook would then refuse `zn run … &` outside `run_in_background` and say so").
Evidence: Claude Code's tool shell is `zsh -c 'source … && eval "<cmd>" … && pwd -P >| …'`. It backgrounds a `&` job, finishes, and exits. The runner's parent is then launchd, so within 0.2 s the runner TERMs the command and exits 129, with the message in whatever log stderr was redirected to. `./zn run --time 600 -- z-nile/check.sh --full > log 2>&1 &` passes the hook (probe: `ok`). The agent then waits for a log that stops after one line. The refute for F9 discussed only a runner orphaned before it starts.
Critique: the guard and the runner now disagree about what a background job is. This is the agent's natural way to start a long job, and it fails with nothing visible in the call's result.
Consequences: refusing `&` after a bounded command outside `run_in_background` needs its own message ("use run_in_background"). The same rule should cover `(… &)` and `nohup`-free spellings. A `&` inside the wrapped command (`./zn run -- sh -c 'a & b; wait'`) is fine and must keep passing.
Recommendation:
- Add a boundcmd rule `background-in-foreground`: a simple command ended by a single `&` at the top level of a foreground Bash call is refused. The message names `run_in_background: true` and the wrapper.
- Monitor is excepted (its shell lives to its timeout).
- Cases: `./zn run --time 600 -- x > log 2>&1 &` refused in foreground; the same with `{ background = true }` passes; `./zn run -- sh -c 'a & b; wait'` passes.
- Add a Rules row.
Lesson: zz-arch/children-need-a-lifeline

### F5 [medium] `/clear` stops every running background task of a session that goes on, including an in-flight `./zn land` or gate, and this product choice is neither marked nor tested
Where: Design, `session-end.sh` ("`clear` is not skipped: the cleared conversation's tool processes are its own"); U2 (asks only about `/exit`).
Evidence: SessionEnd fires on `clear` (Design, "What prep found"). The session rule takes every tool shell of `claude` except the reaper's ancestors, whatever it runs. The transcripts show `./zn land 2>&1 | tail -4` run with `run_in_background: true` and a 900 s timeout. A user who clears context while it runs has the land TERMed and, two seconds later, KILLed mid-gate or mid-push. Nothing records whether Claude Code itself keeps background tasks across `/clear`. If it does, this design is what ends them.
Critique: outcome 2 says a command stops "when the agent or session that started it ends". Whether `/clear` ends the session, in the sense the user meant, is a product question. The Design answers it silently, and its effect (losing a land in progress) is the kind of surprise the memory notes warn about ("Land: clean up only after 'landed'").
Consequences: if `/clear` skips the session rule, the cleared conversation's leaks are found by the orphan rule only once `claude` exits. If it keeps the rule, the user should know. In both cases a running `./zn land` needs a stated fate.
Recommendation:
- Add to U2: does a `run_in_background` task survive `/clear` without this hook?
- Escalate to the user: (a) `clear` runs the session rule (today's design, background tasks end); (b) `clear` skips it like `resume` (leaks wait for exit). Record a `Decided with the user` line.
- Pin the decision in hooks.spec (a payload with reason `clear` makes the reap call, or makes none).

### F6 [medium] AC6's "`./zn sync` runs the reaper" is pinned by a count of `reapAuto()` anywhere in the engine, so a call placed in another command, or after the fetch, passes
Where: docs.spec "./zn sync runs it too…" (`calls >= 2`, `["--auto"]`, `guarded(true)` anywhere); the Rules row "the reaper runs at the gate start and at `sync`" (`reasoned`; mutants listed: no call, call before the `--plan` guard).
Evidence: a `main.luau` that defines `reapAuto()` and calls it from `cmd.land` instead of `cmd.sync` satisfies all three assertions, and so does one that calls it after `sh.git({"fetch", …})`. The gate pin is similar: a commented-out line `# [[ -n $plan ]] || ./zn reap --auto || true` before `source z-nile/lib/par.sh` passes it.
Critique: a Checked criterion that a wrong placement passes. It was loosened to survive c0180's split, but there is a pin that survives the split without losing the placement. The tempting fix (match `function cmd.sync(`) breaks when c0180 lands first, which is why round 1 dropped it.
Consequences: pin the call inside the sync command's body in either layout. In `main.luau`, the text from `function cmd.sync(` to the next top-level `\nend\n`; in `cmd/sync.luau`, the whole file. Assert `reapAuto()` (or `reap --auto` through the shared helper) appears there before the first `fetch`.
Recommendation:
- In docs.spec, replace the count with that body search, handling both layouts. Add a case that the gate line does not start with `#`.
- Add the mutants "call moved to another command" and "commented line" to the row and run them on the prototype (both die on the new pin).

### F7 [low] Classifier spellings that still disagree with the Design, or with each other
Where: ref-boundcmd `resolve` (PREFIX option skipping), `withoutHeredocs`, the `for ((` text scan, the `lune` branch, the refusal text.
Evidence (probe verdicts):
- `timeout 30 lune run x.luau` is refused, but `timeout -s KILL 30 lune run x.luau` passes. `-s` is skipped, then `KILL` is taken as the program. `sudo -u me lune run x` and `env -S 'lune run x'` pass the same way.
- `cat <<EOF | bash` with `lune run x.luau` in the body passes: a body piped to a shell is read as data.
- `perl -E 'sleep 5 while 1'` passes.
- `echo "for ((;;))" > note` is refused (the C-style scan reads quoted text).
- `lune run --help` is refused.
- The suggested command loses quoting: `lune run p2.luau check 'a b'` becomes `… -- lune run p2.luau check a b`, the very reason decision 2 gives for not rewriting.

Recommendation:
- Skip an option's value for `-s`/`-k` (timeout), `-u`/`-g` (sudo) and `-S` (env, then read its string as a command).
- Treat a here-document whose line pipes into a shell as code.
- Run the `for ((` scan on the unquoted text.
- Pass `lune run --help`.
- Print the suggestion from the original text of the simple command, not the dequoted words.
- One case per form.

### F8 [low] Two process-timing details: the TERM-ignoring survivor case kills its mutant by about 0.1 s, and the runner loses every exit status when it inherits an ignored SIGCHLD
Where: bounded.spec "a survivor that ignores TERM is dead when the runner returns" (`goneSoon(pid, 10)`); ref-bounded.pl wait loop (`$got == -1` → `$st = -1`).
Evidence:
- The mutant (no final group KILL) leaves the survivor to the watchdog's KILL at 2.0 s. The case's tenth check comes after ten `sleep 0.2` processes and ten `kill -0` processes, about 1.9 to 2.1 s, and later under load. Whether the mutant dies depends on the machine's load. The row says `run`.
- If the runner is started with SIGCHLD ignored (inherited across exec), `waitpid` returns -1, `$?` is -1, and every command reports 255.
- Exit 129 means both "HUP received" and "the parent is gone". The Design gives both meanings and no way to tell them apart.

Recommendation:
- Assert the survivor is gone at the first check after the runner returns (a few tries, under 1 s), or give the watchdog's grace a value well above the poll window in the copied runner.
- `$SIG{CHLD} = 'DEFAULT'` at the runner's start, with a case that runs it under `perl -e '$SIG{CHLD}="IGNORE"; exec @ARGV'` and expects 7.
- Give "parent gone" its own code (for example 123), or say in the Design and the usage that 129 is both.
Lesson: zz-test/timing-margins-above-jitter

### F9 [low] Restated mechanics and stale text
Where: Rules table, Implementation steps, Maintainability, Regression guard; the lower-only CPU test in `bounded.pl`, the jail string, `zn`, `pre-bash.sh` and `session-end.sh`.
Evidence:
- The Rules row "settings wire both hooks and allow `./zn run` and `reap`" still says "allow", against round 2 F3's fix and the next row.
- Implementation step 1 says "(14 cases)"; the Test plan says 18.
- Maintainability says "one 120-line Perl file"; the reference is 148 lines.
- The `zn` row is "reasoned (… equivalent …)", though the stand-in `ulimit` now makes it runnable (`asked("500","100") == ""` kills an unconditional set).
- The "only lower" test is written five times, in three languages.
- The Regression guard records the 61-spec sweep as "rerun after round 1's changes". Round 2 changed the docs draft (F10) and the reference code. Two specs that read touched files are not in the swept list: `c0114/layout` (reads `zn`) and `c0120/gate-homes` (runs `z-nile/check.sh` non-plan in a fixture, which now calls `./zn reap --auto` through a stub `lune`). Both look compatible, but neither was run.

Recommendation:
- Fix the four texts.
- Put the lower-only test in one shell helper (`z-nile/lib/cpu.sh`, `zn_lower_cpu <n>`) sourced by `zn`, both hooks and the jail line, with `bounded.pl`'s `sh -c` calling the same function.
- Rerun the regression sweep, adding `c0114/layout` and `c0120/gate-homes`, after this round's fixes, and record the date.
Lesson: z-design/rerun-the-sweep-after-each-round

Other checks:
- Scope fidelity: every captured outcome has a Design and a Checked criterion. The runner's wall, CPU and group stops, including the stop when its parent dies, are AC1. The PreToolUse hook is AC2. The reaper is AC3 and AC4. Its SessionEnd wiring is AC2's settings case, and its gate and `sync` call sites are AC6 (see F6). The spec runner's CPU limit is AC5, and the docs are AC6. No recommendation here narrows an outcome. F2 and F5 are escalations.
- The reaper after the round-2 rewrite: I found no path by which a live session's tool shell becomes a target outside `--session-end`/`--under`.
  - The orphan rule needs every ancestor up to launchd to be in CHAIN. Every live `claude` on this machine (`claude -n …`, `claude --resume`) sits below `-/bin/zsh` → `/usr/bin/login`, and `claude` and `login` are not in CHAIN.
  - The marked rule never names `zsh`.
  - A tool shell's forked subshells carry the same snapshot text, and are taken with their tree or kept with it.
  - Editors' children (Code/Cursor helpers), `tmux`, login shells and launchd daemons outside the repository fail CHAIN or the folder scope.
  - What the orphan rule does take is any ownerless `lune`, `git`, `sh`, `node`, … with a folder in the repository, a minute after its start. That includes a user's own `nohup` job under the checkout after the terminal closes, which is what the capture asks for. Two residual cases depend on the claude binary being named `node`: a `node`-installed Claude Code launched from launchd or `nohup` would itself be an orphan target, and a session that is not named `claude` gets no session rule (fails closed, as documented).
- Lower-only limits compose in every nesting I traced:
  - `./zn check` (1800) → jail (1200) → AC4's `./zn run --time 180` (180);
  - `./zn land` → gate → jail (1200);
  - the Stop hook → `scripts/check.sh` (no engine limit) → jail (1200) → `reap --auto` engine (1200 kept);
  - session-end (15) → `zn` (15 kept);
  - a Monitor → `./zn run --cpu N` (N).
- c0180 (reviewed) no longer runs specs in-process (its Scope decision of 2026-11-01), so the per-process 1200 s still applies to one spec file per worker.
- c0132's jail-string edit and this one meet on one line, as the Design says. c0157's `check.sh` and `stop.sh` edits are near the new `reap --auto` line and also merge by hand.
- Repository safety: reap-e2e holds. Its real steps run only after a dry run that named something and named nothing outside `$W/in`, and `--root` replaces every default scope. The descendants of a decoy are its own `sh`, `perl` and Lune processes. The `--auto` step is a no-op under `ac.sh`'s fence.
- Size: 1550 is over z-raft's cap of about 1,500, so the issue is a raft by itself, which is allowed. F1, F3 and F4 add perhaps 60 lines.

Verdict: changes
