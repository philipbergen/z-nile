# Review 005: c0191 (design mode)
Inputs: prep worktree at de3ad691 plus its uncommitted prep files (c0191.md, check.sh, acceptance/ 8 files, experiments/ref-* 14 files, design-review-001..004, design-refute-001..004, harvest.md); zz-review, z-design (+ checklists/chore.md), zz-arch, zz-test; `./zn lessons --when design --full` (140 lessons) and `./zn lessons --skill zz-review --full`; `./zn capture c0191`; the prototype `.worktree/proto-c0191` (every ref file and every acceptance file is byte-identical to it; its `main.luau` diff equals `ref-main-luau.diff.txt`); the other prep worktrees' Touched lists; the live `ps` table and this session's shell snapshot (read only).
Dropped from design-review-004: none. None was refuted. F1, F2, F3, F6, F8, F9 and F10 hold as fixed apart from what F3, F5, F7 and F8 below say; F4 is fixed in part (F5 below).
Capture: as in rounds 2 to 4, `./zn capture c0191` prints only the template commit 58b946db, so this is not a confirmed capture by the tool's own marker rule. I judged scope against its one-line Problem ("No process a session or agent starts can outlive it or spin unbounded") and b7b14ea1's full text, which the document keeps, plus its two `Decided with the user` lines.
Probes:
- Pure calls into copies of `ref-boundcmd.luau.txt` and `ref-reap.luau.txt` in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/c0191-review-r5/` (p1 to p3, c1 to c3), each under a 40 to 60 s alarm.
- The classifier over the 859-call corpus. With the payload `cwd` set to a worktree it gives 24 refusals: `unbounded:python3` 13, `unbounded:lune` 8, `background:python3` 2, `background:bash` 1. The corpus has no `cwd`, so the `lune` count moves with the assumed folder (13 at the checkout root, because relative `cd ../proto-…` lines leave it). Every `lune` refusal I read is a real `.cache/p*.luau` probe, and no gate-shaped call is refused.
- One spec run on the prototype, `reap.spec` with `boundcmd.spec`: 28 passed, 1 failed. The failure is the settings case, red until execution, as accepted.
- I ran no reaper, no e2e script and no gate, and signalled nothing.

Round 4's fixes, checked:
- F1 (session rule by ancestry): holds in `decide` and in reap.spec, whose session case takes the shell in Documents under the default scope and keeps it with `sessionAnywhere = false`. The value that switches it is built in `main.luau` (`sessionAnywhere = #userRoots == 0`), where no check reaches it (F2).
- F2 (inline Python): holds for every spelling it names. Probed:
  - refused: `FOO=1 python3 - <<E` with a loop; `env … python3 -` with `os.system`; `cat <<E | python3 -` with a loop; `cat probe.py | python3 -`; `python3 - < probe.py`; `itertools.cycle`; untimed `subprocess.run`;
  - passing: `subprocess.run(…, timeout=3)`; literals that mention `while True:` or `subprocess.`; two python here-documents on two lines; `python3 -I -`.
  - The owner of a here-document is still found by a regex that cuts at `&` (F3). The "background" reading the round asked for is not written down, and E15 still mislabels the two calls (F7).
- F3 (`&` after groups, `&` in background and Monitor calls): holds. Refused: `(sleep 5)&`, `{ sleep 5; }&`, `./zn land > l 2>&1 &` in a background call, `tail -f log &` in Monitor. Passing: `sleep 5 & wait` and the same `./zn land` line without `&`.
- F4 (reaper poll): the poll is one `ps -o pid=,stat=` per step. The `lstart` re-read is still one `ps` per process, the wait still counts steps, and the KILL skips the identity check (F5).
- F5 (filters need an operand or a pipe): holds for `cat`, `grep -c x`, `grep -q DONE full.log` and `cat log | grep x`. A redirect target and an option's value count as operands (F4).
- F6 (`cd` tracking): holds for `cd /tmp/cr4 && lune run tests/run`. A quoted operand passes, and a `cd` anywhere in the text counts, even one after the command or inside a string (F3).
- F7 (texts): the zz-test section says 3600 and lists 123 and 128+n. The AGENTS.md paragraph reads in order. The hooks line names Bash, Monitor and every refused class. zz-rules steps 3 and 4 use `../zn run`. In the prototype only SETUP.md (a terminal) keeps bare `lune run scripts/cicd`/`deploy-beta` (`git grep -n "lune run scripts/cicd\|lune run scripts/runtime-test\|lune run scripts/deploy" -- '*.md' zn z-nile/check.sh ':!*/.tracker/*'`: SETUP.md:54, :67, :68; pickman-test:20 is the wrapped form). The sync pin strips comments.
- F8 (`cpu.sh` beside `bounded.pl`): holds. ref-bounded exits 2 naming the missing file, and the "copied without cpu.sh" case exists. `engine.copy` (z-nile/tests/lib/engine.luau:61) copies all of `z-nile/lib`, so the copied-`zn` fixtures get `cpu.sh`.
- F9 holds as a stated consequence (Design, Decided item 2), with no U2 question added (see F1).
- F10 holds for round 3's candidate. Round 4's own candidate is missing (F8).

