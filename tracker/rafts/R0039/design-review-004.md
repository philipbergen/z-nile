# Review 004: R0039 (design mode)
Inputs: b5d1fbf plus the uncommitted prep tree: `tracker/rafts/R0039/{R0039.md,check.sh,design-review-00{1,2,3}.md,design-refute-00{1,2,3}.md}`, `tracker/issues/c0075/{c0075.md,check.sh,acceptance/*.spec.luau,experiments/*}`. Read against `tests/run.luau`, `tests/lib/fence.luau` (`enter`, `jail`, `REAPER`, the lock, `escapes`), `scripts/lib/fence.sh`, `scripts/lib/git-hooks/reference-transaction`, `scripts/check.sh`, `.github/workflows/check.yml`, `tests/tooling/{repo-fence,fence-cache-entry,fence-leftovers,run-guard-relaunch}.spec.luau`, `tests/lib/cachepaths.luau`, `tests/acceptance/{c0001,c0003,c0015,c0049,c0057,c0058,c0059,c0064,c0076,c0077,c0078,c0081}`, and the prototype's `fence.luau` additions (`jailArgv`, `rebindPaths`, `rebindFor`, `trialArgv`, `leaks`, `REAPER` record).
Dropped from design-review-003: F2 and F3 (fixed: the trial is `/bin/sh -c :` in `trialArgv`, the script and `TRIAL_PATTERN`; the spec header and steps 2 and 4 are current). F1 is fixed for the missing `<runTemp>/bin` and the NixOS link direction. Its `PATH`-splitting part is carried as F1 below. Earlier rounds stay dropped.

Walked end to end and holding. Each step is followed by what would catch a mistake there.
- **Linux, top level (CI).**
  - `tests/run` → `enter`. The top makes the run's temp folder under `/tmp`, because `TMPDIR` is unset.
  - `jail()`: `rebindFor` gets nothing under `/run` or `/tmp`. The trial is `/bin/sh -c :` (caught by AC1 and the jail-argv rows). Then `takeLock` and `pidns`.
  - The launcher records `pid-L` (launcher-lock).
  - Inside, `bash` runs `pickman_fence … bwrap`: no hooks, no signing (wiring). Then the guarded `tests/run` records nothing (`recordsPid`; live-jail "holds the launcher").
  - The browser guard folder is under the run's temp folder and so writable. Workers run.
  - Teardown: the launcher's group kill, link unlink and exit code. Then the top's snapshot, lock removal and temp-folder removal.
- **Linux, nested.**
  - `c0058/lock`: the killed-top case holds on the live `pid-L` of the outer namespace, then the takeover. The inner probes don't record (the lock's `pidns` is the outer jail's namespace). The "nested" probe does not wait.
  - `c0058/fence`:
    - escape, own, refs, push, fetch, chain and ownhooks pass under the inner read-only mount;
    - the env, tripwire and not-jailed-again cases are the Overrides;
    - the gate-scan case needs the Linux sibling of repo-fence to pass inside a nested jail, which its listed probes allow.
  - `c0059/adapt` checks only the two scan cases.
  - `fence-cache-entry` refuses before the jail.
  - `run-guard-relaunch` and `c0057` run guarded in the real checkout, with no inner jail.
  - Inner trials skip the missing `<runTemp>/bin` (the `rebindFor` row).
- **macOS.**
  - No `rebindFor` and no `pidns`. `recordsPid(nil, nil)` records as before. The launcher's `pid-L` is one more live pid.
  - The fallback tail goes through `fence.fallback` (jail-verdict; `c0058` pins `cannot jail this run`).
- **Overrides and the gate scan.**
  - Overrides: I ran the grep for every Touched path. The workflow, docs and fence specs that name the paths are the ones already listed in Affected and Regression guard.
  - Gate scan: the banned names in the seven c0075 specs are exactly the planned `ALLOWED` entries (re-grepped).
  - `c0049`'s fixture folders are unique, and `cachepaths` gains no line (`linux-jail.sh` and the `fence.sh` edits name no `.cache`).
- **Mutants.** Each `run` row's mutant fails its case as written. For `rebindFor` I checked missing kept, given dropped, resolved dropped, and `exists` applied to the resolved path.

