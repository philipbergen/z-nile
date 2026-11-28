# Review 001: c0462 (design mode)
Inputs: base 475f932f0 plus the staged prep in `.worktree/prep-spec-runner-no-vacuous-pass`: `z-nile/.tracker/issues/c0462/{c0462.md,check.sh,rewrite-list.md,guesses.md,acceptance/*.spec.luau}`; `./zn capture c0462`; `z-nile/tests/run.luau`, `z-nile/tests/lib/{t,fixture,fence}.luau`; `z-nile/tests/slow.tsv`; `z-nile/tests/acceptance/c0049/parallel-runner.spec.luau`; `z-nile/tests/tooling/{run-guard-relaunch,run-lane-error,repo-fence}.spec.luau`; `z-nile/engine/boundcmd.luau`; zz-rules Merging; zz-execute Phases 5 and 6; the `origin/prep-*` branches.

### F1 [high] A promoted spec of an exempt item turns red: c0049 runs the real runner on zero-assertion probe files, and the design cannot let it pass
Where: c0462.md, The rule as built §3 (the check is on when `inCache(ROOT)` is false, and exemption goes by the path of the file being run); Regression guard (`Overrides: none`, "their fixtures sit under `.cache`, so the check is off for them"); E1.
Evidence: `z-nile/tests/acceptance/c0049/parallel-runner.spec.luau` (c0049 is exempt, its file may not be edited, and it is in `tests/slow.tsv`) runs `lune run tests/run` with `cwd = root`, where `root` is `pwd -P` of the real z-nile home (lines 15 and 95). So the runner is the real one, `ROOT` has no `.cache` part, and the check is on. The files it runs are `.cache/c0470-runner/<name>.spec.luau`, built from `PASS = cases("")` (line 54) and the rendezvous bodies. None of them asserts anything. `itemOf(".cache/c0470-runner/a.spec.luau")` is `nil`, so no file is exempt. Every such case now fails, and lines 169–170 (`r.ok` true, `"2 passed, 0 failed, 2 spec files"`), 191–192, 226–227, 244–245, 269–272 and others go red. That breaks Non-goal 1 ("a case in those files passes or fails exactly as it does today") and the captured "`--slow` stays green", and no fix is allowed. The same shape in a file that is not exempt is missing from `rewrite-list.md`: `z-nile/tests/tooling/run-guard-relaunch.spec.luau` case 1 runs the real runner on `.cache/run-guard-relaunch/records.spec.luau`, whose one case only writes a file, then expects `r.code` to be 0 (line 29). E1 could not see either one. Its prototype printed `ZERO` lines in each runner process, but a nested run's stdout goes to the spec that started it. E1 also skipped the slow tier, where c0049 lives.
Critique: the obvious fix is to add c0049 to some allowance or edit its probes, but the Non-goal forbids editing it. Another tempting fix is to skip every file under a `.cache` path, but that also exempts probes run by specs that are not exempt (run-guard-relaunch), which the capture says are checked ("in every registered project home", except exempt items' files and `.cache` homes).
Consequences: whatever carries the exemption into a nested run must not become a switch that a stray environment variable can flip for a whole real run. It also adds a visible state, like the "off" line.
Recommendation: carry the exemption from the running case into nested runs. The in-process case loop sets a variable (for example `ZN_VACUOUS_PARENT=<item id>`) in `process.env` while it runs a case from an exempt file, and clears it after. `fence.luau` already sets `process.env` for children this way (`PICKMAN_WORKER_LANES`, line 961). A runner that inherits the variable treats its cases as exempt and prints one line, `assertion check off: started by exempt <id>`. The outermost run of a real checkout (the one that wraps itself in the measurement, `ZN_MEASURED ~= "1"`) drops an inherited value, so a shell cannot turn the check off. Add these fixture.spec cases: a zero-assertion probe whose nested real-runner run of a zero-assertion file passes when the probe's file is a listed item's and fails when it is not; and an outermost run started with the variable already set still fails a vacuous case. Add `run-guard-relaunch`'s probe to `rewrite-list.md` (it can be edited: give the probe a `t.assert`). Rerun E1 with the prototype appending its `ZERO <file> :: <case>` lines to one log file named by an environment variable (absolute path, under the main checkout's `.cache`), so nested runs are counted. Include `--slow`, as lesson z-design/confirm-overrides-with-a-suite-run asks. Then fix the Regression guard to name this class (real-runner runs of probe files under a home's `.cache`: c0049, c0181's footer, run-lane-error, run-guard-relaunch). If the author prefers to skip files under `.cache`, that widens the exemption past the capture: record a guess and get a `Decided with the user` line.
Lesson: z-design/confirm-overrides-with-a-suite-run
Erred: z-design
Upstream: none

