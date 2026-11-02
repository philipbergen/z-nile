# Review 001: c0191 (design mode)
Inputs: prep worktree at de3ad691 (uncommitted prep files): c0191.md, check.sh, acceptance/ (bounded, boundcmd, reap, reap-e2e, runner-cpu, docs), experiments/ref-*; zz-review, z-design (+ chore checklist), zz-arch, zz-test skills; `./zn lessons --when design`; other prep worktrees (c0132, c0157, c0165, c0166, c0180); live `ps` on this machine (read only).
Capture: `./zn capture c0191` prints 58b946db (the template "new" commit). The user's Problem quote, Non-goals and Solution ideas were added in b7b14ea1 (a commit titled for c0180). I judged scope against b7b14ea1. The document's Problem, Non-goals and Solution match it word for word, plus one "Prep detail" paragraph.

### F1 [high] The first captured outcome ("every such command stops on its own within a limit") is met only for interpreter starts: shell loops, background calls and the Monitor tool stay unbounded, and three such loops are running on this machine now
Where: Design, `boundcmd` (Refused/Passes); AC2; settings `matcher: "Bash"`; Problem, "What should happen", bullet 1.
Evidence: `ps` on this machine, 2026-11-01. Session `claude` pid 3465 has three agent-started Bash children with `etime` 05-08:51 to 05-13:45. Two are `until s=$(gh pr view 138 --json …) && …; do …; sleep 30; done`. One is `until grep -qE 'GATE (PASSED|FAILED)|sweeper was killed|tripwire' …/90b21ea5-…/scratchpad/full.log; do sleep 20; done`, which polls a log in the incident session's scratchpad that will never finish. Under this design:
- the hook passes all three, because no program in `INTERPRETERS`/`lune`/`rojo`/detachers appears;
- the reaper keeps them, because their owner (claude 3465) is alive, so they are not orphans, and `--session-end` fires only when that session ends, which can be days later.

Other gaps:
- `caffeinate -i` with no `-t` never ends. It passes because `caffeinate` is a PREFIX with no following word.
- `tail -f`, `watch` and `gh run watch` pass.
- E2 shows that a foreground call past its timeout is moved to the background, so any foreground loop becomes one of these.
- The Monitor tool also takes a shell `command`. The `Bash`-only matcher never sees it. When a monitor expires, the harness kills its shell. E4 shows that killing the Rokit shim leaves its `lune` child spinning, so `Monitor(command: "lune run probe.luau")` leaks exactly as the incident did.