### F1 [medium] (repeat of review-003 F1, the `PATH` part) Which candidates `jail()` hands to `rebindFor` (the checkout, the git directory, `PATH` split on `:`, `HOME`) is still unpinned, and nothing on the Linux gate exercises it. This is the fourth round to find a hole in "pure seam, wiring read in review"
Where: c0075 Design, `jail()` step 1 ("`rebindFor({ here, git common dir, every entry of the run's PATH, $HOME }, realpath, exists)`"); the Rules table (the `rebindFor` row's mutants are all inside the pure function; no row for the candidate list); review-003 F1's Recommendation (`rebindFor(here, common, pathVar, home, resolve, exists)`, splitting `PATH` inside the pure function); refute-003 F1 ("the wiring is now a pure, pinned function").
Evidence:
- `jail-argv.spec` passes `rebindFor` a ready-made list. These `jail()` variants all pass AC1 to AC7 and the whole Linux gate:
  - passing `process.env.PATH` unsplit (one candidate, which `exists` rejects);
  - leaving out `HOME`;
  - leaving out `here`;
  - leaving out the common dir.
- **Top level on CI.** No candidate lies under `/run` or `/tmp`, so the list doesn't matter.
- **Nested on CI.** The one `PATH` entry under `/tmp` is the outer browser guard's folder (`<runTemp>/pickman-guard.X`). If it is not rebound, the inner `tests/run` finds no `open` stub there (`tests/run.luau:46`), quietly makes its own guard, and passes.
- So the candidate list is exercised only on the hosts the rebind exists for: NixOS and Guix, a checkout under `/tmp` or `/run/media`, and `HOME=/tmp/h`.
- There, a wrong list passes the trial, because `/bin/sh` is absolute and the trial needs no `bash` and no checkout. It then fails at the real launch with `bwrap: execvp bash: No such file or directory`, or `.: scripts/lib/fence.sh: not found`, after the lock is taken.
- The refute counts the missing-`bin` part (which nested `c0058` runs do exercise) as the whole wiring.
Critique: rounds 1 F8, 2 F4 and 3 F1 each found the bug in the "one line, read in review" next to a pinned pure function. Moving more logic into the seam each round leaves a smaller unpinned remainder. That remainder is still where the bug can sit, and the Linux gate can't see it. The tempting answer is "E5 will show it". E5 runs on `ubuntu-latest`, where every variant above is green.
Consequences: pinning the list needs a function of the raw environment, so the spec has to cover `PATH` edge cases: an empty entry, a trailing `:`, `HOME` unset (nil in Lune) and a relative `PATH` entry (skip it, never resolve it against the cwd). A live proof needs a nested run whose candidates really lie under `/tmp`. The fixture rule keeps the nested *checkout* under `.cache`, so that run can prove `PATH` and `HOME`, not `here`.
Recommendation:
- **Pure function.** Make the candidate list pure, as review 003 recommended: `fence.rebindCandidates(here: string, common: string?, pathVar: string?, home: string?): { string }`, split on `:`, with empty and relative entries dropped and nils skipped. `jail()` is then `fence.rebindFor(fence.rebindCandidates(here, common, process.env.PATH, process.env.HOME), resolved, fs.isDir)`.
- **Spec cases in `jail-argv.spec`:**
  - `"/a::/tmp/b:"` gives `{here, common, "/a", "/tmp/b", home}` in order;
  - `pathVar` nil and `home` nil;
  - a relative entry is dropped.
- **Rules rows:**
  - mutants "`PATH` unsplit", "`HOME` left out" and "`here` left out" (run);
  - a reasoned row for the one remaining line.
- **Live case.** In `live-jail.spec`, gated on `bwrap`: copy the runner into `.cache/c0075-live-jail/nested` as `c0058/lock.spec` does. Run it with `PATH=<TMPDIR>/c0075-stub:$PATH` and `HOME=<TMPDIR>/c0075-home`, both created first. Its probe asserts `fs.isDir` of both inside the inner jail. That is the first check on the gate that fails when the candidate wiring is wrong.

### F2 [medium] Nesting is proven only with the sysctl lifted, yet SETUP.md is to offer an AppArmor profile as the alternative. Where nested user namespaces are refused, every nested-runner spec fails with advice that doesn't apply
Where: c0075 Documents ("SETUP.md (… for hosts that cannot, the AppArmor-profile alternative in one sentence)"); E2 (nesting, run on `ubuntu-latest` after `sysctl … =0`); Scalability ("Nested runs … nest a jail (E2: works)"); `jail()` step 3 with `fence.escapePaths("linux")`; `linuxWhy`.
Evidence:
- Ubuntu's shipped `bwrap-userns-restrict` profile moves what bubblewrap starts into `unpriv_bwrap`, which allows `userns` but denies capabilities. So a bubblewrap started *inside* the jail is expected to fail to mount in its new namespace. This is unverified here, and that is the point: no experiment covers a route other than the sysctl.
- When an inner trial fails, the inner run takes the fallback inside the outer jail. There `/tmp` and `/dev/shm` are the jail's private, writable mounts, and `escapePaths("linux")` lists both. So `leaks` is non-empty and the run refuses with `cannot jail this run (bubblewrap cannot create a user namespace here …; run scripts/linux-jail.sh --apply-sysctl)`.
- That takes down `c0058/fence` and `c0058/lock`, `c0059/adapt` and `fence-leftovers`, all through their setup case. A developer who followed SETUP.md's alternative gets a red suite whose message tells them to do the thing they chose not to do. The sysctl lasts only until the next boot, so a persistent profile is the route a Linux developer is likely to take.
Critique: the tempting fix is to make the fallback treat a private `/tmp` as no leak when inside bwrap. That weakens the outer-sandbox proof for a case that should simply not exist.
Consequences: either the documented routes are limited to ones that nest, or one more experiment proves a profile shape that does. A host that can jail but can't nest stays possible (a container's seccomp, say). It should fail with a message that names nesting, not the sysctl.
Recommendation:
- **Either** state in SETUP.md and the testing skill that the spec jail needs nested user namespaces. Name the sysctl as the supported Ubuntu route, and drop the profile sentence or name it as unsupported.
- **Or** add E9: on `ubuntu-latest` with the sysctl left at 1 and the proposed profile loaded, run E2's nested probe and record pass or fail. Write into SETUP.md only a profile that passed.
- **Either way:** when the inner trial fails while `PICKMAN_TEST_JAIL` is `bwrap`, `linuxWhy`, or the caller, says "a nested jail cannot start here (the outer one did): this host refuses nested user namespaces". Add a `jail-verdict` case and a Rules row (mutant: the sysctl advice inside a jail).

