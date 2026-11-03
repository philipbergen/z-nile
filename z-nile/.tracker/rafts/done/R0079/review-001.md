# Review 001: R0079 (code mode)
Inputs: HEAD 3a7a7c3ede8ae8b9ab4108740d7d31e60bceee36 (branch R0079-bounded-commands-and-reaper, PR #227), `git diff origin/main...HEAD` (origin/main e337a745, merge-base 7902dec5); c0191.md (Design, Acceptance criteria, Verification log), c0191 `check.sh` and `acceptance/`, `experiments/ref-*`, R0079.md and its `check.sh`; zz-review, zz-arch, zz-test, zz-rules skills and `./zn lessons --skill zz-review --full`, `./zn lessons --when build`.

Evidence run for this review (every probe through `./zn run`):
- `diff experiments/ref-<f>.txt <f>` for bounded.pl, cpu.sh, boundcmd.luau, guard-bash.luau, reap.luau, pre-bash.sh, session-end.sh: all identical (the executor copied the reference files as the Implementation steps say).
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing; `git diff --summary` has no `mode change`.
- `./zn check c0191`: 6/6 criteria passed (45 s wall, its proofs included).
- `./zn reap --dry-run` on this machine: `reap: no leaked processes` (0.38 s).
- `z-nile/check.sh --affected` (selects everything for this diff): `GATE PASSED (affected)` in 342 s: z-nile 1764 passed, 0 failed (260 spec files), pickman 1273 passed, 0 failed (187 spec files). The full `--full` gate is left for the merge (the user's rule: one `--full` at the final merge), and the Verification log records the executor's RC0 full gate passing.
- The hook (`scripts/hooks/pre-bash.sh`) fed about 115 payloads (`jq`-built `{tool_name, cwd, tool_input:{command, run_in_background}}`); results quoted in F3 and F4. Three payloads of 30 to 120 KB (a 2,000-line `python3 - <<'PY'` edit, a 4,000-line `cat > f <<EOF` with quotes and `$(`, a 3,000-term `&&` chain) pass in 0.25 s each.
- `boundcmd.check` fuzzed with 20,000 random lines built from shell metacharacters, here-documents, `bash -c`, loops and prefixes: 0 errors, worst case 2 ms, total 0.59 s CPU (copy of the module in the session scratchpad, `./zn run --time 120 -- lune run fuzz.luau`).

Reaper safety (the brief's main question) holds as far as I could attack it: a signal goes only to a pid whose `lstart` still matches the snapshot; the reaper, its ancestors, pid 1, other users, `git maintenance`/`fsmonitor` and everything below them are never targets; the orphan rule needs a launchd-only chain of CHAIN names, so a terminal, `login`, `tmux`, an editor or a live `claude` ancestor keeps a process; the session rule needs a direct child of the nearest `claude` ancestor that sources a shell snapshot (here `claude -n …` and `/bin/zsh -c source /Users/…/.claude/shell-snapshots/…`, read with `ps`), and the default scope's session prefixes exclude other projects (`pickman-old`, `pickman.bak`). Hook fail-open holds: every non-refusal path in `guard-bash.luau` exits 0, a Lune error exits 1, a missing `lune` exits 127, SIGXCPU gives 152 or 1, and only `process.exit(2)` after a verdict refuses. CPU limits only lower at all five setters (`cpu.sh` used by `zn`, both hooks, the jail's shell and `bounded.pl`'s `sh -c`). The findings below are gaps, not wrong kills.

### F1 [medium] The reaper cannot recognise a Python process on macOS, so Python leaks escape the orphan and deadline rules, and so does any `lune` started by an orphaned Python
Where: `z-nile/engine/reap.luau:160` (`reap.name`), `:51-107` (TARGETS, INTERPRETERS, ORPHANABLE, CHAIN), `:358` (the `.app/Contents/` exclusion)
Evidence: on this machine `python3` is Homebrew's framework build, which re-executes itself as the bundle binary. Run under `./zn run --time 10 -- sh -c 'python3 -c "import time; time.sleep(2)" & sleep 0.7; ps -o pid=,command= -p $!'`, `ps` shows:
`5185 /opt/homebrew/Cellar/python@3.15/3.15.0_1/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python -c import time; time.sleep(2)`.
`reap.name` of that command is `Python`, which is in none of the lists (they hold `python` and `python3`). So:
(a) an orphaned Python process in scope is never stopped by the orphan rule;
(b) a `./zn run -- python3 …` that escaped the group (`setsid`) is never stopped by the deadline rule: the name does not match, and the command contains `.app/Contents/`, which the rule treats as an application;
(c) `ownerless` fails for every process under an orphaned Python, because `Python` is not in CHAIN, so the `lune run tests/run` children of an orphaned mutation runner (`python3 … mutants.py`, the c0153 case the Design names) are kept as well.
The same holds for `/usr/bin/python3` (Command Line Tools: `…/Python3.framework/Versions/3.x/Resources/Python.app/Contents/MacOS/Python`) and python.org builds. `grep -rn 'Python.app\|Python.framework' z-nile/.tracker/issues/active/c0191/` finds nothing, and `reap.spec.luau` has no Python case: the Design names `python` and `python3` as reapable, but nothing ever checked what macOS shows for them. The session-end rule still catches Python under a live tool shell (it takes the whole tree), so the gap is Python that outlives its shell or its session (a crash or a killed terminal, `&`, `setsid`). That is exactly the backstop the Problem's third bullet asks for.
Critique: the obvious fix is to add `Python` to the three lists. That also matches an application's embedded `Python` (Blender, Xcode tools), and the `.app/Contents/` exclusion would still block the deadline rule.
Consequences: the matching rule needs a precise form. Xcode's Python (`/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/…/Python.app/Contents/MacOS/Python`) sits inside an application bundle, and `/usr/bin/python3` resolves to it on machines where Xcode is selected, so "never inside another `.app`" would drop that case again.
Recommendation: give the reaper one function for a program's identity (it replaces `reap.name` wherever a list is consulted). When the first word matches `/Python3?%.framework/Versions/[^/]+/Resources/Python%.app/Contents/MacOS/Python$`, it returns `python3`, and the deadline rule's application test skips exactly that form. An application's embedded Python is still bounded in practice by the other conditions: the orphan rule needs a launchd-only chain and a folder in this repository, and the deadline rule needs `ZN_BOUNDED_DEADLINE`. Add cases in a new, unsequestered tooling spec (`z-nile/tests/tooling/`, not the sequestered `reap.spec`): an orphaned Homebrew Python in scope is stopped; a CLT Python and an Xcode-bundle Python past their deadline are stopped; a `lune` below an orphaned Python is stopped with its tree; `/Applications/Studio.app/Contents/MacOS/node helper` is still kept. Record the identity rule in zz-test's Bounded commands section (F2).

### F2 [medium] zz-test's "Bounded commands" section is the prep's unexpanded draft, not "the whole mechanism in one place" that the Design and step 6 require, and the deviation is not logged
Where: `z-nile/skills/zz-test/SKILL.md`, `## Bounded commands`; c0191 Design, "The rule" ("zz-test gets a `## Bounded commands` section (the whole mechanism in one place: runner, limits and exit codes, the hook and why it fails open, Monitor, the reaper's three rules and its call sites, the CPU limits and that they only lower, SIGXCPU's limit, what each cannot do)"); Implementation step 6 ("`ref-docs-draft.diff.txt` is a working draft; expand the zz-test section into the full mechanism description")
Evidence: the Verification log says the docs were done by "applying `ref-docs-draft.diff.txt`", and the section on the branch is that draft's seven bullets. What it lacks, item by item against the Design's list:
- **Why the hook fails open**: only "fails open".
- **Monitor**: the section never names it. Only the Hooks list says "Bash or Monitor", and nothing says that loops and follows pass in Monitor while interpreters and detachers do not.
- **The reaper's three rules**: named, but not their conditions (folder scope and what is in it, `--min-age` 60, one explicit yes, the session rule taking the whole tree by ancestry wherever it went). The SessionEnd budget is missing too.
- **The CPU limits**: the engine's `ZN_ENGINE_CPU` (1800 s) and the hooks' 2 s and 15 s are missing; only the spec runner's and `--cpu` appear.
- **SIGXCPU's limit**: the ignored signal is there, but E18 (a syscall-heavy loop beats `ulimit -t`) is missing.
- **What each cannot do**: missing. That covers the hook's uncovered forms (`bash probe.sh`, `npm`/`make`, unlisted interpreters, unreadable spellings), `setsid` leaving the group, and the reaper's gap after a crash for a shell outside scope.
- **What `Bash(./zn run:*)` allows**: missing. Any wrapped command runs without a permission prompt, which the Design states plainly as the user's decision.
AGENTS.md sends readers here ("The zz-test skill's "Bounded commands" has the rest"), so an agent refused by the hook, or a reviewer judging item 11/12, finds the class names but not the limits. `docs.spec` passes because it checks only that each part is named.
Critique: the tempting fix is to add a sentence to AGENTS.md or zz-review. The Design says the mechanism is described once, in zz-test (Restated rules).
Consequences: none beyond keeping the pinned sentences (the rule, `/clear`, the subagent sentence) word for word, which `docs.spec` checks.
Recommendation: expand the section in zz-test only, covering every item above. Keep the three pinned sentences unchanged and run `docs.spec` and the c0114/c0119 skill specs after the edit. If the expansion is deliberately deferred, log it as a deviation in the Verification log with its reason (zz-review code-mode item 4).

### F3 [medium] `tmux new -d`, `screen -dm` and `yes` pass the hook, and nothing else ever stops what they start
Where: `z-nile/engine/boundcmd.luau:34` (`DETACHERS`), `:36-49` (`FOLLOWERS`); `z-nile/engine/reap.luau:86-107` (CHAIN)
Evidence: hook exit codes from the payload run (`0` lets the call through):
`0 screen -dm lune run x`, `0 tmux new -d lune run x`, `0 at now <<< 'lune run x'`, `0 launchctl submit -l x -- lune run x`, `0 yes > /dev/null`. For comparison, `2 nohup ./zn check c0191 &` and `2 lune run probe.luau &`.
- A detached `tmux`/`screen` server is a PPID-1 process whose name is not in CHAIN, so `ownerless` is false for everything under it. Nothing marks the probe. It runs in no tool shell (the session rule misses it), and nothing gives it a CPU limit. A `lune` spinner started that way runs until reboot, which is the incident exactly.
- `at` and `launchctl submit` hand the command to launchd, outside every layer.
- `yes > /dev/null` burns a core in the foreground. The Design's Decision 2 lists `yes` (and `caffeinate` without `-t`) among the follows the hook refuses, but `FOLLOWERS` has no `yes`.
Decision 2 makes refusal by class ("a detacher"). The Design's "does not cover" list names only spellings the scanner can't read and unlisted interpreters, and these forms are plainly readable.
Critique: the tempting fix is to add `tmux` and `screen` to `DETACHERS` by name. That would refuse `tmux ls`, `tmux kill-session` and `screen -r`, which an agent uses to inspect or clean up.
Consequences: the refusal must look at arguments. The refusal text should send long-lived servers (`rojo serve` for Studio) to `./zn run --time 3600 -- …`. The user's own terminal use of tmux is untouched (the hook sees only agent tool calls).
Recommendation: under rule `detach`, refuse `tmux` with `new`/`new-session` and a `-d` flag; `screen` with `-d`, `-dm` or `-D`; `at`, `batch`; and `launchctl submit` (and `bootstrap`/`load` of a file). Refuse `yes` under `follow` as Decision 2 says. Add both-sides cases in an unsequestered tooling spec: `tmux new -d …` refused, `tmux ls` and `tmux kill-session -t x` pass, `screen -dm …` refused, `screen -ls` passes, `yes > /dev/null` refused, `yes | head -1` passes. Then list the remaining uncovered forms in zz-test (F2).

### F4 [low] Readable spellings of refused classes still pass the hook
Where: `z-nile/engine/boundcmd.luau` (prefix commands, `pythonHit`, loop keywords)
Evidence (hook exit codes, `0` lets the call through):
- `0 exec -a foo lune run probe.luau`: `exec` is a listed prefix, but its `-a NAME` option is not read.
- `0 find . -name '*.luau' -exec lune run {} \;`
- `0 python3 -c 'from subprocess import run; run(["lune","run","x"])'` and `0 python3 -c 'import subprocess as s; s.Popen(["x"])'`: the scan looks for the text `subprocess.`.
- `0 python3 -c 'import os; os.execvp("lune", ["lune","run","x"])'`
- `0 repeat 100000 sleep 1`: zsh's counted loop. The tool shell is zsh (E12).
- `0 awk 'BEGIN{while(1);}'`
The hook is a seatbelt by decision, and the reaper and the session end still take most of these.
Critique and consequences: each is a one-line rule. Chasing every spelling turns the scanner into a shell interpreter, which the Design rejects.
Recommendation: add the cheap ones: `exec`'s `-a NAME`; `find … -exec|-execdir <interpreter>`; `from subprocess import` and `import subprocess as`; `os.exec*` and `os.spawn*`; zsh `repeat` with a count above, say, 100. Give them spec cases in the same unsequestered tooling spec as F3. Name the rest in zz-test's "what it cannot do" (F2).

### F5 [low] The reaper reads `ps lstart` in the user's locale; under any non-English locale every line is "unreadable" and the backstop silently does nothing
Where: `z-nile/engine/main.luau` `reapRun` (`ps -axww -o …lstart=…`, and `running()`'s `ps -o pid=,stat=,lstart=`); `z-nile/engine/reap.luau:138` (`%a%a%a %a%a%a +%d+ [%d:]+ %d+`)
Evidence: `ps -o lstart= -p $$` gives `Mon Nov  2 20:58:01 2026`; with `LC_ALL=de_DE.UTF-8` it gives `Mo.  2 Nov. 20:58:01 2026`, and with `fr_FR.UTF-8` it gives `lun.  2 nov. 20:58:01 2026`. Neither matches the pattern. `--auto` (every `sync` and gate) then prints `reap: skipped (≈1200 unreadable ps lines)` and stops nothing. An explicit `reap` prints every line as a problem, then reaps nothing. It fails closed and is not a wrong kill, but on a new machine with another locale (SETUP.md) the backstop is off, and its only sign is a line nobody asked about.
Recommendation: run the three `ps` calls with `LC_ALL=C` (through `env LC_ALL=C ps …`, or the exec's env), so the parsed snapshot and the re-read agree. Add a case that pins the environment at the call site (zz-test/pin-call-site-arguments), for example a stub `ps` on PATH in a fixture that answers only when `LC_ALL=C`.

## Judged criteria (code mode only)
c0191 has no Judged criteria (its `### Judged` section reads "None."), so there is nothing to rule on.

Candidate lesson (for the lead to place): **a program-name rule is checked against what `ps` really prints for each name it lists** (zz-arch or zz-test). Why: F1. The Design listed `python`/`python3` for the reaper, and macOS shows every framework Python as `…/Python.app/Contents/MacOS/Python`, which also collides with the rule's application exclusion. Check: for each program a process rule names, did someone start it on the supported host and read its `ps -o command=`?

Verdict: changes