Lessons pass:
- Asked of the draft:
  - z-design/never-narrow-captured-scope: F1;
  - zz-test/kill-mutants-where-the-value-is-built and zz-test/pin-fail-safes-where-they-act: F2;
  - zz-test/one-rule-one-function and zz-arch/guards-decide-from-the-tools-resolution: F3;
  - zz-test/count-calls-in-poll-loops, zz-arch/read-paired-facts-at-one-moment and zz-arch/children-need-a-lifeline: F5;
  - z-design/quote-other-preps-before-promising and z-design/design-the-execution-window: F6;
  - z-design/decided-guesses-rewrite-their-body: F7.
- Applied well: new-commands-run-in-a-copy (the e2e dry-run gate still precedes every signal), stand-ins-answer-only-named-arguments, refusals-tested-on-both-sides, specs-set-host-markers-explicitly, timing-margins-above-jitter, seed-every-enumerated-case (the Python forms the decision names are now seeded).
- `harvest.md`: round 4's ten rows map to existing lessons, which is fair, but round 4's candidate lesson has no note (F8).

Candidate lesson for the lead (z-design; as a subagent I write no lesson file): "When a capture names several owners of one outcome ('the agent or session that started it'), the design says how each owner's end is detected, or records a decided reading. Why: c0191 review 005 F1: four rounds checked the session's end, and none asked what happens at a subagent's end, which ancestry cannot see. Check: for each actor the Problem names, which mechanism observes its end, and which case or experiment shows it?"

### F1 [high] The captured outcome "every such command stops when the **agent** or session that started it ends" has a design only for the session: a subagent's commands outlive the subagent, and nothing records a reading or an experiment
Where:
- Problem, "What should happen" bullet 2 (from b7b14ea1), and the capture's "No process a session or agent starts can outlive it".
- Design decision 4 and the reaper's session rule (`under` = the nearest `claude`).
- The rule sentence pinned in five places ("it stops at its limit, when it ends and when you do").
- U1 to U3; AC2 to AC4.

