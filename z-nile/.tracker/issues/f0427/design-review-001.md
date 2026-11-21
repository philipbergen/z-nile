# Review 001, Fable 5.2, 2026-11-21
Design mode, one round, covering f0427 and f0428 together.

## Findings
- F1 [high] The active half of the work walk has no design in host mode. workread.luau:819-860 finds layers from refs of the repository the engine runs in, and cmd.done (main.luau:5403-5406) fails with no layers. In a host, the engine runs in .tracker, where no layer branch exists and start is refused. Unstated: where the review, final-review, trace and harvest files are written, what trace --check reads, what replaces the layer diff, and workread.prLookup (627-650), along with eight gh pr calls, asks the tracker repository.
- F2 [high] The checks that keep unapproved work from landing are not carried to zn pr and zn land: cmd.done's reviewProblem, runCheck, guessesKept, guessedGap and approvalGap (main.luau:5409-5470). In land=pr mode, the irreversible public act is opening an upstream pull request.
- F3 [high] The approve terminal test lives in the bash wrapper (zn lines 134-165) that the Go front door replaces. The engine's own test (main.luau:6146) can be passed by an agent's tool shell. The wrapper also sets ZN_TOP, ZN_CWD and the CPU limit, and reroutes work.
- F4 [high] Sequestration is lost. check.sh, acceptance/ and approval.md live in the tracker, where the building agent can edit them and land them with only zn audit.
- F5 [high] G4's evidence is false. The engine calls perl in about fifteen places: lib/sh.luau:53 (replace-file.pl, with 19 call sites), costrow.luau:76, runner.luau:82,102,168, main.luau:6147, approvewalk.luau:562, workread.luau:633, watchcmd.luau:1237, dispatcher.luau:268, modelstep.luau:76, lib/procstart.luau:37, lib/fence.sh:149 and lib/par.sh:16. It also calls uuidgen, hostname, od, tar and security.
- F6 [high] Test plan, Rules and mutants, and Overrides are empty, and both check.sh files hold no check.
- F7 [high] One branch per ticket from upstream leaves a raft of several tickets undefined, and contradicts the owner's wish for fewer, meatier pull requests. The two Solutions disagree (raft branch vs ticket branch).
- F8 [high] A delivery in land=pr mode has no defined end: who notices the merge, changes requested, a closed pull request, a squash merge.
- F9 [medium] Recovery between the two repositories is described only for the spend row. Not covered: land merged then the publish fails; an owed row after the session ends; a rebase rewrites shas; ready wins then the fetch fails; a scan refusal read as a lost race.
- F10 [medium] The pre-push scan runs too late. It misses commit messages, the author email, the machine name, other machines' paths, other secrets and file names, and it can be silently off (core.hooksPath, a clone made by hand). This repository's tracker prose already contains the home path 379 times.
- F11 [medium] Host and tracker resolution is undefined from inside .tracker and its worktrees. worktree, land and commit are claimed by both halves, and "land" is reserved for the implementation merge.
- F12 [medium] There are more than seven switch sites. ac.sh cannot work from the engine cache: it cds to its own ../.., runs lune run z-nile/roots, and uses the fence. Also missed:
  - the watch net kick (main.luau:2857) and watchcmd.upkeep (4945);
  - done's check.sh --affected (5605);
  - costrow's measure.pl and prLookup's bounded.pl;
  - four lune spawns (4196, 4222, 5064, 6298);
  - approvewalk re-running the engine;
  - 355 messages printing ./zn;
  - reap, which is macOS only (8729).

  The shape of the host check.sh and its acceptance specs is undefined.
- F13 [medium] Nothing protects the owner's machine from the test command or a check.sh on Linux: there is no jail and no hook, reap refuses, test.command is unbounded, and settings from a public repository execute.
- F14 [medium] The embedded binary is trusted on a marker file alone, which leaves tampering, deletion, noexec mounts and XDG_CACHE_HOME taken from the environment.
- F15 [medium] Matching remotes by URL string breaks on ssh versus https forms and can publish a credential in settings, and gh repo fork names the fork origin.
- F16 [medium] Not designed: the live layer (where.MainCheckout finds .tracker, and the daemon can never be built there), skill upgrades, version skew between machines, and which lessons ship.
- F17 [medium] Linux is proven only at steps 9 and 10, step 5 names no test, and steps 3-5 each need pickman's full gate.
- F18 [medium] The bounded runner's guarantees are not listed for the Go port: the watchdog pipe, exit 123, a CPU limit that is only lowered, TERM then KILL, the group sweep, ZN_BOUNDED_DEADLINE, exits 124 and 125, --report, and the measurement variables.
- F19 [medium] Destroying .tracker destroys every ticket in f0427's local mode, because the bare origin is inside it.
- F20 [medium] The host skills are a second copy kept by hand, while this week's tickets rename skills.
- F21 [low] AC4 asserts no .claude folder, but omarchy ignores .claude/ and Claude Code writes settings.local.json there. AC9 names old stage words.
- F22 [low] f0427 excludes .cache/ in the host but says zn writes only under .tracker.
- F23 [low] Unusual hosts make dirname(git-common-dir) wrong (a submodule, --separate-git-dir, a bare repository with worktrees), so init should refuse each.
- F24 [low] Nothing in the design answers "too slow, too many tokens". Record that the settings or the work profile carry review-round counts, and that the Go front door passes the profile through.

## Verdict
changes
