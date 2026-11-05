# Review 003: c0122 (design mode)
Inputs: worktree `prep-fence-accepts-empty-fetch` at 0d4323b4, plus its uncommitted `c0122.md`, `check.sh`, `acceptance/{fetch,refuse,wording}.spec.luau`, `design-review-00{1,2}.md`, `design-refute-00{1,2}.md` and `harvest.md`; `./zn capture c0122` (b46fadef, a confirmed capture: title, Problem, Outcome and Non-goals match, and the Problem only gained the "Prep finding" paragraph); c0123's prep worktree (`c0123.md`, `acceptance/wording.spec.luau`, `experiments/prototype.patch`); c0189's prep worktree (`c0189.md`, `acceptance/repo-hook.spec.luau`); `./zn lessons --when design --full`; the zz-review lessons.
Dropped from design-review-002: F1, F3, F4. Their fixes are in the document and the specs, and the runs below agree with them. F2's fix (the positive rule) is right, but the safe command it added has the same defect as before, so its mechanism comes back as F1 below.
Runs (git 2.54.0, every command time-bounded; fixtures in `mktemp -d` folders, and spec runs in a `--no-hardlinks` clone of the worktree with the prep files copied in, all deleted afterwards):
- In the worktree: `./zn check c0122` gives AC1, AC2 and AC4 PASS, and AC3 FAIL naming every phrase and allowance line (E4). `./zn promote-check c0122` is OK.
- In the clone, base `fetch` and `refuse`: 10 passed. M13 (`set -u` in the hook) fails the 4 cases E7 names. M14 (`refs/tags/` creations allowed) fails the tag case alone. A new mutant, `[ -z "${PICKMAN_FENCE_SPECS+x}" ]` (an empty transaction accepted only when the marker is unset), fails AC1 on `empty=` (F4).
- Design items 1 to 3 applied exactly as worded (the text copied from `c0122.md` lines 50, 53 and 56 to 63): `wording.spec` 4 of 4. `repo-fence.spec` passes 10 of 10 before promotion, so the stale-key case does accept the keys.
- c0123: its wording spec pins only its own appended sentences, not the fetch sentence. c0189: its `repo-hook.spec:247` now has the nothing-new fetch case that Existing work said had been reported to it.

