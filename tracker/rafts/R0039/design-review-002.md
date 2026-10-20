# Review 002: R0039 (design mode)
Inputs: b5d1fbf plus the uncommitted prep tree: `tracker/rafts/R0039/{R0039.md,check.sh,design-review-001.md,design-refute-001.md}`, `tracker/issues/c0075/{c0075.md,check.sh,acceptance/*.spec.luau,experiments/*}`. Read against `tests/lib/fence.luau`, `scripts/lib/fence.sh`, `tests/run.luau`, `scripts/check.sh`, `scripts/lib/par.sh`, `scripts/tracker/main.luau` (promote-check), `.github/workflows/check.yml`, `tests/tooling/{repo-fence,fence-leftovers,fence-cache-entry,sweeper-interlock}.spec.luau`, `tests/acceptance/{c0001,c0003,c0015,c0055,c0058,c0059,c0064,c0076,c0077,c0078,c0079}`, the testing skill, and the prototype in `.worktree/proto-linux-jail`. `grep -rlF` over `tests/acceptance` for `fence.luau`, `fence.sh`, `check.yml`, `repo-fence.spec`, `SETUP.md` and `testing/SKILL.md` finds no promoted spec beyond the two on `Overrides:` that the design turns red. I walked every `c0058/fence.spec` and `c0058/lock.spec` case under nested bwrap with the launcher record, and they hold.
Dropped from design-review-001: F1, F2, F3, F5, F6, F7, F9, F10. F4 is carried in part (F6 below). F4 below finds a second hole in the mechanism F8 introduced.

### F1 [high] `jailArgv` makes `/run` read-only before it binds anything under it, so a checkout under `/run` (the spec's own `/run/media/…` example) or a `TMPDIR` under `/run` can't be jailed, and AC1 pins that order
Where: c0075 Design, `fence.jailArgv` (`"--tmpfs", "/run", "--remount-ro", "/run", "--tmpfs", "/tmp", <rebind ro-binds>, "--bind", cache…, "--bind", runTemp…`); `jail-argv.spec`, cases "is exactly the reviewed policy…", "hides /run read-only…" (`argv[run + 1] == "--remount-ro"`) and "keeps a checkout that lives under /tmp or /run visible…" (rebind `/run/media/co/.git`); R0039 Risks ("A checkout under `/tmp` or `/run` … `jail()` re-binds it read-only"); AC1.
Evidence: bubblewrap applies its setup operations in argument order. `--remount-ro /run` remounts the fresh tmpfs read-only at once. Each later `--ro-bind`/`--bind` whose destination lies under `/run` first creates its mount point with `mkdir` inside the new root. On the now read-only tmpfs that fails (`Can't mkdir parents for /run/media/co/.git: Read-only file system`). So:
- The trial fails for a checkout on a udisks mount (`/run/media/<user>/<disk>/…`, the default for removable and secondary drives on Fedora and Arch), or with `TMPDIR` under `/run/user/<uid>`.
- `linuxWhy` reports `bubblewrap failed: …; run scripts/linux-jail.sh`. The script's own trial binds folders under `${TMPDIR:-/tmp}` and agrees only when `TMPDIR` is also under `/run`.
- The run then takes the fallback and refuses.

