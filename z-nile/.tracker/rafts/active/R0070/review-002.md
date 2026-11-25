# Review 002: R0070 (code mode)
Inputs: layer 2 `R0070/2/c0189` at 6c740db70 over layer 1 `R0070/1/c0194` at e5148ba57 (`git diff R0070/1/c0194...HEAD`, one commit); c0189.md, its `check.sh`, `guesses.md` and `acceptance/` (five specs), `experiments/layer2.patch`; R0070.md; the zz-review, zz-rules, zz-arch and zz-test skills.
Ran: `./zn check c0189` (5/5 PASS); the slow-tier gate specs the new stage could break, which the affected gate skips (`c0120/gate-homes`, `c0114/gate-cover`, `c0114/finished`, `c0074/done-gate`: 25 passed); c0194's `callers`, `docs` and `tmp` specs on this layer (54 passed); `./zn approve c0189 --check` (approved, hash holds) and `./zn guesses c0189` (G1 approved); read-only censuses of the real repository's refs and `git ls-remote origin`; a bounded Lune probe of repo-fence's `identitiesIn` on c0189's specs. Not run: mutation rows (each needs a full clone of guard code under `./zn tmp jail`; the prep and E15 records were read instead), `./zn hooks` in any form outside a spec fixture.
Also checked, no finding: sequestration (`git diff --find-renames=100% --name-status R0070/1/c0194...HEAD` on the tracker's `check.sh` and `acceptance/` paths lists only `A …/c0189/acceptance/watch.txt`, which `./zn finish` writes); overrides (the only promoted spec changed is `c0055/setup-run.spec.luau`, seven added lines, exactly as declared); the prose merge (a word-level diff of AGENTS.md, SETUP.md and the six skills against layer 1 deletes only three words, each replaced by its extended form: z-design's mutation bullet, zz-arch's `z-nile/lib/` row, zz-rules' main-checkout list; nothing of main's or layer 1's text is lost or contradicted); repository safety (no spec, `check.sh` or script runs `./zn hooks` against the real repository: `setup.sh` is run only by `c0055/setup-run` with a stub `zn`, `hooks-command.spec` runs the fixture's own `zn` through `fixture.exec` in a `.cache` checkout, the gate runs only `--check`, whose code path writes nothing; the real repository's `hooks/` folder holds no `reference-transaction` after every run above); the hook's logic against the Design (phases, the awk filter, the already-held test and its `HEAD` and per-worktree exclusions, the refusal on an unreadable commit, the message lines and when each prints); `hooks.plan` against the Design's table; `cmd.hooks`' reads (`zn` changes into the checkout, so the relative `SOURCE` path and the `ls-tree` pathspec resolve from the root); the three `ALLOWED` entries (each names one banned name in one file, for the stated use).

### F1 [medium] The z-design lesson the Design says to reword is not reworded, and no deviation is recorded
Where: `z-nile/skills/z-design/lessons/prove-specs-pass-on-a-prototype.md:13`; c0189.md:124 (The rules in prose), :177 (Touched modules), :327 (Implementation step 7)
Evidence: the Design says the lesson's "How to apply: in a scratch worktree, apply the smallest patch …" becomes "in a scratch clone or worktree (z-design, Unknowns & experiments)" and that the executor edits it as the raft's lead; Touched modules lists the file; step 7 lists it. `git diff --stat R0070/1/c0194...HEAD` has no lesson path, line 13 still reads "**How to apply:** in a scratch worktree, apply the smallest patch …" (and "under `src/` of the scratch worktree" later in the same paragraph), and neither `experiments/prototype.patch` nor `experiments/layer2.patch` touches it. `wiring.spec` does not pin the lesson, so `./zn check c0189` passes without it and the Verification log does not mention it.
Critique: this lesson is what z-design shows at every design's lessons pass, and it still sends designers to a scratch worktree, the habit (a worktree committing as `proto@example.invalid`) that produced the fixture-tip branches the chore exists for (F2 counts fourteen today). The rule this layer adds lives in three skills; the lesson is the fourth place that restates where a prototype lives, and it is the one left behind. The tempting fix is to change the two words on line 13 only.
Consequences: the same paragraph names "the scratch worktree" a second time, and the new wording must agree with c0194's "a prototype worktree goes under `.worktree/`" and with the new rule (a clone under `.cache/.tmp/`, or your own identity). The file is a lesson: no spec selects it, and `./zn lessons --check` reads its frontmatter, which does not change.
Recommendation: change line 13 to the Design's words ("in a scratch clone or worktree (z-design, Unknowns & experiments)") and the paragraph's second "the scratch worktree" to "the scratch clone or worktree"; run `./zn lessons --check`; say in the Verification log that the lesson was edited by the lead, as step 7 asks.
Lesson: z-design/restated-rules-move-together
Erred: zz-execute
Upstream: z-design