### F3 [low] Stale or contradicting text the executor will read: AC1 still says the trial uses `true`, the Test plan omits the `rebindFor` case, and the shared tail changes the macOS leak labels the Design says stay byte for byte
Where: c0075 AC1 ("the trial is that command with `true`"); Test plan, AC1 line (no "rebinds each existing candidate…"); Design `jail()` step 3 ("its messages stay byte for byte") against `fence.leaks` labels (`the folder <dir>`; today `the shared temp folder /private/tmp` and `the user temp folder <dir>`); R0039 Risks ("re-binds it read-only (`rebindPaths`), pinned in AC1").
Evidence:
- The pinned trial is `/bin/sh -c :` (jail-argv, `TRIAL_PATTERN`).
- The prototype's `leaks` returns `the folder /private/tmp`, so the macOS refusal text changes. Nothing pins it (I grepped `tests/`), but the Design claims it does not change.
Recommendation:
- Change AC1 to "…the trial is that command with `/bin/sh -c :`".
- Add the `rebindFor` case (and F1's, if taken) to the AC1 Test plan line.
- Either say the leak labels change to `the folder <dir>`, or have `leaks` take a label per entry so the macOS text stays.
- Make the Risks sentence name `rebindFor`.

### F4 [low] `fence-leftovers.spec`'s Linux assertion ("asserts the leftovers died with their jail's namespace") has no stated method, so the executor is likely to write a branch that can't fail
Where: c0075 "Overrides and tests the executor edits", the `fence-leftovers` bullet.
Evidence: the outer spec can't `kill -0` a pid of the inner namespace, and the Design doesn't say what else to check. On Linux, `survived` would be false by construction.
Recommendation: the probe records `readlink /proc/self/ns/pid`. When that differs from the spec's own namespace, the spec scans `/proc/*/ns/pid` and expects no process still in the recorded namespace (a child namespace's processes are visible in the parent's `/proc`), with a bounded poll for the teardown. State this in the bullet.

### F5 [low] `live-jail.spec` depends on `python3`, which no other spec or setup step needs
Where: `tracker/issues/c0075/acceptance/live-jail.spec.luau`, "no host socket is reachable on Linux…" (`process.exec("python3", …)`).
Evidence: `grep -rl python3 tests scripts` finds nothing, and SETUP.md doesn't install it. On a Linux host without it (a minimal image, NixOS without it in the profile), `process.exec` raises and the promoted AC5 case fails for a reason unrelated to the jail. `perl`, which the runner already requires, has `IO::Socket::UNIX` in core.
Recommendation: probe with `perl -MIO::Socket::UNIX -e 'for (@ARGV) { print "CONNECTED $_\n" if IO::Socket::UNIX->new(Peer => $_) }' …` and keep the case's assertions.

Verdict: changes