The feature the Risks section lists as handled can't work for `/run`. AC1's sequestered spec forces exactly this order, so a correct implementation fails AC1. E4 hid `/run` only with both folders under `/tmp` and a checkout under `/home`, so nothing in prep exercised a bind under `/run`.
Critique: the failure is safe (a refusal, not an escape). But AC1 says "any checkout under them kept visible read-only", and the pinned argv can't deliver that. The tempting fix is to drop `/run` from the rebind rule and say "checkouts under `/run` are unsupported". That keeps the `TMPDIR` case broken, and it gives a Fedora user with a checkout on a second disk a refusal that points at the wrong script.
Consequences: bubblewrap's `--remount-ro` is non-recursive, so moving it after every bind under `/run` keeps those binds as they were made: the rebinds read-only, the cache and the run's temp folder writable. The three `jail-argv` cases that encode the adjacency must change now, because they are sequestered. `scripts/linux-jail.sh`'s copy of the trial (and `TRIAL_PATTERN` in its spec) must follow, or the script and the runner disagree again (round 1 F9).
Recommendation:
- **Order.** Put `--remount-ro /run` after the rebinds and both `--bind`s (before `--dev`). Re-pin the exact list, and change "hides /run read-only" to assert that `--remount-ro /run` follows every `--bind`/`--ro-bind` whose destination lies under `/run`.
- **Spec cases.** Add one case each with a rebind under `/run` and with a run temp folder under `/run`, and update `TRIAL_PATTERN`.
- **Experiment.** Add one to the ubuntu-latest harness: a checkout made with `sudo mkdir /run/pickman-co && sudo chown`, and separately `TMPDIR=$XDG_RUNTIME_DIR`. It must show that the old order fails, that the new order starts, and that a write under the rebind is refused while `.cache` and `TMPDIR` are writable.
- **Rules row.** Add one: mutant "`--remount-ro` before the binds".

### F2 [medium] Other things a Linux run needs can live under `/run` or `/tmp`, and the design doesn't handle them: tool paths (NixOS, Guix), a home under `/tmp`, and the gpg agent
Where: c0075 Design, `jail()` step 1 (`rebind` = the checkout and the git common directory only), "Hiding `/run` and `/tmp`"; Usability; `scripts/linux-jail.sh` step 4; `scripts/lib/fence.sh` specs mode.
Evidence:
- **Tool paths.** On NixOS and Guix, `bash`, `git`, `perl`, `true` and the rest are reached through `/run/current-system/sw/bin`, and setuid wrappers through `/run/wrappers/bin`. With `/run` hidden, the trial's own `true` is not found (`bwrap: execvp true: No such file or directory`). `linuxWhy` quotes that and says to run `scripts/linux-jail.sh`. The script then prints its generic advice to rerun with `--apply-sysctl` (step 4 says "print bwrap's error and the knob" for any failure). That advice is wrong, and the host-wide sysctl doesn't help.
- **Home under `/tmp`.** Containers that set `HOME=/tmp` (common in CI images) lose `~/.rokit/bin/lune` inside the jail. The trial passes (`true` is in `/usr/bin`), and the run then fails at `exec lune` with a bare "command not found".
- **gpg agent.** A developer whose global config has `commit.gpgSign=true` signs every fixture commit. On Linux the agent's socket is `/run/user/<uid>/gnupg/S.gpg-agent`, now hidden, and gpg can't start a new agent in a read-only home, so every fixture commit fails with `gpg failed to sign the data`. On macOS the socket lives under `~/.gnupg`, so this works there today. The fixture helper and `fence.sh` set nothing about signing.
Critique: E4 proved the hiding on one image whose tools and home live elsewhere. The user's decision to hide `/run` and `/tmp` stands, but its consequences for anything else under those two paths are unstated. The tempting fix is a SETUP.md sentence. That leaves the misleading refusal and the sysctl advice in place.
Consequences: rebinding more paths grows the rebind list. Every rebind is read-only and comes before the writable binds (and before the remount, per F1), so it opens no write.
Recommendation:
- **Pure `fence.rebindPaths`.** Compute rebind with a pure `fence.rebindPaths(here, common, path, home)`. It returns, resolved, the checkout, the common directory, every `PATH` entry and `$HOME`, each only when it lies under `/run` or `/tmp`, without duplicates and without a path that lies inside another on the list.
- **Its spec.** Pin it in `jail-argv.spec`: a NixOS `PATH` yields `/run/current-system/sw/bin`, `HOME=/tmp/h` yields `/tmp/h`, and an ordinary host yields `{}`. Add a Rules row: mutant "PATH ignored".
- **Signing.** In `fence.sh` specs mode, add `commit.gpgSign=false` and `tag.gpgSign=false` to the `GIT_CONFIG_KEY_*` list (fixtures never sign), with a case in `wiring.spec`.
- **The script's advice.** Give the sysctl advice only for the four user-namespace errors `linuxWhy` already matches. Otherwise quote the error. Add a "does not blame" case to `linux-jail-script.spec`.