### F2 [high] fixture.spec commits as `dev@example.com` and runs raw `git add`/`git commit`: the gate's identity scan fails once it is promoted
Where: `acceptance/fixture.spec.luau:97-99`.
Evidence: line 98 is `{ "-c", "user.name=dev", "-c", "user.email=dev@example.com", "commit", ... }`. zz-test (Fixtures) says fixtures commit as `<name>@example.invalid`. The gate spec `tests/tooling/repo-fence.spec.luau :: every fixture commits as <name>@example.invalid` scans every home's specs, promoted acceptance specs included, and fails on any other identity (lines 764–793; the fence's `FIXTURE_EMAIL` is `@example.invalid`, and the tripwire relies on it). After `./zn done` promotes the file to `z-nile/tests/acceptance/c0462/`, every gate goes red, and the only fixes are editing a promoted spec or adding a repo-fence `ALLOWED` entry. Lines 97 and 99 also run `git add` and `git commit` through raw `process.exec`. zz-test allows raw git only for `rev-parse`, `ls-files`, `init` and `clone`, and otherwise requires `fixture.git`.
Critique: changing only the email is the tempting fix. The raw-git calls stay outside the helper's refusal of a directory that is not a fixture.
Consequences: `fixture.git` calls `fixture.check`, which requires the repository to sit under the run's own `.cache`. `base` is `{pwd -P}/.cache/c0462-vacuous`, so it qualifies.
Recommendation: commit as `dev@example.invalid`, and run `add` and `commit` through `fixture.git(repo, …)` (the `top == here` check can then go). Before the next round, run `repo-fence.spec` on a scratch copy that holds the file under `tests/acceptance/c0462/`.
Erred: zz-test
Upstream: z-design

### F3 [high] The landing order has no mechanism in the path that actually merges, so the list can miss an item whose prep merges after the gate
Where: c0462.md, How it lands steps 1–3; Implementation step 7; check.sh AC5; the capture's Solution bullets 7–8.
Evidence: zz-rules Merging lands a raft with `./zn done`, then `gh pr merge --squash`. If main moved after `done`, step 4 merges `origin/main` in with plain git (not a rebase), and asks for a re-run only when `lune run z-nile/affected` selects a spec. A prep's `z-nile/.tracker/issues/<id>/acceptance/*.spec.luau` is tracker state, which selects nothing. Nothing in that path runs `vacuous-exempt -- --write`, `--check` or `--gate-needed`. AC5 runs inside `done`, before that last merge of main. Under `./zn dispatch` the merge is a human's gate (zz-execute Phase 6), and that human has no reason to know about the writer. Scenario: `done` passes at main M1; the prep of a new item merges at M2 with a "cleans up" case that only calls `removeDir`. The merger merges M2 per step 4; affected selects nothing; the squash merge goes in. The new item is not on the list, and its sequestered case fails for good. Its check.sh can then never pass without editing a sequestered file. Main took 44 commits in the 24 hours the idea review counted (idea-review-003 F2), 13 `origin/prep-*` branches hold spec files today, and each of them is one such merge waiting to happen. The design also says "rebase" where the repository's procedure merges, and no guess covers that difference.
Critique: the tempting fix is a sentence in Implementation step 7. The executor does not perform the final merge, so a sentence there binds no one.
Consequences: every restack during execution also reruns AC5 and goes red whenever main has gained an item with specs. The executor needs the order for that case too (fix on the tip, `--write`, `./zn finish`, a plain restack). Also, `lune run z-nile/vacuous-exempt` is not in `boundcmd.TOOLING`, so the PreToolUse hook refuses it when an agent runs it bare.
Recommendation: key the landing to zz-rules Merging step 4 with exact commands: after merging `origin/main`, run `./zn run --time 120 -- lune run z-nile/vacuous-exempt -- --gate-needed <gated main> <merged main>` and `-- --check`. If either asks for it, run `--write`, commit, push, and rerun the gate. Have zz-execute Phase 5's `Ready to merge` comment carry those commands for whoever merges. Record a guess for merge versus the capture's "rebase", stating that the outcome (a list taken from the tree that merges) holds either way. Also add a fix-forward rule: right after the merge, run `--check` on main, and if an id is still missing (a race of seconds), open a PR with only the `--write` change before anything else lands. Say what the executor does when a restack's AC5 goes red.
Lesson: z-design/design-the-execution-window
Erred: z-design
Upstream: none