### F2 [medium] The existing-work census is stale: origin now carries a fixture-tip branch, the condition G2's recommendation named, and fourteen local branches have fixture tips, none of them the four G4 covered
Where: c0189.md:130-131 (Existing work), :191 (E1), :333 (G2); R0070.md Risks (After the merge)
Evidence: read-only, 2026-11-19: `git ls-remote origin refs/heads/proto-c0260` gives 6cb75b10d, author and committer `proto@example.invalid` ("Merge remote-tracking branch 'origin/main' into proto-c0260", 2026-11-14), and `refs/remotes/origin/proto-c0260` holds it locally; of origin's 85 heads it is the only fixture tip. `git for-each-ref refs/heads` lists fourteen branches with fixture-identity tips (`proto-boards-per-game`, `proto-c0202-landed`, `proto-c0251-rulings`, `proto-c0260`, `proto-c0262`, `proto-c0288`, `proto-n-place-deploy`, `proto-narrow-c0210-lobby-pin`, `-optb`, `-portal`, `-pre`, `proto-portal-start-place`, `proto2-n-place-deploy`, `proto2-portal-start-place`); the four `proto-wall-picks-*` are gone. The design still says "no remote-tracking ref has one" and "None of origin's branches has a fixture tip", and G2 was ruled on "Recommended: (a) now, (b) as its own chore if a push ever happens (it has not in the repository's history; E1 finds no fixture tip on origin)". The amendment of 2026-11-19 re-cut the specs and was approved again without re-running E1.
Critique: once the hook is installed a plain `git fetch origin` still passes, because the tracking ref already holds 6cb75b10d and git sends no update for it. But the day `proto-c0260` moves on origin (its owner pushes another prototype commit, from a scratch clone whose remote is GitHub or from anywhere the hook is not installed), or the local tracking ref is removed and fetched again, git aborts the whole ref update of every session's `git fetch origin` (E5) until someone deletes a branch that belongs to another session on GitHub. That is G2's accepted cost, but the user accepted it on a premise that no longer holds. The tempting fix is to delete `proto-c0260` on origin, or the local branches, yourself: both are other sessions' branches and writes to shared state, which only the user decides (G4 named four branches, not these).
Consequences: deleting the remote branch is a push to the shared remote; the pre-push hook (G2's option b) is a chore with its own design (`hooks.NAME` as a list, three cases, `--no-verify` still skips it); extending G4 to the fourteen branches needs their owners asked, as G4 says; nothing in this layer's code changes.
Recommendation: escalate to the user before `./zn done` (zz-execute stop conditions; under `## Open to the human` in R0070.md): give the census (the two commands above and their output) and ask (a) whether `proto-c0260` is deleted on origin before or right after the landing, and by whom; (b) whether G2's option (b), the pre-push chore, is captured now that a push has happened; (c) whether G4's "delete them" extends to the fourteen newer branches. Add the census command to the post-merge step in R0070.md's Risks so the lead reruns it after `./zn hooks`.
Lesson: z-design/new-rules-migrate-existing-work
Erred: z-design
Upstream: zz-review

### F3 [low] The post-landing net's first run after this raft lands fails at the new hooks stage, before any spec runs
Where: `z-nile/engine/watchcmd.luau:891` (`z-nile/check.sh --full` in `.worktree/watch-net`); zz-execute Phase 6 step 1 (`./zn watch-kick` right after the merge); c0189.md Implementation step 9 and R0070.md Risks (After the merge), which run `./zn hooks` after the merge
Evidence: `.worktree/watch-net` is a worktree of the real repository, so it shares the hooks folder. Once main holds `z-nile/lib/repo-hooks/reference-transaction` and `origin/main` has it, `./zn hooks --check` there exits 1 with `… is missing; run ./zn hooks` until someone installs the hook; `check.sh` stops at `par_wait … || { cat "$report"; exit 1; }`, `watch.failingSpecs` finds no spec, and the net fails with "the suite failed and named no spec": no pass is recorded for the landing and the slow tier does not run. c0189.md and R0070.md never mention the net (Existing work lists gates, `done`, `land` and the stop hook).
Critique: it heals at the next landing on this machine (the net covers every source since the last pass), but the landing that adds the stage is the one whose slow tier is skipped, and on any other machine the net fails silently (only `.cache/watch-net.log`) until `./zn hooks` runs there. The tempting fix is to skip the stage in the net, which would hide a missing hook from the one run that covers every spec.
Consequences: none in code; the order of two post-merge commands, and one more line for other machines.
Recommendation: in the landing, run step 9 (`./zn sync`, `./zn hooks`, `./zn hooks --check`) before `./zn watch-kick`, or kick again after it; say so in R0070.md's Risks (After the merge) and in the final report, with "the net stays red on a machine until `./zn hooks` runs there".
Lesson: z-design/new-rules-migrate-existing-work
Erred: z-design
Upstream: none

### F4 [low] `OTHER_IDENTITIES` widens the fixture-identity rule for addresses the scan never sees
Where: `z-nile/tests/tooling/repo-fence.spec.luau` (`OTHER_IDENTITIES` and its use in "every fixture commits as <name>@example.invalid")
Evidence: a bounded probe running the spec's own `identitiesIn` over c0189's `repo-hook.spec.luau` and `hooks-command.spec.luau` finds 0 identities in each: repo-hook passes every address through `GIT_AUTHOR_EMAIL = author` and `GIT_COMMITTER_EMAIL = committer`, which the pattern `email[^@\n]-([%w%.%-_]+@…)` cannot read. So deleting the table and its lookup leaves repo-fence green, and the Rules and mutants table has no row for it. The Regression guard and G1 asked the user for the widening because the cases "need commits under them".
Critique: an allowance that allows nothing today is a widening with no use, and nothing stops it outliving the spec's use of the addresses: the day the scan learns to read variables, or the spec spells an address after `email`, those four addresses pass for that file without anyone looking. The tempting fix is to delete the table, which departs from the approved Regression guard and G1.
Consequences: a per-address staleness check must read the sequestered copy until `done` promotes the spec, as the key-staleness case already does through `ROOTS`.
Recommendation: keep the table (G1 is the user's) and add to "every allow-list key names a file…" a check that every `OTHER_IDENTITIES` address occurs, as plain text, in its file (the promoted path, or the item's `acceptance/` copy before promotion), so an unused entry fails; say in the Verification log that today's identity scan does not read addresses passed through variables, so the allowance is pre-emptive.
Lesson: zz-test/narrow-guard-allowances
Erred: zz-test
Upstream: z-design

### F5 [low] `hooks-command.spec`'s leftover check looks for the first design's temporary name, so its two assertions cannot fail
Where: `z-nile/.tracker/issues/active/c0189/acceptance/hooks-command.spec.luau:62-71` (`leftovers()`), used at :368
Evidence: `leftovers()` counts names that start with `.reference-transaction.n` (the old `mktemp <dir>/.reference-transaction.new.XXXXXX`); the re-prep moved the temporary file into `replace-file.pl`, which names it `.reference-transaction.pickman-tmp.<pid>.<letters>`. No name the install makes can match, so `#leftovers() == 0` passes whatever is left behind. The property is still pinned elsewhere: `c0077/replace-file` ("a source that can't be read … leaves none"), row M7.
Critique: a vacuous assertion in a sequestered spec reads as coverage it is not. The executor may not edit it.
Consequences: none for this layer.
Recommendation: no change here; harvest it as a design lesson candidate: when a re-prep replaces a mechanism, search the sequestered specs for the old mechanism's names (here `.new.` and `mktemp`'s template) and re-point or remove each.
Lesson: zz-test/no-vacuous-pass
Erred: zz-test
Upstream: z-design

### F6 [low] SETUP.md's troubleshooting row says the gate fails for an older hook, which `--check` accepts
Where: `SETUP.md:52`
Evidence: the row says "the repository hook is missing or older than `origin/main`'s: run `./zn hooks`". `hooks.plan` flags an executable copy that `origin/main`'s first-parent history held as `older`, and `cmd.hooks --check` prints the note and exits 0 for it (hooks-command "when origin/main moves…" pins it). The stage fails for a missing or non-executable copy, a text `origin/main` never held, an unknown hook, a link, a folder, a redirecting setting, a failed read of `origin/main`, and `origin has no main fetched`.
Critique: a person whose gate is red for a hand-edited or never-merged copy reads "older" and may not see why; a person told "older" fails nothing.
Consequences: `wiring.spec` pins only steps 4 and 5, so the row can change freely.
Recommendation: "the repository hook is missing, not executable, or a text `origin/main` never held: run `./zn hooks` …"; keep the second sentence, and add `hooks: origin has no main fetched` → `git fetch origin main`.
Erred: zz-execute
Upstream: none

### F7 [low] Layer 2 edits layer 1's `tmp.luau` with no reason recorded, and so watches it
Where: `z-nile/lib/tmp.luau:174`; `z-nile/.tracker/issues/active/c0189/acceptance/watch.txt`
Evidence: `for _ = 0, #from do` becomes `for _ = 1, #from + 1 do`: both run `#from + 1` passes and the body does not read the counter, so nothing changes. The Verification log lists it among "the three fixes after the merge" with no reason, and no lint, type or meta rule I could find asks for it. Because `./zn finish` writes a ticket's watch from its layer's diff, c0189's watch.txt now names `z-nile/lib/tmp.luau`, so every later change to the temporary-tree maker also runs c0189's five hook specs (the hook and command fixtures are among the heavier ones).
Critique: one layer per ticket: a change to c0194's module belongs in c0194's layer, or nowhere when it changes nothing.
Consequences: reverting the line and rerunning `./zn finish c0189` drops `tmp.luau` from the watch; the Touched modules line that names it is design text (hashed by the approval), so leave it: a listed module that is not changed costs nothing.
Recommendation: revert the line in layer 2 and rerun `./zn finish c0189`. If a check did need it, say which in the Verification log and move it to layer 1 (`./zn finish c0194`, `./zn restack R0070`).
Erred: zz-execute
Upstream: none

### F8 [low] `cmd.hooks` reads every failure of the hooks-folder setting's read as "no redirect"
Where: `z-nile/engine/main.luau`, `cmd.hooks` (`configured`, `redirects = hooksLib.redirects(if configured.ok then configured.stdout else "", dir)`)
Evidence: `git config --get-all` exits 1 when the key is unset; any other non-zero exit (an option an older git does not know, such as `--show-scope` before 2.26; a value git cannot read) also becomes "no redirect", and `--check` can then report `ok` while git reads hooks from elsewhere.
Critique: zz-arch rule 7: a guard acts on its one explicit "no" and treats every other outcome as guarded. Only exit 1 means "nothing is set". Low, because a git that cannot read its configuration usually fails the earlier `rev-parse` too, and the supported hosts run git 2.34 or later.
Consequences: a third outcome needs a message naming the command and its stderr; no spec can easily make `git config` fail while `rev-parse` works, so this one is reasoned.
Recommendation: `if configured.ok then configured.stdout elseif configured.code == 1 then "" else fail("hooks: cannot read the hooks folder setting: <stderr>")`, in both modes.
Lesson: zz-arch/guard-no-is-explicit
Erred: zz-arch
Upstream: none

## Judged criteria (code mode only)
- None: c0189.md's `### Judged` says None, so there is nothing to rule on.

## Candidate lessons (for the lead to file)
- z-design (F2, F3): an amendment that re-cuts specs on a newer main also reruns the existing-work census and lists the new runners of the gate (the post-landing net) before the approval request; check: "Was E1-style existing work re-derived on the main the amendment was cut on, and does Existing work name every process that runs the gate in a worktree of the real repository?"
- z-design (F5): when a re-prep replaces a mechanism, the sequestered specs are searched for the old mechanism's names; check: "Does any sequestered assertion still look for a name, path or message only the replaced mechanism made?"

Verdict: changes