### F3 [medium] A Linux run on the outer-sandbox path fails two expectations: `live-jail` requires no `pidns` file, which the top writes on every Linux run, and the narrowed `c0078` case still assumes pid 1 is root's
Where: `live-jail.spec` "the run's lock names the jail's pid namespace…" (else branch: `t.expect(table.find(names, "pidns")).toBe(nil)`); c0075 Design ("the top writes `<lock>/pidns` (`fence.pidNamespace()`, skipped where it is nil) right after `takeLock`", unconditionally); the Overrides text for `c0078/jail-signals.spec` ("the live `fence.alive("1")` assertions remain only where `PICKMAN_TEST_JAIL ~= "bwrap"`"); AC5 ("or an outer sandbox that protects the repository").
Evidence:
- **AC5.** On Linux where bwrap can't start (a container without user namespaces, or nested inside another bubblewrap-based sandbox) and the probes say `outer sandbox (protects the repository)`, `pidNamespace()` is non-nil. The top writes `pidns`, and the else branch fails. AC5 is red on a host whose verdict the design accepts. The executor can't edit the spec and must escalate.
- **The live comparison.** In the same case, `fs.readFile(pidns) == mine` compares against `readlink`'s stdout, which ends in a newline. It is false whatever the file holds, so that assertion can't fail.
- **c0078.** An outer Linux sandbox that has its own pid namespace makes pid 1 the user's own. `fence.alive("1")` under `none (unjailed)` is then true again, and the case fails just as round 1 F2 found for bwrap. The gate keys on the jail's name rather than on the fact the assertion needs.
Critique: the design tested its Linux branch only as `bwrap`. The fallback path it shares with macOS has Linux-specific facts (`/proc` exists, pid namespaces are common) that the specs don't allow for.
Consequences: writing `pidns` only under bwrap loses nothing. In every other case the top and the guarded processes share one namespace, and `recordsPid` would record anyway.
Recommendation:
- **Write `pidns` only under bwrap.** State in the Design that the top writes `pidns` only when the jail is `bwrap`, and keep `live-jail`'s else branch as it is. Alternatively, make the else branch accept a `pidns` equal to its own namespace, together with a recorded `pid-<own>`. Either way, decide now, because the spec is sequestered.
- **Trim the comparison.** Trim `mine` before comparing.
- **Gate c0078 on pid 1.** Gate the narrowed case's live assertions on "pid 1 is not this user's" (`kill -0 1` refused) instead of on the jail's name.
- **Rules row.** Add one: mutant "`pidns` written outside bwrap", killed by the else branch on a Linux outer-sandbox run (reasoned).

