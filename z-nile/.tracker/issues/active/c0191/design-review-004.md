# Review 004: c0191 (design mode)
Inputs: prep worktree at de3ad691 plus its uncommitted prep files (c0191.md, check.sh, acceptance/ 8 files, experiments/ref-* 12 files, design-review-001..003, design-refute-001..003, harvest.md); zz-review, z-design (+ checklists/chore.md), zz-arch, zz-test; `./zn lessons --when design --full` (140 lessons) and `./zn lessons --skill zz-review --full`; `./zn capture c0191`; c0193's prepared document and specs (`.worktree/prep-lesson-scanner-loops-advance`); the live `ps` table (read only).
Dropped from design-review-003: none. None was refuted; F2 and F5 came back as user decisions. Below I judge each fix against the documents, specs and reference code.
Capture: as in rounds 2 and 3, `./zn capture c0191` prints only the template commit 58b946db, so this is not a confirmed capture by the tool's own marker rule. Its one-line Problem ("No process a session or agent starts can outlive it or spin unbounded") and b7b14ea1's full text are what I judged scope against. The document keeps both, plus two `Decided with the user` lines, which are allowed.
Probes: pure calls into copies of `ref-boundcmd.luau.txt` and `ref-reap.luau.txt` in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/c0191-review-r4/` (p1 to p4), each under a 40 to 60 s alarm. I also ran the classifier over round 3's 859-call corpus (p2), which reproduces E15 exactly: 22 refusals (`unbounded:python3` 13, `unbounded:lune` 6, `background:python3` 2, `background:bash` 1). I ran no spec, no reaper and no gate, and signalled nothing.

Round 3's fixes, checked:
- F1 (redirections are words) holds. `ls &>/dev/null` and `git log >& out` pass in the background; `lune run p.luau 2>&1` is refused; no gate-shaped call in the corpus is refused.
- F3 (TOOLING only in this checkout) holds for the payload's `cwd`. A `cd` inside the command defeats it (F6).
- F4 (`&` in a foreground call) holds for `cmd &` and `(cmd &)`. It misses `(cmd)&`, `{ cmd; }&` and every background or Monitor call (F3).
- F6 (sync pin in the command's body) holds, except that a commented-out `-- reapAuto()` passes (F7).
- F7 (spellings) holds. Probed: `timeout -s KILL`, `nice -n 5`, `env -S`, `env -i`, `xargs -I{}`, `cat <<EOF | bash`, `perl -E`, a quoted `for ((;;))`, `lune run --help`.
- F8 holds: the survivor case looks at the first polls; SIGCHLD is reset (without the reset the runner reports 255, so the `reasoned` row's mutant would die); 123 is distinct from 129.
- F9 holds: one `zn_lower_cpu` in `cpu.sh`, the fixtures copy it, and the jail's shell skips a missing one. Step 1's case count is stale again (F7).
- The two decisions are built, but the Python one only for the plain spelling (F2). The `/clear` one is pinned in hooks.spec and docs.spec, but it has a consequence nobody named (F9), and the AGENTS.md draft garbles its sentence (F7).
- Settings: `boundcmd.spec`'s settings case stays red until the executor applies `ref-settings.json.txt`. Implementation step 2 says so in bold, so I accept it as stated and do not report it.

Lessons pass:
- Asked of the draft:
  - z-design/never-narrow-captured-scope: F1;
  - zz-arch/guard-no-is-explicit, read the other way (a "keep" that the capture says must be a "stop"): F1;
  - zz-arch/guards-decide-from-the-tools-resolution: F2, F3, F6;
  - zz-test/one-rule-one-function: F2 (two readings of "which command reads this here-document");
  - zz-arch/children-need-a-lifeline: F3;
  - zz-test/count-calls-in-poll-loops: F4;
  - zz-test/seed-every-enumerated-case: F2, F4;
  - z-design/instructions-runnable-where-they-run: F7;
  - z-design/restated-rules-move-together: F7;
  - z-design/quote-other-preps-before-promising: F8;
  - z-design/accepted-risks-checked-and-decided: F9.
- Applied well: new-commands-run-in-a-copy (the e2e dry-run gate), stand-ins-answer-only-named-arguments, specs-set-host-markers-explicitly, refusals-tested-on-both-sides, timing-margins-above-jitter.
- `harvest.md`: round 3's rows map to existing lessons, which is fair, but round 3's candidate lesson is missing (F10).

Candidate lesson for the lead (zz-review; as a subagent I write no lesson file): "A rule that decides who owns a process uses ownership (ancestry) wherever it is known, and keeps the folder scope only for processes whose owner is gone. Why: c0191 review 004 F1: the session rule also required the tool shell's folder to be in scope, so a session's own shell in a `mktemp -d` clone outlived the session and was never reaped. Check: for each rule that keeps a process, is the reason it keeps it a fact about ownership, or a proxy (its folder) that the owner's own work can step outside?"

### F1 [high] A session's own tool shell is never stopped, at its end or after, once its folder is outside the repository and the session scratch folders (a `mktemp -d` clone, as zz-rules' merge procedure makes); one such leak is running in this session now
Where: ref-reap `decide` (`not inScope(p.cwd, …)` → `continue`, before all three rules, including `under`); Design, "A process is stopped only when all of these hold … its working folder is under a root … or a scratch prefix"; reap.spec's session case ("an out-of-scope shell … kept"); zz-rules Merging step 2 (`dir=$(mktemp -d)`; clone; gate there); the capture ("No process a session or agent starts can outlive it").
Evidence:
- Live, read only. Tool shell 62384, a direct child of this session's `claude -n Z-NILE` (64186), sourcing its shell snapshot, has run 4 h 41 m. Its child `ugrep -c ^git repack` (63274) has 0 CPU and is blocked reading fd 0, a unix socket that never closes. The call ran `grep -c '^git repack' $SHIM_LOG` with `SHIM_LOG` empty.
- `lsof` gives the shell's folder as `/private/var/folders/b1/…/T/tmp.VVxWCcQtwK/repo/z-nile`: a `mktemp -d` clone of this repository. That is neither the main checkout, nor `<tmp>/claude-501/<slug>`, nor `pickman-run.*` or `pickman-guard.*`.
- A pure probe (p4) with that shape returns 0 targets with `under = claude` (session end, `/clear` included), and 0 targets once the shell is orphaned (PPID 1). The same shell with its folder in the scratchpad returns 1.
- So the design never stops this process: not at `/exit`, not at `/clear`, not at any later gate, sync or session end. The same holds for any unwrapped command the hook passes (`sleep`, a filter, `git`, `gh`, inline Python, `bash script.sh`, `make`) once its shell `cd`s outside the scope. The merge procedure's own clone, and `$TMPDIR/tmp.*` in general, are such places.
Critique:
- The session rule already knows the process is the session's: it is a direct child of the ending `claude` and sources its snapshot. The hook that runs it comes from this project's settings, so the ending session is this project's.
- The folder test adds nothing to that, except the miss above. It turns "every such command stops when the agent or session that started it ends" into "… unless it changed folder".
- The fix the author will be tempted to make is to add `<TMPDIR>/tmp.` to the scratch prefixes. That catches this clone but not `/tmp/x` or another `mktemp` template. It would also make the orphan rule take other tools' `tmp.*` work.
Consequences:
- Judging the session rule by ancestry alone stops the session's shells wherever they are. That matches the pinned docs sentence ("A `/clear` ends the background commands of the conversation it clears"), which is untrue today.
- It must not weaken AC4's safety. With an explicit `--root`, the e2e gate requires every named process to be under the throwaway folder. So keep "a `--root` replaces every default scope, the session rule included", and make the session rule scope-free only under the default scope.
- The orphan rule after a killed terminal keeps its folder scope, so a shell orphaned outside it stays. That remaining gap has to be either stated or closed: for example, a scope entry for clones of this repository, a folder whose git root holds this repository's root commit, at one `git` call per candidate.
- The Non-goal "other repositories" is the only text that could be read as excluding a tool shell that `cd`ed into another repository. If the author reads it that way, it is a decision for the user, not a design choice.
Recommendation:
- Under the default scope, take the session rule's targets (`under` set, a tool shell, `ppid == under`) by ancestry only. With an explicit `--root`, keep the folder test for every rule.
- reap.spec: replace "an out-of-scope shell is kept" with two cases.
  - Default scope: a session shell in `<T>/tmp.X/repo` is taken, with its tree.
  - Explicit `--root`: a shell outside the root is kept.
- Keep the orphan rule's scope. Either add clones of this repository to it (state how they are recognised, with a reap.spec case for a clone and one for an unrelated `tmp.*` folder), or record the killed-terminal gap under "Limits of the design".
- If the Non-goal is read as covering a session's shell in another repository, escalate to the user with the options and their costs:
  - (a) ancestry alone: every shell of this project's session stops at its end;
  - (b) ancestry plus clones of this repository;
  - (c) today's folder scope, which leaves the leak shown above running indefinitely.
- Add a Rules row: "the session rule is by ancestry under the default scope". Its mutant is the folder test kept; the spec kills it with the new case.
Lesson: z-design/never-narrow-captured-scope

### F2 [medium] The inline-Python decision holds only for `python3 - <<EOF` spelled bare: a prefix, a pipe or a redirect skips the scan, a Python file fed on stdin passes, and the scan refuses edits whose string literals mention `while True:` or `subprocess.`
Where: ref-boundcmd `checkCommand` (`elseif a == "-" then return OK`), `withoutHeredocs` (`first` = the segment's first word, not the resolved program), `pythonHit` (raw text, literals included), and the background rule (python3 is not TRIVIAL); the Design's "Decided with the user" item 1; E15; the boundcmd.spec python cases.
Evidence (probe p1):
- `FOO=1 python3 - <<'E'\nwhile True: pass\nE` → ok.
- `env PYTHONPATH=x python3 - <<'E'\nimport os\nos.system('sleep 999')\nE` → ok.
- `cat <<'E' | python3 -\nwhile True: pass\nE` → ok.
- `python3 - < probe.py` → ok, and `cat probe.py | python3 -` → ok. The decision says "a Python file stays refused".
- `checkCommand` passes `-` on the assumption that `withoutHeredocs` scanned a body. `withoutHeredocs` gives a body to python only when python is the first word of the segment. The two read "which command takes this here-document" differently.
- The other way round: `python3 - <<'E'\np='c0191.md'\ns=open(p).read()\ns=s.replace('\`subprocess.\` without','x')…\nE` is refused, and so is a `.replace('while True: pass','x')` edit of boundcmd.spec. Editing this issue's own files, or any document that quotes these forms, is refused.
- Corpus: the 2 `background:python3` refusals are inline document edits of c0180.md with no hit. E15 counts them among "13 Python files (the agent's mutation-runner scripts, rightly)". They are not files, and the decided rule would pass them in the foreground.
Critique:
- The user decided "refused only on a hit; a Python file stays refused". Both halves fail on common spellings, and no case would turn red: REFUSED and ALLOWED hold only bare `python3 -` and `python3 -c` forms.
- The tempting fix is to resolve the first word through `resolve` in `withoutHeredocs`. That handles the prefixes, but not a body piped in, nor a file fed with `<`.
Consequences:
- `python3 -` should pass only when this very command has a scanned here-document; otherwise its stdin is unreadable and it is refused like a file.
- Scanning code with string literals removed keeps `os.system(` and `subprocess.run(…, timeout=5)` and drops mentions.
- Whether scan-clean inline Python counts as "ends by itself" in a background call is a reading of the decision. Write it down either way, and fix E15's labels.
Recommendation:
- One function says which here-document body belongs to which simple command, using `resolve`'s reading, and both `checkCommand` and the scan use it.
- `-` with no such body is refused (rule `unbounded`, the file message).
- `pythonHit` runs on the body with `'…'`, `"…"` and triple-quoted literals blanked.
- State the background reading, and fix E15's sentence.
- boundcmd cases, REFUSED: `FOO=1 python3 - <<E` with a loop, `cat <<E | python3 -` with a loop, `python3 - < probe.py`, `cat probe.py | python3 -`. ALLOWED: a `python3 - <<E` edit whose literal contains `while True: pass` and `subprocess.`.
- Add one REFUSED case each for the forms the decision names but no case seeds: `itertools.cycle`, `serve_forever`, `signal.pause`, `os.fork`, `os.popen`.
Lesson: zz-test/one-rule-one-function, zz-test/seed-every-enumerated-case

### F3 [medium] The `&` rule (round 3 F4) misses `(cmd)&`, `{ cmd; }&` and every `&` in a background or Monitor call: a wrapped job is stopped at once (exit 123), and an unwrapped `./zn land … &` becomes an orphan that the next reap anywhere kills mid-land
Where: ref-boundcmd `check` (the `&` scan is in the `elseif not CTX.monitor` branch of `if CTX.background`); `split` (an `&` after `)` or `}` ends a command with no words, so its separator is never recorded); ref-reap's orphan rule.
Evidence (probe p3):
- These pass in the foreground: `(./zn run --time 60 -- lune run x.luau)&` and `{ ./zn run --time 60 -- lune run x.luau; } &`.
- These pass with `background = true`: `./zn run --time 600 -- z-nile/check.sh --full > log 2>&1 &`, `./zn land > land.log 2>&1 &` and `z-nile/check.sh --full > log 2>&1 &`. The last two also pass in Monitor.
- In each case the tool shell ends at once, so a wrapped job's runner sees its parent gone and stops the command within 0.2 s (exit 123, written to a log nobody watches).
- An unwrapped `./zn land` is reparented to launchd: `lune` is ORPHANABLE, its ancestors are only launchd, and its folder is the checkout. At the next `./zn sync`, gate start or session end of any session, a minute later, the orphan rule TERMs and KILLs it with its tree, in the middle of a gate or a push.
Critique:
- Round 3 F4 named "`(… &)` and `nohup`-free spellings". The fix covers one spelling in one context. This is the second hole in the same mechanism, so the mechanism itself is in question: a scan that only looks for `&` separators of words it recorded.
- The tempting fix is to look at the last character of the text, which `&&`, `2>&1` and `&>` defeat.
Consequences:
- Read the separator after every simple command and every group, `( … )` and `{ … }` included. A top-level `&` with no `wait` in the same call is refused in every context: Bash foreground, Bash background and Monitor.
- `./zn run -- sh -c 'a & b; wait'` and `a & b & wait` keep passing.
- The refusal names `run_in_background` without `&`.
Recommendation:
- `split` records the separator that follows `)` and `}` against the group.
- The `&` rule moves out of the foreground branch, so background calls and Monitor get it too.
- REFUSED cases: `(cmd)&` and `{ cmd; }&` in the foreground; `./zn run --time 600 -- x > log 2>&1 &` and `./zn land > log 2>&1 &` with `background = true`; the second with `monitor = true`.
- ALLOWED: the same lines without `&` in a background call.
- Extend the Rules row "a job started with `&` … is refused unless the call waits" to every context, with the mutant "`&` after a group not recorded".
Lesson: zz-arch/guards-decide-from-the-tools-resolution, zz-arch/children-need-a-lifeline

### F4 [medium] The reaper's stop step spawns one process per pid per poll and counts 20 polls, not two seconds, so "a session end is done in about two and a half seconds however many targets" is false; the KILL path is never exercised by AC4
Where: ref-main-luau `reapRun`:
- one `ps -o lstart= -p <pid>` per process of every tree;
- `survivors()`, one `kill -0` per pid, called up to 20 times with `sleep 0.1` between;
- then `kill -KILL`, another `sleep 0.2` and another `survivors()`.

Also the Design's edge paragraph ("so a session end is done in about two and a half seconds however many targets, inside its 20-second budget") and reap-e2e (every decoy dies on TERM).
Evidence:
- Each `./zn run` in a tree has a watchdog that ignores TERM (ref-bounded, line 74). So any target tree holding a wrapped command keeps `survivors()` non-empty until the runner's own two-second grace ends, or until the reaper's KILL. That is all 20 polls.
- With N pids, one poll is N process spawns plus 0.1 s. A session ending in the middle of a gate (a tool shell running `./zn check` or `land`: 6 workers with their children, easily 40 to 60 pids) costs 20 × N spawns. At 10 to 40 ms per spawn under the load the gate runs at, that is 8 to 48 s, and the `ps` re-read adds another N spawns first.
- The hook's budget is 20 s. Past it, the harness kills the hook, the Rokit shim dies, and the real Lune reaper is left running. That is E4's leak, with KILL possibly never sent.
- reap-e2e has no decoy that ignores TERM, so neither "KILL what is left" nor "COULD NOT STOP" ever runs in AC4. The Rules table has no row for either.
Critique: the cost grows with the size of the tree, and the loop counts steps instead of wall time, which is exactly the lesson's question. The tempting fix is a smaller loop count, which only moves the cliff.
Consequences:
- One `ps -o pid=,lstart= -p <all pids>` for the re-read, and one `ps -o pid= -p <all pids>` per poll (a vanished pid is simply missing), against a wall-clock deadline of two seconds. The cost is then constant in the size of the tree.
- A zombie still answers `kill -0`. `ps -o stat=` lets the poll treat `Z` as gone.
Recommendation:
- Rewrite the stop step as above, and put the re-read parse into `reap.luau` as a pure function: `reap.alive(psText, pids)`, `reap.unchanged(psText, tree)`.
- reap.spec cases for both: a pid missing, `Z` counted as gone, a changed `lstart` left out.
- reap-e2e: add a decoy that ignores TERM (`perl -e '$SIG{TERM}="IGNORE"; sleep 120'`) under the root. Assert it is dead after the real run, and that the run took under 6 s, a margin well above start-up jitter.
- Add Rules rows for "KILL what TERM did not stop", "the wait is two seconds of wall time" and "COULD NOT STOP exits 1" (the last `reasoned` if it cannot be made unkillable).
- Correct the Design's budget sentence to the measured cost.
Lesson: zz-test/count-calls-in-poll-loops

### F5 [low] The background rule treats every filter as "ends at the end of its input", but a filter with no operand reads the tool shell's stdin, a socket that never closes
Where: ref-boundcmd TRIVIAL (`tail`, `tee`, `head`, `grep`, `sed`, `awk`, `wc`, `sort`, `cut`, `tr`, `cat`, `uniq`); the Design's "the filters … end by themselves".
Evidence:
- `grep -c x` and `cat` pass with `background = true` (p1).
- Live: F1's `ugrep -c ^git repack` (63274) has been blocked on fd 0, a unix socket from Claude Code, for 4 h 41 m.
Recommendation:
- A filter counts as ending by itself only as a later pipeline stage, or with a non-option operand.
- Add the stdin case to "What it does not cover". An operand that expands to nothing (`$EMPTY`) cannot be seen.
- Cases: `cat` and `grep -c x` refused in a background call; `./zn land 2>&1 | tail -4` and `grep -c x log` still pass.

### F6 [low] The TOOLING folder check reads the payload's `cwd` and ignores a `cd` in the same line, so a scratch copy run as `cd /scratch && lune run tests/run` passes
Where: ref-boundcmd `toolingMatch` (`CTX.cwd`); Design, TOOLING ("a relative one passes only when the call's `cwd` … is inside it, so a scratch copy of the tooling is a probe like any other").
Evidence:
- `cd /tmp/cr4 && lune run tests/run -- x` and `cd /tmp/cr4/z-nile && lune run tests/run -- x` both pass with the checkout's own `cwd` (p1).
- 437 of the 859 corpus calls start with `cd`.
Recommendation:
- Track a top-level `cd <absolute path>` (or relative to the payload's `cwd`) through the line, and judge later TOOLING targets against it. A `cd` to a path the scanner cannot read (`cd $P`) leaves the folder unknown; say which way unknown decides.
- TOOLING_CASES: `cd /tmp/x && lune run tests/run` refused; `cd z-nile && lune run tests/run` from the checkout passes.

### F7 [low] Restated text that disagrees with the design, a merge instruction that cannot run where it runs, a stale count, and a sync pin that accepts a commented call
Where: ref-docs-draft; c0191.md Design (TOOLING paragraph) and Implementation step 1; docs.spec's sync case.
Evidence:
- zz-test "Bounded commands" draft: "`--time` … at most 900" (the runner and the Design say 3600). It also names exits 124 and 125 but not 123.
- AGENTS.md draft: "…refuses a bare `lune run` of a probe, A `/clear` ends …  `./zn reap` …". The `/clear` sentence is spliced into the middle of another, with a comma before it and a double space after.
- zz-test's hooks list draft: "Before every Bash command …: a command that starts an interpreter with no time limit is refused". The matcher is `Bash|Monitor`, and loops, follows and background calls are refused too.
- `lune run scripts/cicd` stays bare in three places: pickman-test's runtime row ("A merge runs `lune run scripts/cicd`", in the same table cell the draft edits), zz-rules Merging step 4 ("step 3 (`lune run scripts/cicd`)"), and SETUP.md:68. Only step 3 is wrapped.
- Step 3 runs "In `$dir/pickman` … `./zn run --time 1800 -- …`", but `zn` is at the clone's root, so it must be `../zn run …`. docs.spec's substring `./zn run --time 1800 -- lune run scripts/cicd` also matches `../zn`, so the executor can fix the text without editing a sequestered file.
- Implementation step 1: "AC1 line passes (18 cases)". bounded.spec has 19.
- docs.spec's sync case: the body `-- reapAuto()` followed by `sh.git({"fetch"…})` passes. The gate pin rejects a commented line; the sync pin does not.
Recommendation:
- Fix the draft (3600, 123, the spliced sentence, the hooks line) and the three bare `cicd` lines, and use `../zn` in step 3.
- Change step 1 to 19.
- In docs.spec, find `reapAuto()` only on a line that does not start with `--` (as the gate pin does), with the mutant "commented call" in the row.
Lesson: z-design/instructions-runnable-where-they-run, z-design/restated-rules-move-together

### F8 [low] c0193 calls `perl <checkout>/z-nile/lib/bounded.pl` directly, not `./zn run`, and the runner now needs `cpu.sh` beside it, but the Design's interface paragraph names only `./zn run --time N -- <cmd>`
Where: Design, "The runner's interface is stable for its callers (c0193 and the lesson c0192 run `./zn run --time N -- <cmd>` …)"; c0193.md (prep-lesson-scanner-loops-advance) `hostile.bounded`, which is `perl <checkout>/z-nile/lib/bounded.pl --time <seconds> -- <argv>`, run inside the spec jail; ref-bounded line 93 (`. "$1" && zn_lower_cpu "$2" || exit 126`).
Evidence:
- c0193 records that its prototype "was proven against c0191's reference `experiments/ref-bounded.pl.txt` copied to `z-nile/lib/bounded.pl`".
- With round 3's change, a copy of `bounded.pl` without its `cpu.sh` exits 126 for every command.
- The interface c0193 depends on is the path, a direct `perl` call inside the jail, 124 and 125, and 128+n. It is stable and covered: bounded.spec calls `perl BOUNDED` directly in the jail. But the Design does not say any of that.
Recommendation:
- The interface paragraph names `perl z-nile/lib/bounded.pl [--time S] [--cpu S] -- <cmd>` as the second stable entry (with `cpu.sh` beside it), and lists 123 and 126 among the exits a caller may see.
- Tell c0193's lead to rerun its prototype against the current reference, with `cpu.sh` copied.

### F9 [low] `/clear` also stops the in-flight calls of the session's running subagents, a consequence the decision did not name
Where: the Design's "Decided with the user" item 2; U2; the pinned sentence ("ends the background commands of the conversation it clears").
Evidence:
- Read only: this review's own tool shell is a direct child of the lead's `claude -n Z-NILE` (64186) and sources the same snapshot (`snapshot-zsh-1793480272332-20v3b8.sh`) as the lead's shells.
- So the session rule cannot tell a subagent's shell from the lead's. If background subagents outlive `/clear` (not recorded), a `/clear` TERMs their in-flight spec runs, gates and lands too.
Recommendation:
- Add to U2: do background subagents survive `/clear`?
- If they do, put it to the user as a `Decided with the user` addendum: (a) accept, and widen the docs sentence to "and its subagents'"; (b) skip the session rule on `clear` while subagents run, which ancestry cannot detect, so in practice skip `clear`.

### F10 [low] harvest.md drops round 3's candidate lesson
Where: harvest.md (rows for design-review-003 only); design-review-003's "Candidate lesson for the lead" (measure a refusing hook against real session history before it ships).
Evidence: no `- note …` line records it, and no lesson under `z-nile/skills/*/lessons/` asks that question (`./zn lessons --when design --full`, 140 checks read).
Recommendation: write it, or a note on an existing lesson such as `z-design/new-refusals-reach-every-caller`, and record it as `- note design-review-003 candidate: <lesson id>`.

Other checks:
- Scope fidelity: every captured outcome keeps a Design and a Checked criterion.
  - Runner: AC1, including the stop when its parent dies.
  - Hook: AC2.
  - Reaper: AC3 and AC4, with its SessionEnd wiring in AC2's settings case and its gate and sync call sites in AC6.
  - Spec runner CPU limit: AC5.
  - Docs: AC6.
  
  F1 is the one outcome the design meets only in part. No Recommendation here narrows an outcome.
- Repository safety: the e2e dry-run gate holds, and F1's recommendation keeps it, because `--root` keeps scoping every rule. The jail string change, `cpu.sh` and the two `ALLOWED` entries weaken no guard. `--auto` is a no-op under ac.sh's fence. No spec writes outside `.cache`.
- Lower-only limits compose in every nesting traced in round 3, and still do through `cpu.sh`.
- c0193's dependency: the runner's interface (124, 125, 128+n, direct `perl` call in the jail) is unchanged by round 3's fixes, apart from F8's documentation gap.

Verdict: changes
