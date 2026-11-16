# Review 005: R0039 (design mode)
Inputs: b5d1fbf plus the uncommitted prep tree: `tracker/rafts/R0039/{R0039.md,check.sh,design-review-00{1..4}.md,design-refute-00{1..4}.md}`, `tracker/issues/c0075/{c0075.md,check.sh,acceptance/*.spec.luau,experiments/*}`. Read against `tests/lib/fence.luau` (`alive`, the lock, `resolved`, `escapes`, `jail`, `REAPER`, `enter`), `tests/run.luau` (the browser guard runs after `enter`, so its folder lies in the run's temp folder), `scripts/lib/fence.sh`, `scripts/lib/ac.sh`, `scripts/lib/git-hooks/reference-transaction`, `scripts/check.sh` (stage order), `.github/workflows/check.yml`, `tests/tooling/{repo-fence,fence-leftovers,sweeper-interlock,run-guard-relaunch}.spec.luau`, `tests/acceptance/{c0001,c0015,c0049,c0058,c0078}`. I ran the five pure acceptance specs against the prototype (`.worktree/proto-linux-jail`, spec files identical to the prep tree): 46 passed, 0 failed.
Dropped from design-review-004: F1 (the candidate list is the pure, pinned `rebindPlan`; its spec kills "PATH unsplit", "HOME left out" and "checkout left out"), F2 (SETUP.md names only the sysctl route, and `linuxWhy` has the nested message), F3 (AC1 says `/bin/sh -c :`; the Test plan lists the plan cases; the label change is stated), F4 (the `/proc/*/ns/pid` method is stated; no poll is needed, because a pid namespace is empty before its init's parent `waitpid` returns), F5 (perl, not python3). Earlier rounds stay dropped.

Checked and holding:
- **Documents against the specs.** Every signature in the Design matches its spec's calls and argument order: `jailArgv`, `trialArgv`, `rebindPaths`, `rebindPlan` with its `RebindEnv` keys, `linuxWhy` with three arguments, `fallback`, `escapePaths`, `leaks`, `networkClosed`, `reads`, `recordsPid`. The Test plan's case names match the specs for AC1 (13 cases), AC3, AC4, AC5 and AC6. The Rules table's spec::case references all exist. The check.sh AC1 to AC7 labels and order match the issue. AC7's folder list matches the doc's twelve ids and five tooling specs.
- **The gate scan.** Grepping the seven specs for every `NAMES` entry plus the four new ones gives exactly the planned `ALLOWED` entries. c0049's `tests-run` exemption covers `live-jail`'s lock read.
- **CI.** No workflow spec pins the gate's step indexes. The dispatch step runs the sequestered specs after `linux-jail.sh` has run.
- **c0058 under nested bwrap.**
  - The `during()` tripwire cases change the fixture from outside the inner jail, so the Overrides' tripwire variant needs no new machinery.
  - The spec-run `ac.sh` case is unchanged: `ac.sh` passes no jail, so it sets hooks, as it does under the macOS jail today.
  - The `chain` hook does not depend on `PICKMAN_FENCE_HOOKS`.
- **Consequences of hiding `/run` and `/tmp`.**
  - The browser guard's folder is under the run's temp folder at the top level. In nested runs it is rebound read-only, so its stub still shadows `xdg-open`; only its log write fails.
  - Unjailed `.cache` writers (gate stages run before the specs, tracker writes go through `writeReplacing`) don't follow a link a spec made.
  - Signing is off, and the gpg socket is not needed.
  - `RC1` never installs or changes anything: it needs `bwrap` present and passes no flag.

### F1 [low] A few document lines still disagree with the specs or the experiments. The one that matters: `jail()` step 3 calls `linuxWhy` without the argument that turns on the nested message, and nothing on the gate would notice
Where: c0075 Design, `jail()` step 3 ("`why = fence.linuxWhy(program, trial stderr)`"); AC2 text and the AC2 Test plan line; E3 ("AC4's spec passes 11 of 11"); Scalability ("Nested runs … nest a jail (E2: works)"); E5 ("if it is a **promoted** spec, narrow it … and say so in the Verification log"); "Overrides and tests the executor edits", the `repo-fence` Linux sibling bullet.
Evidence:
- **`linuxWhy`.** The signature and `jail-verdict` "says a jail could not nest…" take `outerJail` as the third argument, but step 3 passes two. An executor who follows step 3 literally gets:
  - AC2 green, because the function is pure.
  - A green Linux gate, because nesting works on CI.
  - On a host that can jail but not nest, the sysctl advice again: the exact misdirection round 4 F2 removed.
  - The Design never says where `outerJail` comes from. It is the inherited `process.env.PICKMAN_TEST_JAIL`, read before `enter()` overwrites it for an outer sandbox.
- **AC2.** Neither the AC2 text nor its Test plan line mentions the nested message, though the spec and the Rules table have it.
- **E3.** `linux-jail-script.spec` has 12 cases, not 11.
- **E2.** E2 nested the *first* argv: no `--tmpfs /run`, no `--tmpfs /tmp`, no rebinds and no `--new-session` (`experiments/E2-bwrap-nesting-signals.sh`). The final policy nested inside itself is first run by E5. I expect it to work: bubblewrap mounts its own base on `/tmp`, and the outer `/proc` is a fresh mount. But the doc states it as proven.
- **E5.** E5 allows narrowing another promoted spec in this PR. It doesn't say to add that spec to the `Overrides:` line and Touched modules, which is what review step 4 checks.
- **The `repo-fence` Linux sibling** lists bwrap-only facts: `/tmp` private and writable, `.cache` a mount point, `/run` read-only. It doesn't say what holds on a Linux outer-sandbox run, which the macOS case accepts. It also doesn't say how "no effect outside" for `/tmp` is checked from inside.
Critique: each one is small, but the first is the "pure seam, one wiring line" pattern this raft has hit four times. This time the gap is in the text, not the mechanism. The pure function is right, and the executor needs the right call written down.
Consequences: none beyond the text. Passing `PICKMAN_TEST_JAIL` is already how `fence.alive` reads the jail.
Recommendation:
- Change step 3 to `why = fence.linuxWhy(program, trial stderr, process.env.PICKMAN_TEST_JAIL)`, read before `enter()` sets it for an outer sandbox. Add a Rules row: "`jail()` passes the inherited jail name", reasoned, read in code review.
- Add the nested message to AC2's text and its Test plan line.
- E3: "12 of 12".
- Scalability: "E2 nested the first argv; the final one nested is E5's first check (the nested `c0058` runs)".
- E5: "…and add it to the `Overrides:` line and Touched modules".
- Sibling: gate the bwrap-only probes on `PICKMAN_TEST_JAIL == "bwrap"` and keep the shared probes for an outer sandbox. Either name the `/tmp` check (its `/proc/self/mountinfo` entry is a `tmpfs` of the jail's own) or say only "writable".

Verdict: approve