### F4 [medium] The pure-seam fix for round 1 F8 pins lists that nothing is shown to use, and one entry, `$DARWIN_USER_TEMP_DIR`, is no environment variable, so following the Design drops macOS's user-temp leak probe
Where: c0075 Design, `fence.escapePaths` (`macos { "/private/tmp", "$DARWIN_USER_TEMP_DIR" }`) and "`escapes(here)` loops over `fence.escapePaths(process.os)` (… `$VAR` entries are read from the environment and skipped when unset)… The macOS probes it already has stay."; `jail-verdict.spec` "an outer sandbox must close each shared folder…"; `tests/lib/fence.luau` `escapes()` (`getconf DARWIN_USER_TEMP_DIR`).
Evidence:
- **The macOS entry.** `DARWIN_USER_TEMP_DIR` is a `confstr` name that today's `escapes()` reads with `getconf`. It is never in the environment. An executor who implements the loop as specified skips it on every macOS run. An outer sandbox that leaves the user temp folder writable, which the jail closes because programs outside it run files from there (testing skill, review 004 F2), is then judged "protects the repository".
- **No spec catches it.** No spec covers that probe: repo-fence's `getconf` probe tests the jail, not `escapes()`. The other reading of "the macOS probes it already has stay" leaves a dead, misleading list entry.
- **The use is untested.** A mutant `escapes()` that ignores `escapePaths` entirely, and keeps its own probes or none, passes every acceptance spec, because `jail-verdict` compares only the list literal.
Critique: round 1 F8 found the Linux probes untested. Its fix moved the paths into a pinned list, but the hole moved to whether and how the list is used. A second hole in the same mechanism suggests pinning data is the wrong unit. The probe itself should be testable.
Consequences: a testable probe needs the writable check, the variable lookup and the `confstr` lookup behind a seam.
Recommendation:
- **Pure `fence.leaks`.** Replace the list-only seam with `fence.leaks(paths: {string}, lookup: (string) -> string?): {string}`, which runs the writable-folder probe over resolved entries. `escapes()` calls it with `fence.escapePaths(process.os)` and a lookup that reads `$VAR` from the environment and `getconf:NAME` through `getconf`.
- **Rename the macOS entry** to `getconf:DARWIN_USER_TEMP_DIR`.
- **Spec it in `jail-verdict.spec`** on every platform:
  - a writable fixture folder under `.cache` is reported;
  - a missing or unwritable one is not;
  - an unset variable is skipped;
  - a `getconf:` entry goes through the lookup.
- **Rules row.** Add one: mutant "`escapes` ignores the list" and mutant "the `getconf` entry read from the environment".
- **Labels.** Keep the leak labels byte for byte if any promoted spec reads them (none does today).

