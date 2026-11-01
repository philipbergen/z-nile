# Review 002: c0191 (design mode)
Inputs: prep worktree at de3ad691 plus its uncommitted prep files (c0191.md, check.sh, acceptance/ 8 files, experiments/ref-*, design-review-001.md, design-refute-001.md, harvest.md); the prototype in `.worktree/proto-c0191` (its `boundcmd.luau`, `reap.luau`, `bounded.pl`, both hook scripts and all eight acceptance files are byte-identical to the `ref-*` files and acceptance/; its check.sh is round 1's); zz-review, z-design (+ checklists/chore.md), zz-arch, zz-test; `./zn lessons --when design`; the prep documents of c0132 (sweeper-killed-under-load), c0157 (gate-contention), c0165 (reuse-test-results), c0166 (relevant-review-lessons) and c0180 (hybrid-inprocess-gate); the Monitor tool's schema as this harness loads it.
Capture: `./zn capture c0191` prints 58b946db (the template). The real text came in b7b14ea1. The document's Problem, Non-goals and Solution match b7b14ea1 word for word, plus one "Prep detail" paragraph.
Dropped from design-review-001: none. Round 1's F2, F3, F5, F6, F7, F9, F10, F11 (except as F11 below), F12, F13, F14, F15, F16, F17, F18 and F20 hold against the documents, specs and reference code. Where a round-1 fix only partly holds, the new finding says so.
Probes: pure calls into copies of the prototype's `boundcmd.luau` and `reap.luau`, plus a copied `zn` with one mutant line, all run in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/c0191-review-r2/` (`probe.luau`, `eng/`) under a 30 to 60 s alarm. Nothing was signalled and no spec was run.

### F1 [high] The backstop never stops the leak class round 1 found running on this machine: a loop runs in the tool shell itself (`zsh`), and its children (`sleep`, `gh`, `grep`, `node`) are not in TARGETS, so neither the session-end rule nor the orphan rule takes them
Where: Design, `reap.luau` (rule 3 "its program is one of TARGETS", rule 2 "its program is one of TARGETS"); ref-reap.luau lines 48, 332, 334; reap.spec "a session that is ending takes what its own tool shells started" (it pins `node editor.js` below a tool shell as **kept**); Problem, "What should happen", bullets 2 and 3.
Evidence: E11's loops are `/bin/zsh -c source …/shell-snapshots/… eval 'until …; do …; sleep 30; done'`. The loop runs in the tool shell; its children are `sleep` and `gh`/`grep`. A pure probe with that shape (claude 100 → tool shell 200 running the `until` → `sleep` 300 and `gh` 400, cwd in the root, 4.6 days old) gives:
```
session-end targets: 0
after claude exits, orphan targets: 0
```
`belowToolShell` is true for all of them. But `TARGETS` is `{lune, git, sh, bash, perl}`, so the tool shell (`zsh`), `sleep`, `gh`, `grep`, `node` and `python3` are never targets. After `claude` exits, the orphaned `zsh` fails rule 2's name test the same way. reap.spec makes this a sequestered expectation: `editor = node editor.js` below the tool shell must survive the session end (`toEqual({ 4000 })`).

So a loop, a follow or a background `node`/`python3` that gets past the hook outlives its session for good. The hook fails open on purpose, has the bypasses in F4 and F8, and only sees calls made after the settings change. The Design says "the reaper is the backstop for what it misses". It is not, for exactly this class.
Critique: outcome 2 ("every such command stops when the agent or session that started it ends") and outcome 3 ("a backstop finds any that still escape") are met only for five program names. The tempting fix is to add `zsh`, `sleep`, `gh` and `node` to TARGETS. That is a program list again, and the next `tail`, `caffeinate` or `npx` slips through.
Consequences:
- At a session end, ancestry is already the proof of ownership. Taking every program below the session's own tool shells (the tool shell itself included) also takes, on `/clear`, every still-running background task of the cleared conversation. The Design already accepts that for TARGETS.
- A macOS application started directly from a tool shell (`/Applications/X.app/Contents/MacOS/X`) would be taken too. Keep the `.app/Contents/` and legit-git exceptions.
- An agent running `./zn reap --session-end` by hand keeps its own tool shell, because it is in `self`. The session's other tool shells (its background tasks) are taken: say so in the usage text.
- The orphan rule then needs `zsh` among the names it may take. That covers a tool shell orphaned when `claude` died with its loop still running. `ownerless` already keeps a terminal's login `zsh` (its parent is `login`, tmux or an app).
- The folder scope: under the session rule a probe the session started in `/tmp/x` is still its own work. Decide and record whether the session rule keeps the folder scope (the Non-goal excludes other projects' processes, not this session's).
Recommendation:
- Rule 3 takes the whole tree of each tool shell of the ending session, the shell included, whatever the program, except `.app/Contents/` and anything at or below a legit git.
- Rule 2 adds `zsh` to the names an orphan may have (its tree goes with it).
- reap.spec, changed in prep:
  - the E11 shape (a tool shell running `until` with a `sleep` child) is taken at session end with its tree;
  - `node editor.js` below a tool shell is taken (flip the current expectation);
  - an orphaned tool shell at PPID 1 older than `minAge` is taken;
  - a login `-/bin/zsh` below `login` is kept;
  - an `.app` binary below a tool shell is kept.
- reap-e2e: the fake tool shell decoy runs a `while` loop itself, with a `sleep` child, and both are gone after the real step.
- New Rules rows: "session rule takes any program below a tool shell" (mutant: TARGETS filter kept) and "orphaned tool shell" (mutant: `zsh` not a target).
Lesson: z-design/never-narrow-captured-scope

### F2 [high] AC5's "ZN_ENGINE_CPU (default 1800 s)" can be passed by a `zn` with no default at all: inside the jail every case expects `min(1800, 1200)`, which the jail's own limit supplies
Where: engine-cpu.spec "the engine gets 1800 CPU seconds by default" and "a bad value falls back to 1800"; Rules row "the engine has a CPU limit (default 1800) | engine-cpu :: default, spins | the ulimit removed | run".
Evidence: the spec runs in the jail, whose shell now sets `ulimit -t 1200`, so `own()` is 1200. Both cases expect `math.min(1800, own()) = 1200`. A `zn` that only lowers keeps an inherited 1200 whatever its default. I ran a copy of the prototype's `zn` with one changed line, `lim=${ZN_ENGINE_CPU:-86400}` (and `|| lim=86400`), against a stub engine that prints `ulimit -t`:
```
under 1200, ZN_ENGINE_CPU= -> 1200
under 1200, ZN_ENGINE_CPU=abc -> 1200
under 1200, ZN_ENGINE_CPU=90 -> 90
no inherited limit, unset -> 86400
```
So the mutant passes every engine-cpu case. The "spins" case sets `ZN_ENGINE_CPU=2`, so it never reaches the default. In a live session (no inherited limit) that mutant leaves the engine with 86400 s. That is round 1 F4's outcome, an engine loop that ends instead of spinning for the session's life, now unchecked. The row's "the ulimit removed" mutant dies only through "spins".

runner-cpu does not share the defect: the outer runner is the same `fence.luau`, so a mutated default changes the outer limit too, and the case sees it.
Critique: a lower-only setter cannot be observed under an equal or lower inherited limit, and every spec runs under one. Running the case from check.sh doesn't help either: under `./zn check` the outer real `zn` gives 1800, so the same mutant shows 1800.
Consequences: the fix has to observe what `zn` asks for, not what the process ends up with.
Recommendation:
- In engine-cpu.spec, run the copied `zn` with `BASH_ENV` pointing at a fixture file that defines a `ulimit` shell function (`zn` is `#!/usr/bin/env bash`, so a non-interactive bash reads `BASH_ENV`).
- The function answers the read (`ulimit -t`) with a value the case chooses (`unlimited`, or `100`) and appends every set (`ulimit -t N`) to a log. It answers only those two forms and fails on anything else (zz-test/stand-ins-answer-only-named-arguments).
- Cases:
  - unset, read `unlimited` → set 1800;
  - `abc` → 1800;
  - `90` → 90;
  - read `100` with `ZN_ENGINE_CPU=500` → no set.
- Keep "spins" as the real-limit case.
- Rules rows: "default 1800" (mutant: default 86400 or none) and "bad value falls back to 1800", both `run`.
Lesson: zz-test/pin-call-site-arguments, zz-test/no-vacuous-pass

### F3 [high] `Bash(./zn run:*)` in `permissions.allow` lets every command run without a permission prompt, as long as it is wrapped
Where: ref-settings.json.txt `"Bash(./zn run:*)"`, `"Bash(./zn reap:*)"`; boundcmd.spec settings case (requires both); AC2 ("allows `./zn run` and `./zn reap`").
Evidence: the allow list today names only read-only or bounded commands (`./zn list`, `find`, `members`, `check`, `metrics`, `lune run tests/run:*`, formatters). A prefix rule `Bash(./zn run:*)` matches `./zn run -- sh -c 'git push --force origin main'`, `./zn run -- rm -rf …` and `./zn run --time 5 -- gh pr merge …`. Claude Code checks `&&`/`;` parts one by one, but this is one command with an allowed prefix.

The hook's refusals send agents to exactly this prefix for every probe, loop and background call. So the wrapper becomes the routine way past every permission prompt the user has kept. `Bash(./zn reap:*)` likewise lets an agent run real reaps with any option, unprompted. E8 records the classifier refusing exactly such a run as correct.
Critique: an authority hole created by the settings this issue writes, and pinned by a Checked criterion. The tempting fix is a narrower prefix such as `Bash(./zn run --time 60 -- lune run:*)`. It matches only one spelling, and agents vary `--time`.
Consequences: without the allow entry, every wrapped command prompts unless the user approves it in the session. That is the same prompt the bare command would have raised, so the hook adds no new prompts beyond the wrapping. Whether to auto-allow the wrapper is the user's decision, not prep's.
Recommendation:
- Remove both entries from the reference settings and from the settings case.
- The case asserts that no allow entry starts `Bash(./zn run` or `Bash(./zn reap` (except `Bash(./zn reap --dry-run:*)`, if wanted).
- AC2's text drops "allows `./zn run` and `./zn reap`".
- If auto-allowing the wrapper is wanted, escalate to the user: allow `./zn run:*` (every wrapped command unprompted), or prompt per command (the status quo for the bare forms). Record a `Decided with the user` line.

### F4 [medium] The loop and here-document rules miss ordinary spellings: a loop after `then`, `do`, `else`, `!` or `time`, a C-style `for ((;;))`, a shell fed a here-document, and every line after a `<<` that is not a here-document all pass (repeat of the mechanism round 1 F1 found holes in)
Where: ref-boundcmd `checkCommand` (`words[1] == "while"` only), `resolve` (KEYWORD skips `while`/`until`, PREFIX skips `time`), `withoutHeredocs` (matches `<<word` anywhere, quotes and `<<<` and `$((…<<…))` included); Rules rows "loops … refused", "here-document bodies are data".
Evidence: `boundcmd.check` on the prototype, each `ok = true`:
- `if true; then while true; do sleep 1; done; fi`
- `for x in a; do until false; do sleep 1; done; done`
- `time while true; do :; done`
- `! until false; do sleep 1; done`
- `for ((;;)); do sleep 30; done`
- `bash <<'EOF2'` / `while true; do :; done` / `EOF2`
- `grep x <<<abc` / `lune run spin.luau`
- `echo $((1<<2))` / `lune run spin.luau`
- `echo '<<X'` / `lune run spin.luau`

The last three show that a `<<` that is not a here-document hides every later line, including a bare `lune run`.
Critique: this is the second round in which the classifier's coverage is the hole. Patching spellings one by one is the pattern round 1 warned about. With F1 fixed, the backstop no longer depends on the classifier, so its misses become a cost (a leak that lives until the session ends) rather than a permanent leak.
Consequences: the classifier stays a seatbelt. The Design should say so, list what it does not read, and point at the session rule (F1) as what catches those.
Recommendation:
- `checkCommand` looks for `while`/`until` among the leading keywords and prefixes before the program (`then`, `do`, `else`, `elif`, `!`, `time`, `{`), not only in `words[1]`.
- `for ((` with an empty condition is a loop.
- A here-document whose command is a shell without `-c` (`sh`, `bash`, `zsh`, or `-s`) or an interpreter reading stdin has its body checked as commands.
- `withoutHeredocs` recognises `<<` only outside quotes and `$((…))`, and never `<<<`.
- REFUSED cases for each form above; ALLOWED cases `echo $((1<<2)); echo ok`, `cat <<<x`, `cat <<'EOF'` with a loop as its body.
- One Rules row per rule, with the mutant "keyword skip swallows `while`".
- zz-test's "Bounded commands" lists what the classifier does not read.
Lesson: zz-arch/guards-decide-from-the-tools-resolution

### F5 [medium] The hook refuses routine, self-ending commands: `… | while read …` pipelines, `yes | head`, the absolute path of the gate's runner, and the background `until` wait that Claude Code's own tool guidance recommends
Where: ref-boundcmd `checkCommand` (any `while`), FOLLOWERS (`yes`), `normalise` (relative paths only); the `loop` message.
Evidence:
- Prototype verdicts:
  - `git ls-files | while read -r f; do echo "$f"; done` → refused (loop);
  - `n=$(git log --format=%s | while read l; do echo x; done | wc -l)` → refused (loop);
  - `yes | head -3` → refused (follow);
  - `lune run /Users/philipbergen/code/pickman/z-nile/tests/run -- x` → refused (unbounded).
- A `while read` loop ends at the end of its input. `yes | head` ends at once.
- The Monitor tool's own description in this harness tells agents, for "tell me when X is ready", to use "Bash with `run_in_background` and … `until grep -q "Ready in" dev.log; do sleep 0.5; done`". The hook refuses that form twice over (loop and background).
- The refusal's wrapper, `zn run --time <seconds> -- sh -c '<loop>'`, breaks as soon as the loop contains a single quote, which pipelines with `printf '%s'` or `awk '…'` usually do.
Critique: every one of these costs a refused call and a hand-quoted retry, in every session and subagent. That pressure is what makes agents disable a hook.
Consequences: passing `while read` needs the loop's condition to be `read` (with options), the input-bounded form. A `tail -f x | while read` is still refused by the follow rule on `tail`.
Recommendation:
- Pass a `while`/`until` whose condition is `read …`.
- Pass `yes` whose output is piped to `head`.
- Normalise an absolute `TOOLING` target by its suffix inside `ZN_CHECKOUT`.
- Give the loop message a quoting-safe form: write the loop to a file in the scratch folder and run `<zn> run --time N -- bash <file>`.
- ALLOWED cases for the four commands above.
- A refusal-text case asserting the message names the file form.
- Record in the Design that the harness's own Monitor/Bash guidance recommends the refused background `until`, and what the agent sees instead.

### F6 [medium] The background rule passes a call if any one command in it is bounded, so `./zn list; perl -e '1 while 1'` runs in the background unbounded
Where: ref-boundcmd `check` (`sure = sure or boundedish(words)`); Design "a call in which no command is the gate, …".
Evidence: with `background = true`:
- `./zn list; perl -e '1 while 1'` → ok;
- `./zn list && sleep 99999` → ok;
- `sleep 600` → refused (as intended).
Critique: one innocuous `./zn` or check.sh in a background call whitelists everything else in it.
Consequences: requiring every command to be bounded must still pass the gate's real forms: `cd <wt> && z-nile/check.sh --affected 2>&1 | tail -20` and `z-nile/check.sh --full > log 2>&1; echo done`.
Recommendation:
- A background call passes only when every simple command in it is boundedish or one of a short named list of commands that end by themselves: `cd`, `echo`, `printf`, `export`, `true`, `:`, `tee`, `head`, `tail` without a follow, `grep`, `sed`, `wc`, `sort`.
- boundcmd cases for both sides: the two calls above refused, and the three gate forms passing.

### F7 [medium] Follows are allowed in Monitor because "its timeout ends it", but the Design's own premise is that the expiry kills only the shell, so `tail -f … | grep` and `gh run watch` outlive the monitor for good
Where: Design "What prep found" ("when a monitor expires the harness kills its shell, which orphans a Lune child the way E4 shows"); boundcmd `not CTX.monitor and FOLLOWERS(...)`; the Monitor case in boundcmd.spec.
Evidence:
- The Monitor tool's schema in this harness: `command` (string), `timeout_ms` capped at 1,800,000. It says "Every monitor expires after `timeout_ms` …: it is killed".
- If "killed" means the shell pid only (the Design's premise), a `tail -f log | grep --line-buffered X` leaves `tail` and `grep` running. `tail` blocks on the file and never gets SIGPIPE while `grep` lives.
- Neither name is a reaper target, so even F1's fix catches them only at the session end.
- A loop in Monitor is fine either way: it runs in the killed shell itself.
Critique: the exception rests on the opposite of the premise the interpreter rule uses for Monitor. The schema read settles U1's payload question (`tool_input.command`), but not this one.
Recommendation:
- Add to U1 a pass/fail experiment: does Monitor's expiry kill the command's process group? (Run `tail -f <scratch file> | grep --line-buffered x` with `timeout_ms: 5000`, then `pgrep -f` the unique file name.)
- Fallback when it does not: follows in Monitor are refused unless under `<zn> run --time` at or below the monitor's timeout, and the boundcmd case moves `tail -f` and `gh run watch` from Monitor-ALLOWED to REFUSED.
- Record the result and the branch taken in the Design.
Lesson: z-design/fallbacks-name-the-modes-they-cover

### F8 [medium] "Refuses by class, not by program list" is not what the classifier does: Perl one-liners (this repository's own probe language), shell scripts, `npm`/`npx`, `caffeinate -t N <cmd>` and `bash -c -- '…'` all pass
Where: Design decision 2 ("refuses by class, not by program list"); the `boundcmd` paragraph ("prefix commands (… `caffeinate`, …)"); ref-boundcmd `INTERPRETERS`, `PREFIX` (no `caffeinate`), the `-c` scan.
Evidence: prototype verdicts, each `ok = true`:
- `perl -e '1 while 1'`
- `bash probe.sh`
- `npm run dev`
- `npx tsx probe.ts`
- `caffeinate -t 5 lune run spin.luau` (`caffeinate` is handled as a program, and `-t` passes it without looking at the command it runs; the Design lists it as a prefix)
- `bash -c -- 'lune run spin.luau'`

E1, E4 and bounded.spec themselves use `perl -e '1 while 1'` as the spinning probe.
Critique: an agent reading "refuses by class" will trust a pass. The Design must say what passes.
Consequences: refusing every `perl -e` would refuse the many bounded `perl -pi -e` and `perl -e 'print …'` edits agents run (ALLOWED pins `perl -e 'print 1'`). That is a trade-off to record, not to guess.
Recommendation:
- Treat `caffeinate` as a prefix whose `-t` bounds only itself, so the command it runs is judged.
- Skip `--` after `-c`.
- Correct decision 2's wording to "a named list of interpreters, loops, follows and detachers".
- List in zz-test's "Bounded commands" what passes (`perl`, shell scripts, `npm`/`npx`/`make`, `awk`), with F1's session rule as what stops them.
- Decide `perl -e` explicitly: refuse a `perl -e/-E` whose text holds `while`/`until`/`for(;;)`/`redo`, or leave it to the session rule. Record which.
- REFUSED cases for `caffeinate -t 5 lune run x` and `bash -c -- 'lune run x'`.

### F9 [medium] The captured runner "stops the whole group … when its parent dies"; the Design neither builds nor decides it, and an orphaned runner escapes the session-end rule
Where: Solution (captured, b7b14ea1): "It stops the whole group on timeout, on its own exit, and when its parent dies."; Design `bounded.pl` (the watchdog covers only the runner's own death); the "Limits of the design" list (silent).
Evidence:
- `./zn run --time 3600 -- lune run p.luau &` inside a foreground call: the tool shell exits at once, and the runner is a PPID-1 `perl` running its command for up to an hour.
- At that session's end it is no longer below a tool shell. Pure probe: claude 100, runner 500 at PPID 1, 30 s old, `under = 100` → `targets: 0`.
- Only the orphan rule takes it, after 60 s and only when a later `sync`, gate or session end runs.
- The hook passes the call (`./zn` is boundedish).
Critique: a Solution idea is z-design's to decide, but the decision has to be in the document. Silence reads as built.
Consequences: a parent-death stop (the runner polls `getppid()` with its alarm, or the watchdog does) makes `<zn> run … &` from a foreground call die as soon as the call ends. The hook would then refuse `zn run … &` outside `run_in_background` and say so.
Recommendation:
- Decide and record which of these holds:
  - (a) the runner stops its group when its parent becomes 1. bounded.spec case: the runner's parent `sh` exits, and the command is gone within 3 s. boundcmd case: `./zn run --time 60 -- x &` in a foreground call is refused with the `run_in_background` advice.
  - (b) the orphan rule is the stop for an orphaned runner. The `Limits of the design` line says so, with a reap.spec case for a PPID-1 `perl …/bounded.pl` in scope.
- Either way, add a Rules row.
Lesson: zz-arch/children-need-a-lifeline

### F10 [low] Text that disagrees with the reference code or with itself
Where: Usability; decision 8 and `reap.luau`'s scope paragraph; the `boundcmd` paragraph; Design decision 4; AGENTS.md draft.
Evidence:
- Usability says "`--time must be 1..900`"; the runner says 1..3600.
- The Design says the runner's folders are found "under `$TMPDIR`"; ref-main-luau uses `getconf DARWIN_USER_TEMP_DIR`. Equal on this machine today, not in general.
- The Design lists `caffeinate` among prefix commands; the code doesn't (F8).
- The session rule depends on three unversioned facts, and each fails closed silently:
  - the slug rule: the Design says `/` and `.` become `-`. If Claude Code replaces every non-alphanumeric character, a path with `_` or a space keeps the session folders out of scope;
  - the snapshot path `/.claude/shell-snapshots/`: it moves with `CLAUDE_CONFIG_DIR`;
  - the process name `claude`: an npm install shows `node …/cli.js`, so `sessionRoot` is nil.
- The AGENTS.md draft says the hook "refuses a bare `lune run` of a probe", under-stating loops, follows and background calls.
Recommendation: fix the three texts; name the three dependencies in zz-test's "what each cannot do"; extend the AGENTS.md sentence.

### F11 [low] Who adds c0165's `z-nile/specs` to `TOOLING` depends on landing order, and c0165's reviewed document doesn't know
Where: Existing work ("c0165's executor adds the entry to `TOOLING`").
Evidence: c0165's prep document (reviewed) adds `lune run z-nile/specs -- run|record|digest` and never mentions `TOOLING`. If c0165 lands first there is no `TOOLING` to edit. If c0191 lands first, c0165's executor has nothing telling it to.
Recommendation: "whichever lands second adds `z-nile/specs` to `TOOLING`, with a boundcmd ALLOWED case". Put that sentence in this Design, and tell c0165 (its prep or a capture).
Lesson: z-design/quote-other-preps-before-promising

### F12 [low] reap-e2e's work folder is fixed and removed at start, and AC4 runs outside the runner's lock
Where: reap-e2e.luau `WORK = …/.cache/reap-run`, `fs.removeDir(WORK)`.
Evidence: two `./zn check c0191` in one checkout (a reviewer's and the author's) remove each other's `in/` folder. Every `WAIT` loop then ends, and the cases fail at random. AC4 is not under `tests/run`, so the runner's lock doesn't serialise it.
Recommendation: `WORK = …/.cache/reap-run-<pid>-<random>`.

### F13 [low] The session-end reap polls its targets one after another, up to about 2.3 s each, inside a 20 s hook budget
Where: ref-main-luau `reapRun` (TERM, 20 × 0.1 s polls, KILL, 0.2 s per target).
Evidence: nine TERM-ignoring trees take past 20 s. The harness then kills the hook mid-reap: the rest are neither stopped nor logged, and the engine's Rokit shim is killed while its Lune child goes on (E4).
Recommendation: TERM every target's pids first, poll them all together for one shared 2 s, then KILL the rest. A Rules row "one grace for all targets".

### F14 [low] Round 1's F19 and F20 fixes have no Rules rows and no cases
Where: Rules and mutants; ref-main-luau `guarded(quiet)`, `reapRun` (`--quiet` problems, non-macOS exits).
Evidence:
- No row or case pins any of these:
  - a later non-quiet `guarded()` still prints the message after a quiet one;
  - `--quiet` folds unreadable lines into one `reap: skipped (N unreadable ps lines)`;
  - an explicit `reap` off macOS exits 2.
- docs.spec only finds the text `guarded(true)`.
Recommendation: add the three rows; pin them as pure cases where possible (move the problem folding into `reap.luau`), otherwise mark each `reasoned` with why.
Lesson: z-design/spec-design-correspondence

Lessons pass:
- Asked of the draft:
  - pin-call-site-arguments and no-vacuous-pass: F2;
  - guards-decide-from-the-tools-resolution: F4;
  - fallbacks-name-the-modes-they-cover: F7;
  - children-need-a-lifeline: F9;
  - never-narrow-captured-scope: F1;
  - quote-other-preps-before-promising: F11;
  - spec-design-correspondence: F14.
- The design applies guard-no-is-explicit, read-paired-facts-at-one-moment, new-commands-run-in-a-copy (the dry-run gate holds: the `--auto` and real steps both carry `--root`, and only decoys' descendants share a tree), refusals-tested-on-both-sides and specs-set-host-markers-explicitly.
- `harvest.md` adds no new lesson. It maps round 1 to existing lessons (sources) and four one-offs, which are fair.

Other checks:
- Lower-only limits compose in every nesting I traced:
  - tool shell → `./zn run --cpu N` (N);
  - `./zn check` (1800) → jail (1200) → AC4's `./zn run --time 180` (180);
  - `./zn run --time 600 -- lune run tests/run` (600 kept by the jail);
  - pre-bash (2); session-end (15) → `zn` (15 kept).
  - bash's `ulimit -t` sets the hard limit too, which is what makes "only lower" necessary. It is consistent.
- Exit codes 124 and 125 are used nowhere else in the repository's shell or Lune code: `git grep -nE '(== |-eq |code == |\$\? ?(==|-eq) ?)12[45]\b|exit 12[45]\b|\b12[45]\)' -- '*.sh' '*.luau' zn scripts | grep -v /c0191/` prints nothing, and `ac.sh` treats any non-zero status as FAIL.
- `size: 1550` is a raft by itself under z-raft's cap, which is allowed. F1 and F2's fixes add little.
- Overrides: none is right. c0119's scope-docs pin (`10. **Lessons**` before `11. **Scope fidelity**`) and c0114's settings pins hold with item 12 and the added hook groups.

Verdict: changes