### F4 [high] AC8 can be passed by deleting the cases instead of rewriting them, and it reads a file the executor may edit
Where: check.sh `ac10` (AC8); `rewrite-list.md`; E4 ("the executor adds any case it finds to the list").
Evidence: `ac10` keeps only the file part of each line (`sed -E 's/ :: .*$//'`) and requires that each file runs clean. An executor that deletes `models-skills.spec.luau :: z-work rule 3 …`, or every case it listed, passes AC8. The capture says each case is rewritten to call `t.expect` or `t.assert`. `rewrite-list.md` is not sequestered: the sequestration check covers only `check.sh` and `acceptance/**`. So the executor can also trim the list AC8 reads. And if E4's slow-tier finds are added to that same list, check.sh starts running slow-tier specs, which every `finish`, `restack` and `done` reruns (lesson zz-test/check-sh-never-runs-the-slow-tier).
Critique: moving the file into `acceptance/` is tempting. That stops the trimming, but deleted cases still pass.
Consequences: E4's additions need a home that check.sh does not read, and the slow tier is still covered by the full gate.
Recommendation: move the prep list into `acceptance/rewrite-list.txt` (sequestered), and keep E4's later finds in the Verification log, not in the list AC8 reads. In `ac10`, run each home's files with `PICKMAN_RESULTS` set to a path under that home's `.cache`, and require that every listed `file :: case` appears there with `ok=true`. A missing case fails, naming it. Add a mutant row: "delete the case → AC8 fails".
Lesson: zz-test/check-sh-never-runs-the-slow-tier
Erred: z-design
Upstream: none

### F5 [medium] In-flight preps are not on the list, and the new failure hides among their expected red
Where: Checklist, Existing work ("An item prepared after the merge is checked from its first run: its zero-assertion case fails its own prep (intended)").
Evidence: the writer lists ids with specs in the tree that merges. Thirteen `origin/prep-*` branches (for example `prep-ref-guard-misses-branch-copy`, `prep-colorful-cli-output`, `prep-merge-past-tracker-only`) hold acceptance specs that are not in main's tree, and they were written for the old runner. A prep's own acceptance cases are red by design until execution, so a `case made no assertion` failure among them looks like an expected red, and the prep merges. Once the item is readied, the file is sequestered, so the case cannot be fixed and the raft stops for a human. I grepped their setup and cleanup cases and found none that asserts nothing. The design names no step that would find one.
Critique: the tempting fix is to put prep branches on the list. The capture fixes the list as ids in the tree that merges, so that would change scope.
Consequences: the guard has to live where preps are made and reviewed.
Recommendation: add to zz-test (pinned by docs.spec) and to z-design's spec step: "a sequestered spec's `case made no assertion` failure is never an expected red; fix it before the prep merges". Add it to the design-review checklist item that checks acceptance specs. Name the 13 branches in the Existing work bullet as the known cases.
Erred: z-design
Upstream: none