### F5 [medium] The gate-scan entries the design gives are incomplete, and its conditional ban of `docker` and `systemd-run` collides with three of its own sequestered specs. `promote-check` doesn't run the scan, so this first shows on the PR's gate
Where: c0075 "Overrides and tests the executor edits", the `repo-fence` bullet ("`ALLOWED` gets entries for the promoted `…/live-jail.spec.luau` and `wiring.spec.luau` (they name `sandbox-exec`, and `wiring.spec` names `core.hooksPath`): … checked in prep … If no spec needs `docker`, `systemd-run`, `busctl` or `dbus-send`, the scan bans them too."); `tests/tooling/repo-fence.spec.luau` `NAMES`/`ALLOWED`; `scripts/tracker/main.luau` `promotedChecks` (type check plus `tests/meta/architecture.spec.luau` only).
Evidence: checking every c0075 acceptance spec against `NAMES` the way `bannedIn` does (case-insensitive substring) shows:
- `jail-verdict.spec.luau` names `sandbox-exec` (the `fence.reads` case), and no entry is planned for it;
- `live-jail.spec.luau` names `PICKMAN_TEST_FENCE` (it reads the run's lock through the marker), not only `sandbox-exec`;
- under the proposed ban, `jail-argv.spec` ("Docker" in its comments), `live-jail.spec` (`/run/docker.sock`) and `wiring.spec` (`systemd-run`) would all be flagged.

`promote-check` (RC0) doesn't run `repo-fence`, so after `tracker.sh done` promotes the specs, the PR's `gate` turns red at "no spec, check.sh or script switches a guard off…". "If no spec needs them" can't be decided from the documents: these specs name the words without using the tools.
Critique: the executor can fix this in `repo-fence` (not sequestered), but only after a red CI round, and with no reviewed reason for each entry. That is exactly what `ALLOWED`'s comment requires.
Consequences: banning the daemon names is worth having (round 1 F4), and it needs entries for the three specs.
Recommendation: list the exact `ALLOWED` table in the Design:
- `tests/acceptance/c0075/jail-verdict.spec.luau`: `sandbox-exec` (a jail name passed to the pure `fence.reads`);
- `live-jail.spec.luau`: `sandbox-exec`, `PICKMAN_TEST_FENCE` (reads the lock) and `docker` (the probe's socket path);
- `wiring.spec.luau`: `sandbox-exec`, `hooksPath` (the fence's output) and `systemd-run` (reads the testing skill);
- `jail-argv.spec.luau`: `docker` (a comment).

Decide the ban outright: add `docker`, `systemd-run`, `busctl` and `dbus-send` to `NAMES`, plus a planted line in the scan's self-test. Drop "checked in prep", or record the command that checked it.

### F6 [medium] (repeat of review-001 F4, the residue part) Host sockets outside `/run` and `/tmp` stay reachable on Linux, but the documents say the Linux jail hides host sockets, and the review-only list doesn't gain them
Where: c0075 Solution ("`/run` hidden (host sockets)"), Non-goals, Design "Hiding `/run` and `/tmp`", Documents (the testing skill loses "Linux (CI)" from "Caught only by review"); R0039 Risks ("hidden on Linux by `--tmpfs /run`"); design-refute-001 F4 (silent on this part); review-001 F4 Consequences ("`~/.docker/run` remain").
Evidence: the home folder is bound read-only, and connecting to a Unix socket ignores read-only mounts (E4 showed it for `/run`). So inside the jail, a spec on a Linux developer host can still reach:
- Docker Desktop for Linux's `~/.docker/desktop/docker.sock`;
- colima's or rootless Docker's `~/.docker/run/docker.sock`, or `~/.colima/*/docker.sock`;
- a gpg agent or ssh `ControlMaster` sockets under `~/.gnupg` or `~/.ssh`.

Any of those daemons can write the real checkout (`docker run -v <checkout>:/w …`), or reach origin over an already authenticated connection. AC5's probe checks only the three `/run` paths, so it passes on such a host. The refute answered the `/run` part (the user's decision) but not this residue, and it remains review-only without being listed.
Critique: the user decided to hide `/run` and `/tmp`, and that decision isn't questioned here. The point is that after this raft the documents tell readers that Linux has no socket gap, which is false for the hosts most likely to run Docker.
Consequences: hiding the home folder isn't possible, because specs read it. A mechanism that doesn't depend on paths, such as a seccomp filter on `socket(AF_UNIX)` (abstract sockets are already closed by the network namespace), is the only real closure. It is a separate design, and it belongs in the follow-up issue with the macOS gap.
Recommendation:
- **Wording.** Say "sockets under `/run` and `/tmp`" wherever the documents say host sockets are hidden.
- **Testing skill.** Add to its "Handing work to a process outside the jail" bullet: "a daemon socket elsewhere (Docker Desktop's under the home folder), on both platforms".
- **Follow-up issue.** Widen it to "Unix sockets outside the hidden paths, macOS and Linux", naming seccomp (Linux) and `network-outbound (remote unix-socket)` (macOS) as the candidates.
- **Ban.** Together with F5's ban on `docker`, this keeps the one tool that uses those sockets out of every scanned file.

### F7 [low] The Linux sibling of repo-fence expects `/dev/shm` to be unwritable, but under `--dev` it is the jail's own writable folder, so the sibling fails top-level and nested (promoted `c0058/fence.spec` "the gate spec fails…" counts that failure)
Where: c0075 "Overrides and tests the executor edits", the repo-fence bullet ("`/var/tmp`, `/dev/shm` and `$XDG_RUNTIME_DIR` not writable"); E1 (`: > /dev/shm/probe` passes: "`/dev/shm` is the jail's own"); `c0058/fence.spec` `failures()` (excludes only the macOS case).
Evidence: bubblewrap's `--dev` mounts a tmpfs on `/dev` and creates `shm` in it, owned by the user. E1 recorded the write succeeding without reaching the host. The sibling as specified errors in the top-level run. Nested inside `c0058/fence.spec`'s scan copy, the line is `FAIL … on Linux this run can write…`, which is not excluded off macOS, so that promoted case goes red too.
Recommendation: treat `/dev/shm` like `/tmp` in the sibling: private, so it is writable but a file written there doesn't appear on the host. The sibling can't check the host side, so assert only that it is a mount of the jail's own: its device differs from the host's, readable from `/proc/self/mountinfo`. Or leave `/dev/shm` out. Keep it in `fence.escapePaths("linux")`, where it means the host's.

### F8 [low] Nothing checks that `PICKMAN_REAP_LOCK` is unset for the specs, and the launcher spec's negative cases can't see a leak
Where: c0075 Design ("unset for the specs by the same `unset` that clears `PICKMAN_REAP_SWEPT`/`PICKMAN_REAP_CACHE`"); the Rules table (no row); `launcher-lock.spec` "records nothing without the lock variable" (`launch({}, …)`) and "records nothing when the lock is not a folder".
Evidence: `process.exec`'s `env` merges with the inherited environment. If the variable leaked to the specs (mutant: the `unset` line unchanged), "records nothing without the lock variable" would start its REAPER with `PICKMAN_REAP_LOCK` still pointing at the **real run's** lock. It would write `pid-<n>` there and list an empty `{base}/lock`, so the case passes. The same holds for `c0079` and `c0077`, which drive `fence.REAPER`. The "not a folder" case can't fail either, since no write into a file path can succeed. The only thing it pins is `r.ok`.
Recommendation: add `t.expect(process.env.PICKMAN_REAP_LOCK).toBe(nil)` (with `PICKMAN_REAP_CACHE` and `PICKMAN_REAP_SWEPT`) to a `live-jail` case, plus a Rules row: mutant "lock variable not unset". In "records nothing without the lock variable", pass `PICKMAN_REAP_LOCK = ""` explicitly.

### F9 [low] On Linux the fallback becomes the normal path for a host without bubblewrap, and every refused run then writes probe files into the real checkout and its git directory
Where: c0075 Design, `jail()` step 3 (the shared tail: `writable(here)` and `escapes(here)`); testing skill "Allowed writers" (`.cache`, `sourcemap.json`, the promote-check copies).
Evidence: `writable()` creates and removes `.pickman-jail-probe-<pid>` in the checkout, its common git directory, the main checkout and every `PICKMAN_FENCE_REAL_GIT` repository. `escapes()` does the same in the home folder and the temp folders. On macOS this tail runs only inside an outer sandbox, where the writes are expected to be denied. On Linux it runs on every developer host that hasn't installed bubblewrap. Each `lune run tests/run` there leaves a brief untracked file in the working tree and in `.git` before refusing.
Recommendation: either list "the runner's own probe files (created and removed at once, only when it can't jail a run)" under Allowed writers, or skip `writable()` when `bwrap` is missing and no outer sandbox is suspected. In that case refuse directly with `linuxWhy`'s message. Say which, since this is a user decision if the second option drops support for an outer sandbox without bubblewrap.

### F10 [low] The raft document and one testing-skill bullet go stale under this design
Where: R0039 "Whole-raft design" (`lock: top writes <lock>/pidns; guarded processes record pid-N only in the same pid namespace`; Interfaces lists `jailArgv, linuxWhy, fallback, recordsPid, pidNamespace`); testing skill "Symlinks at the top of `.cache`: specs can't create one there"; c0075 "Documents".
Evidence: the raft's diagram and interface list predate round 1. They omit the launcher's record, which is now the thing that holds the lock, and `trialArgv`, `escapePaths`, `networkClosed` and `reads`. Under bwrap, specs can create a link at the top of `.cache` (E1). The skill's bullet would then be false on Linux, and the Documents list doesn't name it.
Recommendation: update R0039's diagram and Interfaces to the issue's design (plus F4's `leaks` and F2's `rebindPaths` if adopted). Add the Symlinks bullet to c0075's Documents list: "on macOS specs can't create one there; under bubblewrap they can, and the launcher unlinks them after the run".

Verdict: changes