Evidence:
- The Design's only "end" mechanisms are the SessionEnd hook (session end, `/clear`) and the runner's parent watch. The parent the runner watches is the tool shell. `grep -n -i "subagentstop\|agent ends\|subagent ends" c0191.md design-*.md` finds nothing that handles a subagent's end.
- A subagent's tool shells cannot be told from the lead's. Round 4 F9 showed they are children of the same `claude` and source the same snapshot. Read only, on this machine: the 13 live tool shells of `claude` 64186 each write a different `/tmp/claude-<4 hex>-cwd`, so that file is per call, not per agent.
- So a subagent that starts `run_in_background: true` with `./zn run --time 3600 -- …`, or with the gate, `./zn land` or a `check.sh` (all passed as bounded), and then returns its report, leaves that command running.
  - It runs until its own limit (up to an hour, or none for the gate's own commands) or until the session ends.
  - The same holds for a subagent's foreground call that passed its timeout and was "moved to the background" (E2).
  - The incident's probes came from a code-review agent.
- The Design does not know whether Claude Code itself stops a subagent's background shells when the subagent returns. The question is not among U1 to U3.
- The pinned sentence tells every agent, subagents included, that the wrapped command stops "when you do".
- There is no `Scope decision` or `Decided with the user` line for this half of the outcome, and no criterion (Checked or Observed) covers it.

Critique:
- This is the same class of question as round 3's `/clear` escalation: what "ends" means for an owner the Problem names. Here the owner is a subagent, which is not the session.
- The tempting fix is to read "agent" as "the session's agent" in a sentence of the Design. That narrows a captured outcome without the user, and it leaves the pinned sentence untrue for subagents.

Consequences:
- If Claude Code stops a subagent's background shells when it returns, the outcome is met by the harness. It then needs an Observed criterion and a sentence in zz-test, as U1 and U2 do for theirs.
- If it does not, ancestry cannot pick out the subagent's shells.
  - A `SubagentStop` hook would need an identity that the shell's process carries. The hook payload's agent id (if Claude Code sends one) is not in the process table.
  - Refusing `run_in_background` inside subagents (if the PreToolUse payload tells a subagent's call apart) would cost subagents their background gates.
  - Each of these is a product choice.

Recommendation: escalate to the user:
- First run the cheap experiment in prep, as U4 with a pass/fail question: "does a subagent's `run_in_background` command (`./zn run --time 300 -- sleep 300`) survive the subagent's return?" Read `ps` a few seconds after the subagent reports.
- If it does not survive: record the fact, add Observed OC3, and add one zz-test sentence.
- If it survives, the options and their costs are:
  - (a) accept that a subagent's commands stop at their own limit (wrapped: at most 3600 s) or at the session's end. Record this as a `Decided with the user` line, and make the pinned sentence true for subagents (for example, "…when it ends and when your session does").
  - (b) refuse `run_in_background` in subagent calls (needs U1 to show the payload marks a subagent's call). Subagents lose background gates and lands.
  - (c) a `SubagentStop` reap keyed on a marker the hook can plant. The PreToolUse hook would have to rewrite commands, which decision 2 rejected.
- In every case add a Rules row and a case (or an OC) for the reading chosen.

Lesson: z-design/never-narrow-captured-scope

### F2 [medium] The default scope is built in `main.luau`, where no check reaches it: a reaper that does nothing outside `--root`, gets the slug wrong, or undoes round 4's F1 passes every criterion
Where: ref-main-luau `reapRun`:
- `roots = { main }` from `git rev-parse --git-common-dir`;
- the scratch prefixes from the slug `gsub(main, "[/%.]", "-")`, `id -u` and `getconf DARWIN_USER_TEMP_DIR`;
- `sessionAnywhere = #userRoots == 0`.

Also: reap.spec (which hands `decide` ready-made options, `sessionAnywhere = true` by default), reap-e2e (always `--root`), hooks.spec (a stand-in reaper), docs.spec, and the Rules row "the session rule is by ancestry under the default scope … run".

Evidence:
- `grep -n "sessionAnywhere\|slug\|getconf\|git-common-dir\|DARWIN" acceptance/*.luau` finds only reap.spec's own `opts` and a comment. No case derives the options from the facts the edge reads.
- Mutants no check kills:
  - `sessionAnywhere = false`. Round 4's high F1 is undone: the session's out-of-scope shells are kept at `/exit` and `/clear`.
  - The slug built from `/` only.
  - `roots = {}` at the default scope.
- Under each, `sync`, the gate start and the SessionEnd hook (all default scope) never find the incident. Yet AC3 (pure rules) stays green, AC4 (`--root` only) stays green, and AC2 (hooks.spec's stand-in records only the arguments) stays green.
- The Rules row for the session rule marks its "explicit root ignored" mutant as `run`, but it was run on the flag the spec sets, not on the code that sets the flag.

Critique: the decisions that make the backstop reach the incident's folder and the ending session's shells live in edge code that no check reaches. The reason the e2e check uses `--root` (safety) is sound, but it explains only why the edge was not run. The derivation itself is pure logic over read facts (zz-arch: pure modules over texts, reads at the edge). The tempting fix is a dry run at the default scope in reap-e2e. Without `--root` that needs a 60 s minimum age, it could name live processes on the machine, and it would still not pin the slug.

Consequences: a pure `reap.scope(facts, args)` moves about 25 lines out of `main.luau`. The edge then reads the facts (common dir, uid, temp dir, the `--root` values) and passes them in. Nothing new is run against the machine.

Recommendation:
- Add `reap.scope({ main, uid, temp, roots }): { roots, scratch, sessionAnywhere }` to `reap.luau`, called by `reapRun`, and name it in the Design's interface list.
- reap.spec cases:
  - no `--root`: roots `{ main }`, the two `claude-<uid>/<slug>` prefixes and the two runner prefixes, and `sessionAnywhere = true`;
  - a `--root`: only that root, no scratch, and `sessionAnywhere = false`;
  - a main checkout path with a `.` in it (`/Users/me/code/pick.man`) gives `-Users-me-code-pick-man`.
- One case that runs `decide` over the incident fixture with `reap.scope`'s output (no hand-made options), so the default scope is shown to reach the incident.
- Rules rows (`run`): `sessionAnywhere` hard-coded either way; slug from `/` only; empty default roots.
- A docs.spec pin (or a check.sh AC; it is a rule, so a spec) that `reapRun` takes its options from `reap.scope`.

Lesson: zz-test/kill-mutants-where-the-value-is-built, zz-test/pin-fail-safes-where-they-act

### F3 [medium] Three readers of the same shell line disagree: `cd` tracking and here-document ownership are regexes over the raw text, not `split`'s reading, so each has holes both ways (the third time this mechanism has leaked, after round 3 F1 and round 4 F2/F6)
Where: ref-boundcmd `toolingMatch`, `string.gmatch(CTX.line, "%f[%w]cd%s+([^%s;&|)]*)")` over the whole raw command; `withoutHeredocs`, the owner of a body found by `string.match(before, "([^;|&]*)$")`; Design ("A `cd` in the line moves the folder…", refute 004 F6: "`cd ~`, `cd -` and `cd $X` go somewhere unknown and are refused").
Evidence (probe p1, checkout `/Users/me/code/pickman`, `cwd` the checkout):
- **The `cd` reading passes what the Design says it refuses:**
  - `cd "$X" && lune run tests/run -- a.spec.luau` → PASS. The operand `"$X"` keeps its quotes, so it is read as a folder inside the checkout.
  - `cd '/tmp/cr4' && lune run tests/run -- a.spec.luau` → PASS. That is the incident's scratch copy, spelled with quotes.
- **The `cd` reading refuses the gate's own spec runner:**
  - `lune run tests/run -- a.spec.luau; cd /tmp` → REFUSE `unbounded:lune`. A `cd` after the command still counts.
  - `echo "cd /tmp" && lune run tests/run -- a.spec.luau` → REFUSE. A `cd` inside a string counts.
  - Any `cd` text in a commit message or a here-document body does the same.
- **The here-document owner is cut at the `&` of a redirection** (round 3 F1's defect, in a second reader):
  - `bash 2>&1 <<'EOF'\nlune run x.luau\nEOF` → PASS. The shell's body is never read; without `2>&1` it is refused.
  - `python3 - 2>&1 <<'EOF'\nprint(1)\nEOF` → REFUSE "cannot be read".
  - `python3 - <<\EOF …` → REFUSE (a `\EOF` terminator is not recognised).

Critique: `split` already reads quotes, separators, redirections and order correctly. Every regex beside it re-learns one of those, and each round finds the next one it got wrong. The tempting fix is a better regex (strip quotes, anchor `cd` at a command start), which is still a second reader.

Consequences: if `split` returns each command's words (quotes removed) in order with its separators and its byte range, then:
- `cd` tracking walks those commands in order and applies a `cd` only to the commands after it. An operand that still holds `$`, `~` or a backtick after unquoting is unknown, which refuses the tooling match, as the Design says.
- Here-document ownership is the command whose byte range holds the `<<`.

The redirection scanner is then the only place `&` is decided.

Recommendation:
- Rebuild both on `split`'s output.
- Make the Design's sentence exact: "a `cd` moves the folder for the commands after it; an operand the scanner cannot resolve refuses the tooling match".
- boundcmd cases:
  - REFUSED: `cd "$X" && lune run tests/run`, `cd '/tmp/x' && lune run tests/run`, `bash 2>&1 <<E\nlune run x\nE`;
  - PASSING: `lune run tests/run -- a; cd /tmp`, `echo "cd /tmp" && lune run tests/run`, `python3 - 2>&1 <<E\nprint(1)\nE`, `python3 - <<\E\nprint(1)\nE`.
- Rules row: "the `cd` reading and the here-document owner come from `split`". Mutants: a `cd` after the target counted; quotes kept on the operand; `&` in `2>&1` ends the owner's segment.

Lesson: zz-test/one-rule-one-function, zz-arch/guards-decide-from-the-tools-resolution

### F4 [low] The background rule's "ends by itself" list refuses routine set-up commands, and its operand count lets stdin readers through
Where: ref-boundcmd `TRIVIAL`, `FILTER_MIN` and `operands`; the Design's background sentence (its list ends in "...").
Evidence (probe p3, `background = true`):
- REFUSED, though each ends at once:
  - `mkdir -p .cache && z-nile/check.sh --full > .cache/full.log 2>&1`;
  - `rm -f log; ./zn land > log 2>&1`;
  - `[[ -d x ]] && ./zn land > l 2>&1`;
  - `while read l; do echo "$l"; done < f`, though the Design says "`while read`, which ends at the end of its input".
- PASSING, though each reads the shell's stdin, which never closes in a background call (the foreground form has `< /dev/null`; the background one does not, as the live 62384 shows):
  - `cat > out.txt` and `grep x > out.txt`: the redirect target is counted as an operand;
  - `head -n 5`: the option's value is counted.

Recommendation:
- Add `mkdir`, `rm`, `rmdir`, `cp`, `mv`, `touch`, `ln`, `chmod`, `[[`, `]]`, `read`, `basename`, `dirname` and `realpath` to TRIVIAL.
- Skip a word after a bare `>`/`>>`/`<` and the values of `-n`/`-c`/`-e`/`-f` in `operands`.
- Cases on both sides as above.

### F5 [low] The reaper's stop step still re-reads `lstart` once per process and counts poll steps, not wall time, and its KILL skips the identity check (repeat of design-review-004 F4, in part)
Where: ref-main-luau `reapRun`:
- `for _, pr in tree do sh.run("ps", { "-o", "lstart=", "-p", pid })`;
- `for _ = 1, 20 do … sh.run("sleep", {"0.1"}) end`;
- `kill -KILL` on `left`.

Also the Design's edge paragraph ("so the time does not grow with the number of processes: about three seconds") and Scalability ("two `ps` … a few `kill`s").
Evidence:
- The re-read spawns one `ps` per process of every target tree before any TERM. That is the N-dependent cost round 4 named; refute 004 changed only the poll.
- Each poll step is two process starts plus 0.1 s, so under the gate's load the 20 steps take longer than the "two seconds" of wait the Design describes.
- The KILL two or more seconds after TERM goes to pids last checked by `stat`, not by `lstart`.

Recommendation:
- Re-read with one `ps -o pid=,lstart= -p <all ids>`.
- Make the poll read `pid=,stat=,lstart=` and keep a pid only when its `lstart` is unchanged.
- Bound the wait by a wall-clock deadline (`os.clock`/`os.time` taken before the TERM).
- Correct the Design's two sentences.
- Rows `reasoned` or `run` as round 4 asked.

Lesson: zz-test/count-calls-in-poll-loops, zz-arch/read-paired-facts-at-one-moment

### F6 [low] Other preps in flight that touch the same files are not named, and step 2's "apply `ref-settings.json.txt`" would drop c0194's hook
Where: Chore checklist, "Other preps in flight" (c0132, c0157, c0165, c0166, c0180 only); Implementation step 2; Design "`.claude/settings.json` … (`ref-settings.json.txt` has the whole file)".
Evidence:
- The Touched lists of the prep worktrees, searched with `awk '/^### Touched modules/,/^### /' <doc> | grep -E 'zn$|z-nile/check.sh|fence.luau|settings.json|AGENTS.md|main.luau|zz-test|scripts/hooks|z-nile/lib'`:
  - **c0194** (reviewed): `.claude/settings.json` (a `SessionStart` hook, "edit by hand: add the key, no reformatting"), `z-nile/check.sh`, `main.luau`, `fence.luau`, zz-test, AGENTS.md, and a pre-engine branch in `zn` for `./zn tmp`. That is the same lines as c0191's `run` branch.
  - **c0181**: `main.luau`, `check.sh`, AGENTS.md.
  - **c0178**: `fence.luau`, zz-test.
  - **c0123**: zz-test.
- c0194 also moves the runner's temp folder to `<home>/.cache/.tmp/pickman-run.*` and agents' clones to the main checkout's `.cache/.tmp/`. That puts them inside the reaper's root, which narrows the stated "gap" (clones in `$TMPDIR`) and leaves the `<TMPDIR>/pickman-run.` prefixes dead. Its document says "c0191 (draft): its backstop reaper may call `./zn tmp sweep`".
- `ref-settings.json.txt` is the base file with two keys added and the existing hook blocks reformatted. If c0194 lands first, copying it loses the SessionStart entry. Only c0194's promoted `callers.spec` would notice, at the full gate.

Recommendation:
- Step 2: "add the `PreToolUse` and `SessionEnd` keys of `ref-settings.json.txt` to the file as it is on the branch; never copy the file".
- Add c0194, c0181, c0178 and c0123 to Other preps with their overlap: the `zn` pre-engine branch (both add one; keep both), the settings keys, the temp folders and the gap sentence after c0194.

Lesson: z-design/quote-other-preps-before-promising

### F7 [low] The evidence put to the user for the Python decision still mislabels two refusals, and the background reading of clean inline Python is not written down
Where: Design "Decided with the user" item 1 ("13 Python files (the agent's mutation-runner scripts, rightly) and 2 more started in the background"); E15 ("`background:python3` 2 (the agent's mutation runner, started in the background)").
Evidence:
- `grep '"background":true' calls.jsonl | grep python3` gives two calls. Both are `python3 - <<'EOF'` edits of `z-nile/.tracker/issues/c0180/c0180.md` (`s.replace(old,new)`), not mutation runners. Round 4 F2 said so, and refute 004 says the text was fixed.
- The scan passes them, and so does a background `perl -e 'print 1'`. Both are refused only because `python3` and `perl` are not in the background rule's list, so "anything else passes" (item 1) does not hold for background calls.

Recommendation:
- Relabel the two calls in both places ("two inline edits started in the background: refused by the background rule, not the scan").
- Add one sentence: "in a background call an inline script is refused like any interpreter; run it in the foreground or wrapped".
- Add a boundcmd case pinning that reading.

Lesson: z-design/decided-guesses-rewrite-their-body

### F8 [low] Two smaller mismatches: round 4's candidate lesson is not in harvest.md, and Claude Code's `grep` runs as `ugrep`, which the orphan rule does not name
Where: harvest.md (one `note` line, round 3's); design-review-004's "Candidate lesson for the lead"; ref-reap ORPHANABLE and CHAIN; reap.spec "a killed monitor's `tail`/`grep`"; Design decision 4 ("the orphaned `sleep`, `tail`, `gh`, `grep`, `watch` … are leaks").
Evidence:
- harvest.md has no `- note design-review-004 candidate: …` line for "ownership by ancestry, folder scope only once the owner is gone". This is round 4 F10's defect again.
- This session's shell snapshot (lines 381-410) defines `function grep` and `function find`. They run the `claude` binary as `ARGV0=ugrep` and `ARGV0=bfs`. The live leak round 4 found shows in `ps` as `ugrep -G --ignore-files … -c ^git repack` (pid 63274, still running).
- So the "grep" a tool shell or monitor leaves is named `ugrep`. `reap.name` gives `ugrep`, which is in neither list, so an orphaned one stays. Its shell's tree still takes it while the shell is alive.

Recommendation:
- Add the note.
- Add `ugrep` and `bfs` to ORPHANABLE and CHAIN, and add them to the Design's list of Claude-dependent facts (they fail closed).
- Change reap.spec's monitor case to `ugrep …`.

Other checks:
- Scope fidelity: every other captured outcome keeps a Design and a Checked criterion:
  - runner: AC1, with the parent's death as exit 123;
  - hook: AC2;
  - reaper: AC3 and AC4, with SessionEnd wiring in AC2's settings case and the gate and sync call sites in AC6;
  - spec runner CPU limit: AC5;
  - docs: AC6.
  - F1 is the half-outcome without one. No Recommendation here narrows an outcome; F1's options go to the user.
- The Non-goal "other repositories": the session rule now stops a session's shell in another repository. The Design calls this its reading and says the lead is told. It is consistent with the Problem ("No process a session starts can outlive it"). The lead should confirm that the user heard it.
- Repository safety holds:
  - reap-e2e signals only after a dry run that named something and nothing outside `$W/in`, and `--root` still switches off the default scope, the session rule's reach included;
  - the jail string's `cpu.sh` step only lowers;
  - the two `ALLOWED` entries are narrow;
  - `--auto` is a no-op under ac.sh's fence;
  - no spec writes outside `.cache`.
- Could anything stop a process that is not a leak?
  - Read only, on this machine: no `lune`/`git`/`sh`/`perl`/`node` of this user sits at PPID 1 now.
  - Hooks (`bash …/stop.sh`) and Claude's `caffeinate -i -t 300` are direct children of `claude` that are not tool shells, so the session rule keeps them.
  - The credential helper is `osxkeychain` (no long-lived `git` daemon).
  - Nothing in `scripts/`, `zn`, `z-nile/lib`, `z-nile/engine` or the test library detaches on purpose (`git grep -n -E "nohup|setsid|disown|daemon|--detach"`: only `worktree add --detach` and a comment).
  - What remains is the decided `/clear` reach (subagents' in-flight calls included) and F1.
- Settings: `boundcmd.spec`'s settings case is red until the executor's step 2 (prototype run: 28 passed, 1 failed, that case). Accepted as stated.

Verdict: changes
