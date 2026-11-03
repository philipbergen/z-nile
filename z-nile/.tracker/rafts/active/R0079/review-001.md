# Review 001: R0071 (code mode)
Inputs: HEAD fd1ec27e7cb5e97310f1868ae6b332945d4d5478 (branch R0071-no-leaked-processes), origin/main 98d27014; `git diff origin/main...HEAD` (25 files); c0191.md (Problem, Decisions, Design, ACs, Verification log), c0191 `check.sh` and `acceptance/`, `experiments/ref-*.txt`; R0071.md and `check.sh`; zz-review, zz-arch, zz-test, zz-rules skills; `./zn lessons --skill zz-review --full`, `./zn lessons --when build`.

What I ran (every probe through `./zn run`):
- `./zn run --time 900 -- ./zn check c0191`: 6/6 PASS (AC1-AC6).
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing; `git diff --summary` has no `mode change`.
- `.claude/settings.json` against main and against `experiments/ref-settings.json.txt` (JSON, sorted): the only changes are the `PreToolUse` group (matcher `Bash|Monitor`, `pre-bash.sh`, timeout 10), the `SessionEnd` group (`session-end.sh`, timeout 20) and `Bash(./zn run:*)`; both hook groups equal the reference; Stop, PostToolUse and every other allow entry are untouched; no `./zn reap` entry. Matches the Design exactly.
- `./zn reap --dry-run` (default scope, this machine): `reap: no leaked processes`. `./zn reap --dry-run --session-end` with a `./zn run --time 40 -- sleep 35` background call of mine running: one line, `would stop pid … +3 child(ren) … started by the session that is ending … /bin/zsh -c source …/shell-snapshots/…` (only that tool shell; the reaper's own shell was not named).
- `scripts/hooks/pre-bash.sh` fed 9 payloads: `lune run x.luau` exits 2 with the checkout's own `…/zn run --time 60 -- lune run x.luau`; Monitor `tail -f`, a background `sleep`, non-JSON, empty, numeric command, string `tool_input`, non-UTF-8 all exit 0; a 400 KB command exits 0 in 0.21 s; typical calls 0.02-0.03 s. Fails open and is fast.
- About 110 commands through `boundcmd.check` (scratch Lune script requiring the branch's module): the gate, `./zn land 2>&1 | tail` (foreground and background), `gh pr create --body "$(cat <<'EOF' … lune run … EOF)"`, commit messages, the merge procedure's `../zn run --time 1800 -- lune run scripts/cicd` and `PICKMAN_FENCE_REAL_GIT=… z-nile/check.sh --full > full.log 2>&1` (background) all pass; the incident line, loops, follows, detachers, `bash -c`/`eval`/heredoc-fed shells, `( )`/`{ }`/`time`/`command`/`!`/`xargs` prefixes refuse. Exceptions are F2, F4, F5 below.
- Fence and limits: every `ulimit -t` setter in the diff (`git grep -n 'ulimit -t' -- zn scripts z-nile/lib z-nile/engine z-nile/tests/lib z-nile/check.sh`: `cpu.sh:5,7`, `bounded.pl:55` (a read), `fence.luau` comment) goes through `zn_lower_cpu`, which sets only when the current soft limit is `unlimited` or higher: CPU limits only ever lower (c-f of the brief hold). The jail string change and the two `ALLOWED` entries are narrow (one name in one file each).
- Docs: the rule sentence is byte-identical in AGENTS.md, z-design, zz-execute, zz-review (items 12 and 11) and zz-test (AC6 passes, and I read all five in the diff).
- zz-rules Merging step 3: keeps "`lune run scripts/cicd` passes." (pinned by `c0172/merge.spec`) and adds the wrapped form; the deviation is logged in the Verification log.

### F1 [medium] `./zn run` reports exit 125 "stopped at the CPU limit" for a parallel command that failed with status 1 for its own reason
Where: `z-nile/lib/bounded.pl:140-152`; c0191 Design, `bounded.pl` bullet 4; AC1 ("CPU limit (exit 125, only on unambiguous evidence)")
Evidence: run in the scratchpad: `zn run --time 60 --cpu 3 -- sh -c "perl -e '1 while (times)[0]+(times)[1] < 1.45; …' & perl -e '…< 1.45…' & wait; echo 'my own failure' >&2; exit 1"`. Both children printed `child done` (0.57+0.88 s each, half the 3 s limit), the command printed `my own failure` and exited 1, and the runner printed `bounded: stopped at the CPU limit (--cpu 3 s, used 2.9 s): sh` and exited **125**. `times` sums every reaped descendant while `ulimit -t` is per process, and status 1 is the most common failure status there is. The spec's parallel case (`bounded.spec.luau:330`) uses `exit 3`, so it never sees this.
Critique: 125 is the runner's published interface (R0071 "Provides to R0072": c0193's specs and lesson c0192 read 125 as "the CPU limit stopped it"). A red gate or a mutation runner under `./zn run --time 900 -- …` (`--cpu` defaults to `--time`, and their parallel workers' CPU adds up) that exits 1 is then reported as a CPU-limit stop, and the agent raises the limit instead of reading its failure. The tempting fix, a higher threshold, only moves the band.
Consequences: any rule that tells "one process hit the limit" from "many together used as much" needs per-process evidence the runner does not have (the Rokit shim turns SIGXCPU into exit 1). Dropping status 1 from the 125 rule changes what a spinning `lune` under the shim reports (1 plus a note instead of 125), which is R0072's interface: c0193 must be told.
Recommendation: escalate to the lead/user as an interface decision, with the options: (a) 125 only for status 152 (unambiguous), status 1 near the limit keeps 1 and gets the note "may have been stopped by the CPU limit", and the R0072 interface line says so; (b) keep today's rule but make AC1's and zz-test's wording honest ("125 also when a command exiting 1 used most of the allowance in total") so callers treat 125 as "maybe"; (c) make the evidence unambiguous, e.g. run the command's direct child under a tiny Perl parent that waits on it and reports a 152 / shim-exit-1 together with that child's own CPU only. Whichever is chosen, add a case with two half-limit children and `exit 1` (a new non-sequestered spec under `z-nile/tests/tooling/`, since `bounded.spec` is sequestered).

### F2 [medium] The `perl` rules read only a bare `-e`/`-E`: `perl -we`, `-le`, `-ne` and `-e'…'` pass, including the alarm recipe the Design names as the leak's cause
Where: `z-nile/engine/boundcmd.luau:457-486` (`(a == "-e" or a == "-E")`)
Evidence: through `boundcmd.check` with this checkout as `checkout`/`cwd`: refused `perl -e 'alarm 5; exec @ARGV' lune run x` (alarm), `perl -e 'while(1){}'`, `perl -E '1 while 1'`; **passed** `perl -we 'alarm 5; exec @ARGV' lune run x`, `perl -le 'alarm shift; exec @ARGV' 5 lune run x`, `perl -le 'while (1) {}'`, `perl -we 'while(1){}'`, `perl -ne 'while(1){}' /dev/null` (also in Monitor). Perl treats bundled `-we`/`-le` exactly like `-w -e`. The spec's refused list (`boundcmd.spec.luau:89,90,105,111,121`) has only bare `-e`/`-E`.
Critique: E4 is the incident mechanism ("the `perl alarm` recipe itself leaks"), AC2 says the hook refuses it, and `-we` is the idiomatic spelling. The tempting fix is to add `-we` and `-le` to the comparison, which misses `-lne`, `-Mstrict -e`, `-e'…'` and `-0777ne`.
Consequences: a general switch reader must not take a switch's value for a script (`-I dir`, `-M mod`, `-x dir` take arguments) and must handle the attached form (`-e'code'`, `-le'code'`).
Recommendation: read perl's switches as perl does: an argument matching `^-[^-]*[eE]` before the first non-switch argument introduces a script, which is the rest of that argument after the `e`/`E` when non-empty, else the next argument; `-I`/`-M`/`-m`/`-x` with no attached value consume the next argument. Add refused cases for `-we`, `-le`, `-lne`, `-e'…'` (alarm and loop each) and a passing `perl -ne 'print while <>' f`, in a non-sequestered spec.

### F3 [medium] zz-test's "Bounded commands" section is not the full mechanism the Design and Implementation step 6 call for; the gap is not logged
Where: `z-nile/skills/zz-test/SKILL.md` "## Bounded commands" (6 bullets) and "## Hooks"; c0191 Design, "The rule" paragraph ("the whole mechanism in one place: runner, limits and exit codes, the hook and why it fails open, Monitor, the reaper's three rules and its call sites, the CPU limits and that they only lower, SIGXCPU's limit, what each cannot do"); Implementation step 6 ("expand the zz-test section into the full mechanism description")
Evidence: `git grep -n "ZN_ENGINE_CPU\|fails open\|what it does not cover\|bash probe.sh" -- '*.md' ':!*/.tracker/**'` finds only zz-test:144 ("… fails open; …", with no reason). Missing from every skill: the engine's own CPU limit and `ZN_ENGINE_CPU` (every `./zn` command now dies at 1800 CPU-seconds, exit 152, with no message), that Monitor may loop and follow while Bash may not, the hook's blind spots (`bash probe.sh`, `npm`/`make`, unlisted interpreters, unreadable spellings), the reaper's scope (main checkout, this repository's session folders, runner temp folders) and its refusals, `--auto` doing nothing in a check run, and the stated gap (a session's shell that went outside scope after a crash stays). AGENTS.md sends readers there ("The zz-test skill's 'Bounded commands' has the rest"). The Verification log records no deviation for this. AC6's docs spec checks names, not this content, so it passes.
Critique: agents will treat the hook as complete (and skip `./zn run` for `bash probe.sh`), and a person whose `./zn` command dies with 152 has nothing to search for.
Consequences: none beyond keeping the section in step with the code; the AC6 pinned sentence and names stay as they are.
Recommendation: expand the section per the Design's list (one bullet each: hook rules incl. Monitor's allowance and why it fails open; what the hook does not cover; reaper scope, refusals, `--auto` no-op and the gap; the engine's 1800 s and `ZN_ENGINE_CPU`; SIGXCPU-ignoring processes). No spec change needed.

### F4 [low] `yes` is not refused although Decision 2 lists it as a follow
Where: `z-nile/engine/boundcmd.luau` `FOLLOWERS` (`watch`, `tail -f`, `gh … watch` only); c0191 Design, Decision 2 ("a follow (`tail -f`, `watch`, `gh ... watch`, `yes`, `caffeinate` without `-t`)")
Evidence: `boundcmd.check("yes")` and `"yes > /dev/null"` return `ok = true` (foreground and Monitor). The Design's detailed "Refused" bullet omits `yes`, so the Design disagrees with itself; the reaper's `ORPHANABLE` does list `yes`.
Critique: `yes > /dev/null` past the Bash timeout becomes a background process at 100 % CPU until the session ends, the incident's shape. Minor, because agents rarely run it.
Consequences: refusing `yes` must keep `yes | head -3` passing (a pipe into a bounded reader; `boundcmd.spec` already passes it).
Recommendation: refuse `yes` when its output is not piped into a command, or record the deviation in the Verification log.

### F5 [low] An absolute tooling target that leaves the checkout with `..` passes, contrary to "an absolute target must lie under ZN_CHECKOUT"
Where: `z-nile/engine/boundcmd.luau:141-171` (`insideOf` is a string prefix test)
Evidence: with `checkout = <worktree>`: `lune run <worktree>/../../tests/run` passes (it names `/Users/philipbergen/code/tests/run`, outside the checkout); `lune run tests/run/../../probe` is refused (correct). `lune run <worktree>/.cache/tests/run` also passes (a copy inside the checkout's `.cache`, which the Design's rule allows as written).
Critique: a lexical path test, not the path. Seatbelt-only, needs intent.
Consequences: resolving `..` lexically is enough (no file-system read in a pure module).
Recommendation: normalise `.`/`..` segments of an absolute target before `insideOf`; refuse when a `..` remains above the root; add the case to a non-sequestered spec.

### F6 [low] The reaper accepts `--root /Users` (or any ancestor of the home folder) and an unparsable `--under`
Where: `z-nile/engine/reap.luau:421-444` (`checkOptions`), `z-nile/engine/main.luau` `reapRun` (`under = tonumber(opts["--under"][1])`)
Evidence: `./zn reap --dry-run --root /Users --min-age 0` exits 0 (`reap: no leaked processes`), so the same line without `--dry-run` would run the orphan rule at age 0 over every folder of every user project; `./zn reap --dry-run --under abc` exits 0 and silently drops the option (zz-arch rule 8: every refusal names the rule). Because `Bash(./zn run:*)` is allowed, `./zn run -- ./zn reap --root /Users --min-age 0` runs with no prompt, although the Design says `./zn reap` "stops real processes and stays prompted" (the user accepted that any wrapped command is unprompted; this is the reaper's own guard, not the prompt).
Critique: the Design's aim is to refuse "the option combinations that would turn it on a live machine"; a root that contains the home folder is one.
Consequences: AC4 uses a root under `.cache`, so refusing roots that contain `$HOME` (or any root outside the main checkout) does not touch the check.
Recommendation: refuse a `--root` that is an ancestor of (or equal to) the home folder, and refuse a non-numeric `--under` naming the rule; add both to `reap.spec`'s neighbour (non-sequestered).

### F7 [low] The hook scripts are bounded by CPU only, not by wall clock
Where: `scripts/hooks/pre-bash.sh` (`zn_lower_cpu 2; exec lune run …`), `scripts/hooks/session-end.sh` (`zn_lower_cpu 15; ./zn reap …`)
Evidence: by reading, with the Design's own E4: a hook that blocks (a Rokit fetch, a hung `lsof` on a dead mount) uses no CPU; the harness kills the shim at 10 s / 20 s and the real `lune` is left at PPID 1. The orphan rule takes it a minute later at the next gate, `sync` or session end (it is a `lune` in the checkout with an ownerless chain), so it is backstopped, not lost.
Critique: the issue's own runner is cheap here (one Perl start) and would make the hooks follow the rule they enforce.
Consequences: wrapping pre-bash's `lune` adds a Perl start per Bash call (milliseconds); the wrapper's exit 124 must still fail open (it is not 2).
Recommendation: run both entries as `perl z-nile/lib/bounded.pl --time 8|18 -- …`, or record why not.

### F8 [low] `ZN_ENGINE_CPU=0` kills every `./zn` command silently
Where: `zn` (`[[ $lim =~ ^[0-9]+$ ]] || lim=1800`)
Evidence: `ZN_ENGINE_CPU=0 ./zn run --time 30 -- ./zn find c0191` exits 152 with no output; `ZN_ENGINE_CPU=1` works. The Design says a bad value falls back to 1800.
Recommendation: treat 0 as bad (`^[1-9][0-9]*$`), as `PICKMAN_SPEC_CPU` already does (1 to 86400).

### F9 [low] zz-rules Merging step 3 says "Run it as `./zn run …`" from a folder where that path does not exist
Where: `z-nile/skills/zz-rules/SKILL.md` Merging step 3
Evidence: "Run it as `./zn run --time 1800 -- lune run scripts/cicd` (from `$dir/pickman`, the clone's `zn` is `../zn`)". From `$dir/pickman`, `./zn` does not exist; the literal command fails. (`../zn run …` passes the hook: checked.)
Recommendation: write the command as it is typed there: `../zn run --time 1800 -- lune run scripts/cicd`, keeping the pinned "`lune run scripts/cicd` passes." sentence.

### F10 [low] `node` is in the reaper's ownerless chain, so an npm-installed (Node-hosted) Claude Code started at PPID 1 would have its live tool shells, and itself, taken as orphans
Where: `z-nile/engine/reap.luau:62-107` (`ORPHANABLE` and `CHAIN` both hold `node`)
Evidence: by reading: on this machine the session is the native `claude` (my ancestor chain: `claude -n …` → `-/bin/zsh` → `login` → Ghostty), which is in neither list, so it is safe here. An npm install runs as `node …/cli.js`; started headless at PPID 1 (a launchd job, `nohup claude -p … &` from a closed terminal), its own process is `node` (ORPHANABLE, ownerless at PPID 1) and its tool shells' only ancestor is that `node` (CHAIN), so both are "orphaned" a minute later at the next gate or `sync` while the session is working.
Critique: zz-arch rule 7's "unknown parent = keep" is bent by a name that is also the host of a live session.
Recommendation: never take a process (or treat it as an ownerless ancestor) whose command names Claude Code's CLI (`claude`, `@anthropic-ai/claude-code`), or drop `node` from `CHAIN`; add a `reap.spec`-neighbour case with a `node …/claude-code/cli.js` parent at PPID 1.

### F11 [low] Inline Python's process rule misses the common import forms
Where: `z-nile/engine/boundcmd.luau` `pythonHit` (`string.find(script, "subprocess%.")`)
Evidence: pass: `python3 -c 'from subprocess import run; run(["lune","run","x"])'`, `python3 -c 'import subprocess as s; s.run(["lune","run","x"])'`, `python3 -c 'for i in iter(int, 1): pass'`. Refused: `import subprocess; subprocess.run([...])`. The Design lists exactly `subprocess.` so this follows it; the gap is the Design's.
Recommendation: also hit `from subprocess import` and `import subprocess as` (then require `timeout=`), or say in zz-test's hook bullet that only `subprocess.`-qualified calls are read.

## Judged criteria (code mode only)
c0191 has no Judged criteria ("### Judged: None."); R0071 adds none. Nothing to rule on.

Other checks, no finding:
- Brief (a): settings match the Design exactly, nothing extra (above).
- Brief (b): the zz-rules wording keeps the pinned sentence; logged.
- Brief (c): the reaper signals only after re-reading every tree member's `lstart` in one `ps`; KILL goes only to pids still the snapshot's; `--auto` returns at once in a check run (`guarded(true)`) and is skipped in `--plan`; the session rule needs `ppid == under` and a `/shell-snapshots/` command; the orphan and deadline rules need a folder in scope; the reaper and its ancestors are excluded; `git maintenance`/`fsmonitor` and everything below them are kept. Against live processes, the default-scope and session-end dry runs named only my own decoy shell. The e2e check is safe on a live machine: an explicit `--root` under `.cache` replaces every default scope, the dry-run gate precedes every signal, decoys are cleaned by pid and start time. Residual risks are F6 and F10.
- Brief (d): the hook fails open on every bad payload tried and is fast; F7 is the wall-clock gap.
- Brief (e)/(f): the runner's group, watchdog, parent watch and final group KILL read correctly and AC1 passes; every CPU setter lowers only. F1 is the runner's one wrong result.
- Lessons asked: count-calls-in-poll-loops (the reaper's wait is clock-bounded, one `ps` per poll), read-paired-facts-at-one-moment (pid with `lstart`, re-read), plain-find-for-literals (`reap.luau`'s literal finds are plain), exhaustive-lists-name-new-things (usage, zz-rules lists, zz-arch layout, zz-test hooks name `run`/`reap` and the files), narrow-guard-allowances (two one-name entries): no finding beyond the above.
- Bounded commands (item 11): no script in the diff uses `nohup`/`setsid`/`perl alarm`; c0191's `check.sh` runs `reap-e2e.luau` through `./zn run --time 180`; the author's U1 probes say they ran from a scratch folder; F7 covers the hooks.

Verdict: changes