Critique: The Problem is "No process a session or agent starts can … run unbounded". The design narrows that to "interpreters started from Bash", with no Scope decision. The tempting fix is to add `while`/`until` to the refused list.
Consequences:
- Long legitimate polls (PR CI, a full gate's log) run longer than the runner's 900 s maximum.
- A refused `until … sleep` gives the agent no wrapper that works for a 40-minute wait.
- `tool_input.run_in_background` is a field the classifier does not read today.
- The `matcher` regex changes the settings case (`group.matcher == "Bash"` exactly).
Recommendation:
- Treat as unbounded, refused unless the call goes through `./zn run`, `./zn …`, the gate or a check.sh:
  - a Bash call with `run_in_background: true`;
  - top-level `while`/`until` loops;
  - `tail -f`/`-F`, `watch`, `gh run watch`, `gh pr checks --watch`, `yes`;
  - `caffeinate` without `-t`.
- Run the hook on `Bash|Monitor`.
- Decide the `--time` maximum for waits. For example, allow up to 3600 s when `--cpu` is small: a sleeping poll costs no CPU, and the deadline rule still reaps it. Write that decision into the Design.
- Spec cases (boundcmd): JSON payloads with `run_in_background: true`, each loop form, `caffeinate -i` refused and `caffeinate -i -t 300` passing, a Monitor payload refused, and the settings case accepting a matcher that covers both tools.
- AC2's text grows to match.
- If the user prefers interpreter-only enforcement, that is a scope decision: escalate to the user, with the options and the cost (the 5-day loops above stay possible).
Lesson: z-design/never-narrow-captured-scope

### F2 [high] The CPU limits do not compose: any spec run started under `./zn run` fails, because the jail cannot raise the inherited limit to 1200 s
Where: `fence.luau` jail string `ulimit -t "$6" && …` (ref-zn-and-fence.diff.txt); `bounded.pl` line 76 `ulimit -t "$1" || exit 126`.
Evidence: on this machine, `/bin/sh -c 'ulimit -t 5; /bin/bash -c "ulimit -t 10 && echo raised || echo refused"'` prints `ulimit: cpu time: cannot modify limit: Operation not permitted` and `refused`; setting the equal value works. `--cpu` is at most 900 and the jail asks for 1200. So `./zn run --time 120 -- lune run tests/run -- <spec>` fails with that error every time, before any spec runs.

That command is the natural migration of the recipe this rule replaces. Reviewer briefs today say "wrap single spec runs in `perl -e 'alarm…'`", and the hook will refuse that recipe and name `./zn run`.

Worse, active c0153 runs its mutation check as `python3 -I experiments/mutants.py`, which runs `tests/run` once per mutant. The hook refuses it bare. Wrapped, every mutant's spec run fails on the ulimit, so every mutant counts as "killed" and the mutation check passes vacuously.

`bounded.pl` has the same defect: nested `./zn run` calls, or a caller with a lower limit, give exit 126 with no message, and the CPU-detection branch is skipped.
Critique: "the gate, check.sh files and `lune run tests/run` need no wrapper" doesn't forbid wrapping, and the hook's own message and the reviewer briefs will produce wrapped runs. The tempting fix is "tell people not to wrap the runner", which is a prose rule again.
Consequences:
- With "lower only", 1200 becomes a ceiling, not a guarantee: a caller who bounds a run gives its specs less CPU, and a spec that hits the lower limit dies of SIGXCPU.
- The outer `./zn run` then reports exit 125, which is right.
- AC5's default case must still see 1200 when nothing lower is inherited.
Recommendation:
- Both the jail's shell and `bounded.pl` lower the limit only: read `ulimit -t`, and set the requested value only when the current one is `unlimited` or larger.
- `bounded.pl` prints the effective limit on stderr when it inherited a lower one (never a silent 126).
- Spec cases:
  - runner-cpu: a run under an inherited `ulimit -t 100` runs, and its probe sees 100.
  - bounded: `--cpu 50` under an inherited 20 runs with 20.
  - bounded: `./zn run --time 60 -- lune run tests/run -- <probe>` on runner-cpu's fixture passes.
- Rows in Rules and mutants for each case (mutant: unconditional `ulimit -t`).
Lesson: z-design/fallbacks-name-the-modes-they-cover (the modes include "under the bounded runner")

### F3 [high] AC4 runs the new reaper unjailed against the real process table, so a wrong implementation stops other sessions' processes during `./zn check c0191`
Where: check.sh AC4; acceptance/reap-e2e.luau lines 40-43; Rules row "`--root` ignored; stop outside the root … reasoned (not applied)".
Evidence: reap-e2e's safety rests entirely on the implementation under test honouring `--root`. The executor writes `cmd.reap` after these checks exist (tests first) and runs AC4 while iterating.
- Suppose a first implementation drops `--root`, which is plausible: `flags()` gains four boolean flags in the diff, and the value flags `--root`, `--under`, `--min-age` and `--log` go through its generic branch. Then `#roots == 0`, so `scratch = true` and the default scope applies. The "real" step runs `--min-age 0 --under <awk pid>` on the whole machine. It stops every ownerless `lune`/`git`/`sh`/`bash`/`perl` whose folder is in the main checkout, any `.worktree/` or any session scratchpad, immediately and with no age limit. That includes other sessions' just-orphaned work and children of `git maintenance` (F6).
- The row that would show this was not applied, because applying it is dangerous: the case is unsafe by construction.

Critique: zz-test says checks change only fixtures. This one acts on the live machine and fails open on an implementation bug. The tempting fix is "be careful when implementing".
Consequences: a gate before the real step needs a list of the pids the script expects. The reaper's tree listing (`+k child(ren)`) means the expected set includes the decoys' children (the shim's `lune` child).
Recommendation:
- reap-e2e fails closed: after the `--dry-run` step, parse every `would stop pid N` and its `cwd`. Run the `--auto` and real steps only if every N is one of the recorded decoys (or their recorded children) and every cwd is under `$W/in`. Otherwise print FAIL and stop.
- The reaper itself refuses `--min-age` below 60 and `--under` unless `--root` is given (F7), so the dangerous combination is refused by the code as well as by the check.
- Add both to Rules and mutants as `run`. The dry-run gate makes the "`--root` ignored" mutant safe to apply.
Lesson: zz-test/new-commands-run-in-a-copy

### F4 [medium] `./zn …` and the allow-listed Lune entries run with no bound at all, and the incident's loop was in engine code
Where: boundcmd `TOOLING` (includes `z-nile/engine/main`, `scripts/cicd`, `z-nile/affected`, `z-nile/roots`, `scripts/affected`) and "Passes: `./zn ...`"; its comment says they are "jailed, swept and CPU-limited by the runner".
Evidence: only `tests/run` runs in the jail. The others are plain unjailed Lune processes with no `ulimit`. The incident's infinite loop was in `raftcheck`, which is engine code (c0193). A `./zn` command that reaches such a loop in a live session spins as long as the session lives: the hook passes it, the reaper sees a live owner, and Problem bullet 1 is unmet. The TOOLING comment is false for six of its eight entries.
Critique: the capture exempts `./zn` from the wrapper requirement, not from every limit. The tempting fix is to wrap `zn` in `bounded.pl`, but `./zn land` and the Stop hook run the full gate for far longer than 900 s.
Consequences: a CPU limit (not a wall-clock one) on the engine's own Lune process is cheap and safe, because gate and land time is spent in child processes, each with its own CPU counter. It is composable only once F2's "lower only" rule holds.
Recommendation:
- `zn` sets a CPU limit for its engine, for example `ulimit -t ${ZN_ENGINE_CPU:-600}` before starting Lune, applied under F2's lower-only rule.
- The TOOLING entries get the same limit through the hook's message or a wrapper, or the comment states plainly that they are unbounded and why.
- Spec case: an engine command made to spin (a fixture `ZN_ENGINE_CPU=2` with a test seam, or a copied engine) dies at the limit.
- Record the 600 s choice against the slowest engine command, measured in prep.

### F5 [medium] The default scope covers every Claude session's scratch folder on the machine, including sessions working on other repositories: the Non-goals fence those out
Where: ref-reap.luau `inScope` (`string.find(cwd, "/claude%-%d+/")`, `/pickman%-run%.`, `/pickman%-guard%.` anywhere in the path); Non-goals bullet 3.
Evidence:
- `/private/tmp/claude-501/<project slug>/<session>/scratchpad` is per project. The pattern matches every project's scratchpads, and any path that contains a `/claude-<digits>/` folder (a repository named `claude-2` would match).
- The pattern also matches `pickman-run.*` folders of any other clone of pickman.
- An orphaned `bash` script that a session in another repository left in its scratchpad is stopped by this repository's `sync`.
- reap.spec's default fixture cwd is `/private/tmp/claude-501/proj/…`, so it pins the wide match.
Critique: this contradicts "Stopping processes that aren't the user's z-nile or pickman work (… other repositories)".
Consequences: the slug of a worktree session (`-Users-…-pickman--worktree-x`) differs from the main checkout's (`-Users-…-pickman`), so the match has to be a prefix of the main checkout's slug. Claude's slug rule (`/` and `.` become `-`) becomes something the reaper depends on; when it doesn't match, the process is kept (fail closed).
Recommendation:
- Anchor scratch scope to `^<TMPDIR-or-/private/tmp>/claude-<uid>/<slug of the main checkout>` with the slug as a prefix.
- Anchor the runner's temp folders to the runner's own `TMPDIR` prefix.
- reap.spec cases: another project's scratchpad is kept; a worktree session's scratchpad is in scope; `/Users/me/code/claude-2/x` is kept.

### F6 [medium] The exceptions don't hold across rules: children of `git maintenance` are orphans, and the deadline rule stops any program, including detached maintenance and GUI apps launched under `./zn run`
Where: ref-reap.luau `legitGit` (only the process whose own arguments say `maintenance`/`fsmonitor`), `decide` (the deadline branch runs before, and without, `legitGit`); Design "marked … (any program)".
Evidence:
- `git maintenance run --auto --detach` runs `git gc --auto`, `git repack`, `git pack-objects`, `git commit-graph write` and so on as its children. Their command lines don't name `maintenance`, and their chain is `git → git(maintenance) → 1`, all in CHAIN. So every one older than 60 s is an orphan and is stopped mid-repack. E7 saw seven detached maintenance processes at once.
- A `git commit` under `./zn run` starts a detached maintenance (setsid) that inherits `ZN_BOUNDED_DEADLINE`. Homebrew git shows its environment, so the deadline rule stops it 5 s after the deadline, whatever `legitGit` says.
- An editor or app started under `./zn run` (`code .` starts Electron outside the group) also carries the marker. Its folder may be the repository, and the rule names no program.
Critique: zz-arch rule 7 asks for one explicit yes. Here two of the three rules bypass the stated exceptions. The tempting fix is to add `gc` and `repack` to `legitGit`, which leaves the next git subcommand uncovered.
Consequences: exempting the tree below a legit git means walking ancestors for every candidate. That is cheap: the table is already in memory.
Recommendation:
- A process is never a leak when it, or any ancestor up to launchd, is a `legitGit` process. Apply this to all three rules.
- The deadline rule never stops a program under `*.app/Contents/` or one outside TARGETS ∪ INTERPRETERS (or state why "any program" is needed and fence the GUI case).
- reap.spec cases: `git gc --auto` and `git pack-objects` under a maintenance parent at PPID 1 are kept; a marked maintenance process past its deadline is kept; a marked `/Applications/X.app/Contents/MacOS/X` past its deadline is kept.

### F7 [medium] `--under`, `--root` and `--min-age` have no guard: `--under 1` or `--root /` turns the reaper on every live gate on the machine
Where: ref-reap.luau `below` (checks `at == root` before `at <= 1`), `under`/`inScope` (`--root /` strips to "" and matches every path), `num("--min-age", 60)`.
Evidence:
- `./zn reap --under 1` makes `below()` true for every process, so every `lune`/`sh`/`bash`/`perl`/`git` in scope is "started by the session that is ending", whatever its owner or age: every other session's running gate.
- `--root /` (or `--root ~`) puts the whole home folder in scope.
- `--min-age 0` without `--root` stops orphans the moment they appear. These are usage-text flags a person will type.
Critique: the reaper is "not a repository guard but follows its shape". These flags are the unguarded paths.
Consequences: AC4 needs `--under` and `--min-age 0`, so the restriction must still allow them with an explicit `--root`.
Recommendation:
- Refuse (exit 2, with the rule named):
  - `--under` with a pid ≤ 1, or a pid that is not a `claude` process unless `--root` is given;
  - `--min-age` below 60 unless `--root` is given;
  - a root that is empty, relative, `/`, or the home folder.
- reap.spec or bounded cases for each refusal, both sides.
Lesson: zz-test/refusals-tested-on-both-sides

### F8 [medium] At SessionEnd the reaper stops everything below `claude` that it names, including processes the agent never started, and on `/clear` the session goes on
Where: Design decision 4; ref-session-end.sh (skips only `resume`); ref-reap.luau session rule.
Evidence: ps shows that the agent's own commands sit under `claude → /bin/zsh -c source …/.claude/shell-snapshots/snapshot-zsh-….sh … eval '…'`. Other children of `claude` include:
- MCP stdio servers, started with the project folder as cwd, often through `sh`/`bash` wrappers or as `node`/`lune`/`perl` scripts;
- running hooks (another SessionEnd group, a plugin's hook);
- the status-line command.
SessionEnd fires on `clear` (documented reasons), and the claude process and its MCP servers live on. `--session-end` stops every `sh`/`bash`/`perl`/`lune`/`git` among them whose folder is the repository, so after `/clear` the session's MCP tools are dead.
Critique: "the agent or session that started it" is the agent's tool shells, not every child of the app. The tempting fix is to skip `clear` too, which leaves the background tasks of the cleared conversation running for the life of the process.
Consequences: the shell-snapshot command line is Claude Code's, unversioned. If its form changes, the session rule finds nothing (fail closed), and the orphan rule catches what remains after the exit.
Recommendation:
- The session rule takes only descendants of a direct child of the session process whose command matches Claude Code's tool-shell form (`/.claude/shell-snapshots/`).
- Record the form in the Design and keep the fail-closed fallback.
- reap.spec cases: an MCP-server-like `sh` child of `claude` is kept; a `lune` under a tool shell is stopped; a tool shell with an unknown form is kept.
Lesson: zz-arch/guard-no-is-explicit

### F9 [medium] `scripts/hooks/session-end.sh` has no Checked case and no Rules row
Where: Test plan; Rules and mutants; AC2 (checks only that the file is executable and wired); OC2.
Evidence: none of the following is pinned:
- the reason parsing (`sed` on JSON);
- the `resume` skip;
- the `--session-end` and `--min-age 60` arguments;
- the log path under `XDG_STATE_HOME`;
- the `cd` to its checkout;
- the unconditional exit 0.
A mutant that calls `./zn reap --min-age 60` without `--session-end` passes every check, and so does one that exits 1 on a missing log folder. The second blocks nothing, but the first silently loses the whole "stops when the session ends" outcome.
Critique: OC2 is Observed, and it can only show the happy path once.
Consequences: running the real script would run the real reaper, so the case needs a stand-in `zn`.
Recommendation:
- A jailed boundcmd or bounded case copies `session-end.sh` into `.cache/<fixture>/scripts/hooks/`, with a stand-in `zn` at the fixture top that records its argv and answers only those arguments.
- It feeds payloads with reasons `resume`, `clear`, `prompt_input_exit`, a malformed payload and an empty one.
- It asserts the argv (or none for `resume`), the log path, and exit 0 in every case.
- Add a Rules row for each.
Lesson: zz-test/stand-ins-answer-only-named-arguments; z-design/spec-design-correspondence

### F10 [medium] The hook is itself an unbounded `lune run` through the Rokit shim on every Bash call, so a classifier hang leaks the way E4 describes
Where: ref-pre-bash.sh.txt (`export PATH="$HOME/.rokit/bin:$PATH"` … `exec lune run z-nile/guard-bash`); settings (no `timeout` on the PreToolUse hook); also session-end.sh's `./zn reap` and the gate's `reap --auto`.
Evidence:
- `boundcmd` is a hand-written scanner over hostile text, the same class of code as `raftcheck` (c0193).
- If it loops, each Bash call waits for the hook timeout. Claude Code then kills the hook's process, which is the Rokit shim, and E4 shows that the real `lune` child keeps spinning at PPID 1. That happens once per Bash call.
- The orphan rule catches these 60 s later at the next sync, but only after they have run.
Critique: the guard against unbounded processes starts one unbounded process per call.
Consequences: a limit that is too small fails open, which the design accepts; set it well above the measured 30 ms.
Recommendation:
- `pre-bash.sh` runs `ulimit -t 2` before `exec`. Under F2's lower-only rule this needs no special case.
- Give the hook `"timeout": 10` in settings.
- `session-end.sh` runs the reaper with `ulimit -t 15` inside its 20 s budget.
- Spec case: `pre-bash.sh` under a spinning stand-in `guard-bash` exits, not 2, within a few seconds and leaves no process (pgrep by a unique name).

### F11 [medium] "Existing work: grep finds no skill that does" is false: pickman's skill and an active issue tell agents to run commands the hook refuses
Where: Chore checklist, Existing work (1).
Evidence:
- `pickman/skills/pickman-test/SKILL.md:20` (and SETUP.md:68) tell agents to run `lune run scripts/runtime-test -- <version>` and `--lobby <version>`. That command is not in `TOOLING`, so it is refused.
- `lune run scripts/deploy-beta` (SETUP.md) is refused too.
- Active `pickman/.tracker/issues/active/c0153/c0153.md:97` runs its mutation check as `python3 -I experiments/mutants.py`, and d0124 has `python3 tracker/rafts/R0044/experiments/mutants.py`. Both are refused, and once wrapped they break on F2.
- c0165 (preparing) adds `lune run z-nile/specs -- run|record|digest`, which check.sh runs. An agent repeating it by hand is refused, and nothing tells c0165 to extend `TOOLING`.
Critique: the refusal names a wrapper, so the work isn't blocked. But runtime tests and mutation runs take minutes. The 60 s the message proposes is too short, and the wrapped mutation run is silently wrong (F2).
Consequences: `TOOLING` is an exhaustive list other issues extend, so its owner must be named.
Recommendation:
- Rerun the search with every interpreter in INTERPRETERS and every `lune run` target, and paste it into the Design.
- For each hit, decide: add it to `TOOLING` (and say why it is bounded), or record that it is wrapped, with a suggested `--time`.
- Say in the Design that a new Lune entry the gate runs joins `TOOLING`, and add that rule to zz-arch's layout section so that c0165 sees it.
- A boundcmd case for each decided entry.
Lesson: z-design/new-rules-migrate-existing-work; zz-rules/exhaustive-lists-name-new-things; zz-review/lists-paste-their-search

### F12 [medium] Other preps in flight edit the same lines and modules, and only c0157 is quoted
Where: Chore checklist, Existing work (3).
Evidence (Touched modules read from each prep worktree today):
- **c0132** (prepared, `design: ready`) edits the same jail line, the `bash -c` string's `unset PICKMAN_REAP_SWEPT PICKMAN_REAP_CACHE PICKMAN_REAP_TOP;`, plus `fence.enter()` and repo-fence.spec.
- **c0180** (reviewed) splits `main.luau` into one module per command and records which commands each spec ran. c0191 adds `cmd.reap`, `reapAuto` and a call in `cmd.sync`, and changes `guarded()`'s signature.
- **c0165** (reviewed) touches `z-nile/check.sh`, `fence.luau`, repo-fence.spec, AGENTS.md, zz-execute, zz-review and zz-test, and adds the `z-nile/specs` entry (F11).
- **c0166** touches `zn`, `z-nile/check.sh`, AGENTS.md and four of the same skills.
Critique: "whichever lands second merges main" is only true for disjoint hunks. c0132's and c0191's edits to the jail string conflict on one line. After c0180, `cmd.reap` belongs in its own module, and docs.spec's source pins (`function cmd.sync(` … `reapAuto()`, `local function reapAuto()`) no longer hold.
Consequences: a sequestered source pin that a reviewed prep will move is a red check at merge.
Recommendation:
- Quote c0132, c0165, c0166 and c0180 by their current documents.
- Name the merge order or the rule for the second to land for each.
- Make docs.spec's sync pin robust to c0180's split: assert on a behaviour or on a function name c0180 keeps. Or put c0180 in the order and pin its layout.
Lesson: z-design/quote-other-preps-before-promising; zz-test/source-pins-name-what-the-design-names

### F13 [medium] The rule sentence says "every command", the mechanism refuses a handful, and zz-rules lets `./zn run` run anything in the read-only main checkout
Where: "The rule (exact text)"; ref-docs-draft zz-rules hunk ("`run` and `reap`, which touch no repository").
Evidence:
- "Run every command you start yourself that is not the gate, a check or the spec runner through `./zn run`" literally covers `git status`, `ls` and `grep`. No agent will follow that. zz-review's new items ask "did the probes run that way", which cannot be judged against a rule everyone breaks on every call.
- zz-rules' main-checkout list would allow `run` because it "touches no repository". But `./zn run -- <anything>` runs anything there, including `git commit`.
Critique: restated rules need to say what is enforced.
Consequences: the five pinned places and docs.spec's `RULE` change together.
Recommendation:
- Word the rule by class, not "every". For example: every probe, script, interpreter, loop or background command, as F1 defines them.
- The zz-rules entry allows `./zn run` in the main checkout only for a command that is itself allowed there.
- Pin both in docs.spec.
Lesson: z-design/restated-rules-move-together

### F14 [medium] U3's fallback ("raise the default") changes a sequestered number at merge, and AC5's default case inherits `PICKMAN_SPEC_CPU`
Where: Unknowns U3; runner-cpu.spec "a spec's processes carry 1200 seconds of CPU by default" (env `{ PICKMAN_TEST_FENCE = "" }` only).
Evidence:
- U3 runs only at the final merge. If 1200 is too low, the fallback is to raise the default, but AC5 pins `1200` in a sequestered file, so the executor hits a stop condition at the last step.
- The documented remedy for a spec that needs more ("`PICKMAN_SPEC_CPU` raises it") breaks AC5 itself. A gate run with `PICKMAN_SPEC_CPU=3000` passes 3000 to the copied runner's default case (Lune's `env` adds to the inherited environment), which then reads 3000, not 1200.
Critique: the gate's CPU headroom is measurable now: the coordinator and the slowest worker's `time` during any gate another session runs, read with `ps -o time=`.
Recommendation:
- Measure U3 in prep, read-only, from a gate already running, and record it.
- Make the default case clear `PICKMAN_SPEC_CPU` explicitly (`env.PICKMAN_SPEC_CPU = ""`) and say so.
- Record in the Design that a failed U3 is an escalation.
Lesson: zz-test/specs-set-host-markers-explicitly

### F15 [medium] reap-e2e's "live owner" decoys become orphans after 40 s of wall clock, so the check fails under load
Where: reap-e2e.luau lines 29-30 (`…; sleep 40` inside each awk's `system()`).
Evidence: the `live`, `marked` and `future` decoys are children of a `sh` whose life is `sleep 40`. The four reaper runs (Lune starts, two `ps`, `lsof`, up to two seconds of TERM polling per target) plus the 6 s readiness loop must all finish within 40 s. At the load this repository's gates run under (c0132: load around 30), that is not assured. Once the `sh` exits, `live` is a PPID-1 `perl` with `--min-age 0` in scope, so "a process with a live owner is not" and "a second run finds nothing" fail.
Critique: the check asserts on elapsed wall time.
Recommendation:
- The awks block on a FIFO (`read < "$W/hold"`) that the script releases after the last step, instead of `sleep 40`. Cleanup still kills by recorded pid with an identity check (F18).

### F16 [medium] `./zn run` reports exit 125, "stopped at the CPU limit", for any failing command whose children together used 90% of the per-process limit
Where: ref-bounded.pl lines 103-119.
Evidence:
- `times` gives the CPU of all reaped descendants combined, while `ulimit -t` is per process.
- With the default `--cpu = --time`, a parallel command, for example `./zn run --time 60 -- sh -c 'four workers; exit 3'` where the workers use 15 s of CPU each, exits 125 with the CPU message.
- Its real status, 3, is lost.
Critique: the runner replaces a correct result with a false one.
Recommendation:
- Report 125 only on unambiguous evidence: the direct child died of SIGXCPU (status 152), or the Rokit shim's exit 1 combined with its single child's CPU reaching the limit.
- Otherwise keep the command's code and add a stderr note when CPU reached 90%.
- Bounded case: two children at 60% each, exit 3, give exit 3.

### F17 [low] The refusal tells an agent in a scratch folder to run `./zn run`, which doesn't exist there, and the incident ran from a scratch folder
Where: boundcmd `say` texts.
Evidence: from `…/scratchpad/cr4`, `./zn run --time 60 -- lune run p2.luau` fails with "no such file". The hook knows its checkout (`pre-bash.sh` changes to it).
Recommendation: print the absolute path, as in `"<checkout>/zn" run --time 60 -- <command>`. Boundcmd case: the refusal from the entry names the absolute `zn`.
Lesson: z-design/instructions-runnable-where-they-run

### F18 [low] Kill details: only the tree's root is identity-checked, survivors are reported "stopped", and cleanups kill by stale pid
Where: ref-main-luau `reapRun`; bounded.spec `cleanup`; reap-e2e `cleanup`.
Evidence:
- `reapRun` re-reads `lstart` for the root only, then sends TERM to every snapshot descendant.
- `reapRun` polls only the root, so a child that ignores TERM is left alive while the line says "stopped".
- Both spec cleanups send `kill -KILL` to every recorded pid, including decoys the reaper already stopped, without checking start time.
Recommendation:
- Re-check each pid's `lstart` before signalling.
- Poll and KILL every pid in the tree.
- Make the cleanups check identity (or only kill pids still alive with the recorded command).
Lesson: zz-arch/children-need-a-lifeline; zz-arch/read-paired-facts-at-one-moment

### F19 [low] `guarded(true)` caches a silent answer, and `--auto` still prints `ps` problems
Where: ref-main-luau `guarded(quiet)`, `reapRun`.
Evidence:
- The messages print only inside `if guardedRun == nil`. After `reapAuto()`, any later `guarded()` in the same process, such as a future command that both syncs and publishes, prints nothing.
- `reapRun` prints every unreadable `ps` line even under `--quiet`. A locale that changes `lstart` makes every `sync` print about 1,200 lines.
Recommendation:
- Cache the answer and the message separately.
- Under `--quiet`, fold problems into one `reap: skipped (N unreadable ps lines)` line.
- A docs or main case for each.

### F20 [low] Platforms: `ps -E` and the `lstart` layout are macOS-only
Where: Design, `reap.markers`/`parse`.
Evidence: on Linux, `ps -E` is not BSD's (environment lives in `/proc/<pid>/environ`), so every `sync` and gate prints `reap: skipped (…)`, and AC4 fails there.
Recommendation: state the supported platforms. Either read `/proc` on Linux or make `--auto` skip quietly off macOS. Say what AC4 does on Linux.
Lesson: z-design/fallbacks-name-the-modes-they-cover

### F21 [low] Spec nits
Where: acceptance/*.
Evidence:
- The headers say "AC8 to AC3" (reap.spec) and "AC5 to AC2" (boundcmd.spec).
- docs.spec's "zz-review's two modes" finds `**Bounded commands**` twice anywhere in the file, not once per mode.
- docs.spec's `--plan` check passes an inverted `[[ -z $plan ]]`.
- The bounded refusals case never accepts `--time 900` or `--cpu 900`.
- INT and HUP forwarding are untested.
- The case "every process carries the CPU limit, orphaned or not" never orphans.
- `pgrep -f "lune run spin-c0191-probe.luau"` matches the same probe from another checkout's concurrent gate, so the case flakes.
Recommendation:
- Fix the headers.
- Search within each mode's section for the zz-review item.
- Pin `[[ -n $plan ]] ||`.
- Add the boundary acceptance cases and the INT and HUP cases.
- Rename the CPU-limit case or orphan its process.
- Give the probe a per-run unique name.
Lesson: zz-test/refusals-tested-on-both-sides

Lessons pass:
- The draft applies children-need-a-lifeline, guard-no-is-explicit and no-vacuous-pass where it names them.
- The findings above repeat new-rules-migrate-existing-work (F11), quote-other-preps-before-promising (F12), new-commands-run-in-a-copy (F3), never-narrow-captured-scope (F1) and fallbacks-name-the-modes-they-cover (F2, F20).
- This is round 1, so there is no harvest.md to judge.

`size: 1400` is plausible: the reference files come to about 1,250 changed lines before the zz-test section is expanded. Experiment claims E1, E3, E5 and E6 match the reference code and specs. E2 is consistent with the live `ps` above.

Verdict: changes