### F1 [medium] The safe command in the new Ref guard sentence is itself refused under `fetch.pruneTags` or `remote.<name>.pruneTags`, and under a remote's own refspecs (repeat of design-review-002 F2's mechanism, a third time)
Where: Design item 1 ("so a check fetches with `git fetch --no-prune --no-tags origin`"), AC1 (the safe form), AC3's fifth phrase, Usability, Rules row "the safe form `--no-prune --no-tags` succeeds …"
Evidence: each run used a throwaway origin and a `--no-hardlinks` clone, with the clone fenced by this worktree's `pickman_fence` as a check.sh flow (marker unset). Settings were applied through a global-config file (`GIT_CONFIG_GLOBAL`), the clone's config, or `-c`:
- **A.** Global `fetch.pruneTags = true`, and the origin commits and tags `v1`. `git fetch --no-prune --no-tags -q origin` gives `fence: a check tried to change refs in the real repository (…/c/.git); refused` / `fatal: in 'prepared' phase, update aborted by the reference-transaction hook`, exit 128, and no tag is written. With pruneTags on, git adds `refs/tags/*:refs/tags/*` to the refspecs whether or not it is pruning, and `--no-tags` doesn't remove a refspec.
- **A2.** The same, plus `--no-prune-tags`: exit 0.
- **B.** `remote.origin.pruneTags=true` in the clone's config and a new tag: the two-flag form exits 128.
- **I and I2.** `fetch.prune`, `fetch.pruneTags`, `remote.origin.prune` and `remote.origin.pruneTags` all true, plus `remote.origin.tagOpt=--tags`, all given with `-c`. Upstream, a branch the clone tracks is deleted and a new tag appears. `--no-prune --no-prune-tags --no-tags` exits 0 (the stale ref is kept, no tag). `--no-prune --no-tags` exits 128.
- **D.** `remote.origin.tagOpt=--tags` alone: the two-flag form exits 0, so `--no-tags` overrides that setting.
- **J.** The clone's `remote.origin.fetch` gains `+refs/heads/*:refs/heads/up/*`: even the three-flag form exits 128. **J2.** With `--refmap=` and an explicit `'+refs/heads/*:refs/remotes/origin/*'`: exit 0.
- **F and G.** `followRemoteHEAD` creates or moves `refs/remotes/origin/HEAD`: accepted.
- **L.** `git fetch -q origin main` (`./zn`'s form) with `-c fetch.pruneTags=true` and a new tag: exit 0. E7's claim that no tracker command is affected holds.

The keys that can change which refs a fetch writes (`git help --config | grep -E '^(fetch|remote|transfer)\.'`) are `fetch.prune`, `fetch.pruneTags`, `remote.<name>.prune`, `remote.<name>.pruneTags`, `remote.<name>.tagOpt`, `remote.<name>.fetch`, `remote.<name>.mirror`, `remote.<name>.followRemoteHEAD` and `fetch.bundleURI`/`transfer.bundleURI` (I didn't run the last two). git's documentation for `fetch.pruneTags` describes it as the companion of `fetch.prune`, so a machine that prunes is likely to have both set.
Critique: round 2's positive rule ("A fetch that writes any other ref is refused whole") is correct, and every run above agrees with it. The sentence goes on to promise a command, and that command was again chosen against this machine's git config, which has no fetch settings at all (`git config --global --list` has none). A check author on a machine with `fetch.pruneTags` set copies the documented command and is refused as soon as anyone tags upstream. The tempting fix is to add `--no-prune-tags` and stop. That fixes the prune and tag settings, but the sentence would still imply the command works for any remote, and a remote's own refspecs or mirror setting defeat every flag (J).
Consequences:
- AC3's phrase list changes, and so do AC1's text and the Usability line.
- The safe-form case has to set, on its own command line, the settings it claims to override. Otherwise it tests only the host (F2).
- Naming what the flags can't override adds one clause, and that clause needs a refuse case.
- The list of keys is an enumeration. Take it from `git help --config` and paste that search into the Design, so it can be rerun against a newer git (zz-review/lists-paste-their-search).
Recommendation:
- Make item 1's safe form `git fetch --no-prune --no-prune-tags --no-tags origin`, followed by one clause, for example: "which overrides every setting that makes a fetch prune or follow tags (`fetch.prune`, `fetch.pruneTags`, `remote.<name>.prune`, `remote.<name>.pruneTags`, `remote.<name>.tagOpt`); a remote whose own refspecs (`remote.<name>.fetch`, `remote.<name>.mirror`) write outside `refs/remotes/` is refused whatever the flags". Mirror it in AC3's phrases, AC1, Usability and the Rules row.
- `fetch.spec`, the safe-form case: call `fenced("checks", { "-c", "fetch.prune=true", "-c", "fetch.pruneTags=true", "-c", "remote.origin.prune=true", "-c", "remote.origin.pruneTags=true", "-c", "remote.origin.tagOpt=--tags", "fetch", "--no-prune", "--no-prune-tags", "--no-tags", "-q", "origin" })` and keep today's assertions. Run in a clone: it passes 4 of 4 even with a global `fetch.prune`/`fetch.pruneTags` file. With `--no-prune-tags` dropped it fails on its summary line (`result=refused …`), which is the mutant for the row (run).
- `refuse.spec`: one check.sh-flow case for the stated limit. The clone's config gains `remote.origin.fetch +refs/heads/*:refs/heads/up/*` (`fixture.git(work, {"config", "--add", …})`, a config write, not a ref). The three-flag form is then refused with the guard's message, no `refs/heads/up/main` exists, and `origin/main` hasn't moved. Remove the setting afterwards, or put the case last. Its mutant: the hook allowing `refs/heads/` creations during a fetch.
- Record runs A to L as a new experiment (E8).
- Accepting a tag-following or pruning fetch remains a guard widening and the user's call: escalate as before, don't decide it here.
Lesson: candidate for the lead, the third time this mechanism has appeared (harvest.md proposes z-design/promises-name-their-exceptions): a rule text that promises a command is checked against every configuration key the tool has that can change what the command writes (`git help --config` for git), and the case pinning the command sets those keys on its own command line. Check: "which of the tool's configuration keys change what this promised command writes, and does its case set them?"

### F2 [medium] The end-to-end specs read the host's git configuration: with a global `fetch.pruneTags` AC1 is red, and with a global `fetch.prune` the tag case's mutant survives
Where: `acceptance/fetch.spec.luau` and `refuse.spec.luau`, every `fenced()` call; Design › The end-to-end specs; E2 and E7 (all run on this machine's config, which sets no fetch key)
Evidence: in a throwaway clone of the worktree with the prep files copied in:
- Base `fetch` and `refuse`: 10 passed.
- `GIT_CONFIG_GLOBAL=<file: fetch.prune = true, fetch.pruneTags = true> lune run tests/run -- …/fetch.spec.luau …/refuse.spec.luau`: 9 passed, 1 failed. The failure is `AC1: the safe form …`, expected `followed=true noTag=true result=ok staleKept=true`, got `followed=false noTag=true result=refused: fence: a check tried to change refs in the real repository (…/c0122-fetch/clone/.git); refused …`.
- M14 (the hook allowing `refs/tags/` creations) under `GIT_CONFIG_GLOBAL=<file: fetch.prune = true>`: `refuse.spec` 6 passed, 0 failed. The prune case leaves the stale `origin/gone` behind, so the tag case's default `git fetch origin` is refused for pruning it, and the mutant that the tag row names survives.
- With the tag case's fetch pinned as `-c fetch.prune=false -c remote.origin.prune=false`, M14 under the same file fails the tag case (5 passed, 1 failed), and the base passes 6 of 6.

Nothing isolates the specs from the global config: `git grep -n -e GIT_CONFIG_GLOBAL -e GIT_CONFIG_NOSYSTEM -- z-nile/tests z-nile/lib` finds nothing, and `fixture.exec` passes the environment through.
Critique: these specs exist to pin what git's fetch does through the guard, and what a fetch writes depends on configuration. A promoted spec that is red on a contributor's machine fails the gate there with no code change. A mutant that survives on some host leaves the rule unpinned there. This is lesson zz-test/specs-set-host-markers-explicitly again, with the host's git config in place of the jail markers. The tempting fix is `export GIT_CONFIG_GLOBAL=/dev/null` in the fenced script. But `GIT_CONFIG_` is a banned name in the repo-fence scan, so that needs a second allowance name and changes the allowance line that AC3 pins, and the system config would still be read.
Consequences: each case names on its own command line the settings its result depends on, so the cases get longer. Command-line `-c` outranks global and system config and uses no banned name, so the scan, the allowance and AC3's allowance pin don't change. Each Rules row for a prune or tag case then names the setting it pins.
Recommendation:
- Pin the settings each fetch's outcome depends on:
  - the tag refuse case's default fetch: `-c fetch.prune=false -c remote.origin.prune=false` (the tag is then its only reason; run, see above);
  - the prune case's `--prune` fetch and its `--no-prune` sync: `-c fetch.pruneTags=false -c remote.origin.pruneTags=false`;
  - AC1's plain fetches (`brings`, `nothing`, `again`, `empty`, `after`): `-c fetch.prune=false -c fetch.pruneTags=false -c remote.origin.tagOpt=` or an equivalent fixed set;
  - the safe form: as in F1.
- Put the rule in the Design's spec section ("every fetch passes, with `-c`, the fetch settings its result depends on: the host's git config never decides a case"), with lesson zz-test/specs-set-host-markers-explicitly cited.
- Record as an experiment that both specs pass, and that M5, M12, M13 and M14 still fail their rows, with a `GIT_CONFIG_GLOBAL` file setting `fetch.prune` and `fetch.pruneTags` to true, and with one that sets them false.
Lesson: zz-test/specs-set-host-markers-explicitly

### F3 [low] Both end-to-end specs' headers still say a check.sh flow runs with `PICKMAN_FENCE_SPECS` empty
Where: `acceptance/fetch.spec.luau` lines 4 and 5, and `acceptance/refuse.spec.luau` lines 4 and 5 ("fenced by z-nile/lib/fence.sh exactly as a check.sh flow (PICKMAN_FENCE_SPECS empty) or a spec run (PICKMAN_FENCE_SPECS=1)")
Evidence: since design-review-002 F1 the Design says "A real check.sh flow has the marker **unset** … so every check.sh-flow case runs in `checks` mode", and `fenced()`'s own comment says the same. The file headers kept the round-1 wording. A maintainer who trusts the header could "simplify" `checks` back to an exported empty value, which brings back the very gap that M13 exposed.
Recommendation: change both headers to "(PICKMAN_FENCE_SPECS unset, as ac.sh leaves it; once also exported empty)". This is a sequestered text edit in prep, so no spec is needed.
Lesson: z-design/restated-rules-move-together

### F4 [low] The Rules table has no row for the `empty` mode fetch, though one case is the only one that kills its mutant
Where: Rules and mutants; `fetch.spec` AC1 (`empty = fenced("empty", …)`)
Evidence: the Design keeps one nothing-new fetch with the marker exported empty, and the refute of round 2 kept it so that an empty value stays covered. No row names it. Run in a clone: the hook mutant `[ "$lines" -eq 0 ] && [ -z "${PICKMAN_FENCE_SPECS+x}" ] && chain "$@"` (accepted only when unset) passes everything except AC1, which fails on `empty=refused: …`. M13's row covers the opposite mutant.
Recommendation: add the row "a check.sh flow's nothing-new fetch with the marker exported empty succeeds | fetch :: AC1 (empty) | the empty transaction accepted only when the marker is unset (`${PICKMAN_FENCE_SPECS+x}`) | run", and record that run in E7.

Verdict: changes