### F6 [medium] No acceptance case runs the check outside the z-nile home
Where: AC2, fixture.spec (every run is from the fixture's `z-nile/`); the capture ("in every registered project home"); E1's question about the re-exported `t`.
Evidence: a mutant that applies the check only when `HOME == "z-nile"` passes every c0462 spec. Whether a home's `tests/lib/t.luau` (which re-exports `../../../z-nile/tests/lib/t`) shares the runner's counter was proven only by E1's prep prototype, and nothing pins it. If a future edit gave a home its own `t` instance, every case there would count zero and fail. That one would at least be loud; the HOME mutant is silent.
Critique: none beyond adding the case.
Consequences: the fixture needs a second home's forwarder `tests/run.luau`, its `tests/lib/t.luau` re-export and its `.luaurc` alias, and a `projects.toml` or the runner's fallback for a home with no slash.
Recommendation: add `pickman/` to the fixture with those three files, and add a case: `--require-assertions` from `pickman/` fails a zero-assertion probe and passes a probe that calls `t.expect` through `@tests/lib/t`.
Erred: z-design
Upstream: none

### F7 [medium] AC7 pins two phrases already in main's lesson and leaves one captured item unpinned
Where: `acceptance/docs.spec.luau:16-23`.
Evidence: `git show origin/main:z-nile/skills/zz-test/lessons/no-vacuous-pass.md | grep -cF` prints 1 for `` `|| true` `` and for `` `diff <(a) <(b)` ``. The added line could name neither of them and the case still passes. The capture's list also includes "`check.sh` greps that find nothing", which nothing pins. The lesson's own R0100 note asks for every pinned phrase to be absent from main.
Critique: none beyond tightening the case.
Consequences: none.
Recommendation: find the one line that contains "the runner now fails a case with zero assertions" and require each of the five items on that line: greps that find nothing, `|| true`, `diff <(a) <(b)`, assertions that cannot fail, cases that read each other's output.
Lesson: zz-test/no-vacuous-pass
Erred: z-design
Upstream: none

### F8 [medium] AC6's unknown-ref clause checks only stdout, not the exit status
Where: check.sh `ac8`, last test.
Evidence: `[[ -n $(… nosuchref HEAD 2>/dev/null) ]] && fail` passes a writer that prints nothing and exits 0 on a ref it cannot resolve. AC6 says it "fails on an unknown ref". The "no change" (`HEAD HEAD`) case also accepts any status. The design leaves open which repository `--gate-needed` reads: the working directory's, which AC6's fixture needs, or the script's root. An implementation that uses the script's root would fail AC6 even though the design allows it.
Critique: none beyond tightening the check and stating the repository.
Consequences: none.
Recommendation: require a non-zero exit and empty stdout for `nosuchref`, and exit 0 for each `yes` and `no`. State that `--gate-needed` reads the working directory's repository, and `--write` and `--check` the writer's own checkout.
Erred: z-design
Upstream: none

### F9 [medium] count.spec's "a helper counts none" case cannot fail for the mutant it names
Where: `acceptance/count.spec.luau:46-51`; mutant row "helper bumps the counter".
Evidence: `fixture.exec("/nonexistent-c0462", "true", {})` raises at its first line, `fixture.check(dir)` (`fixture.luau:89`), because the directory is not a fixture under `.cache`. A mutant that bumps the counter after the check, where a real call would reach, never runs.
Critique: none beyond giving the call a real fixture.
Consequences: the case needs a real fixture: `git init` under `{pwd -P}/.cache/c0462-count`, then removed.
Recommendation: call `fixture.exec` on that fixture with a command that succeeds, then one that fails, and expect 0 for both.
Erred: z-design
Upstream: none

### F10 [low] "The flag reaches every worker" tests one of the coordinator's two worker branches
Where: fixture.spec "the flag reaches every worker"; `run.luau:419-428`.
Evidence: the coordinator builds its worker command in two places, plain `lune` or the `perl` lane wrapper when `PICKMAN_WORKER_LANES` is set (`fence.luau:961` sets it). The case takes whichever branch the environment gives, so dropping the flag in the other branch goes unnoticed.
Critique: none.
Consequences: none.
Recommendation: build the worker argument list once for both branches (and say so in the design), or run the case twice, with `PICKMAN_WORKER_LANES` empty and set.
Erred: z-design
Upstream: none

### F11 [low] Cross-references point at the wrong criteria
Where: `acceptance/exempt.spec.luau:2-3` ("a check.sh check only (AC7)": it is AC5); check.sh functions `ac8` (runs AC6) and `ac10` (runs AC8).
Evidence: as quoted.
Critique: an executor reading the comments looks at the wrong criterion.
Consequences: none.
Recommendation: rename the functions `ac6` and `ac8`, and fix the comment to AC5.
Erred: z-design
Upstream: none

### F12 [low] The design never says why c0462 depends on c0455
Where: frontmatter `depends_on: [c0455]`.
Evidence: c0455 (lessons staging and prune, still `design: draft`) names c0462 only as a later linter. c0462's docs.spec pins text in `no-vacuous-pass.md`, and c0455 changes which lessons `--check` accepts. The design does not say what c0462 needs from c0455, or whether docs.spec still passes after it lands.
Critique: an executor can't tell whether the dependency is load-bearing.
Consequences: if it is not, the dependency only delays delivery.
Recommendation: state the reason (or drop the dependency with a guess), and say what reruns docs.spec once c0455 is designed.
Erred: z-design
Upstream: none

Verdict: changes
