# Review 001: c0374 (design mode)
Inputs: prep worktree `prep-finished-spec-reads-homes-right` at 67677524b with the uncommitted prep draft: `c0374.md`, `check.sh`, `guesses.md`, `acceptance/reads-homes.spec.luau`, `acceptance/narrow.py`, `experiments/prototype.patch`, `experiments/mutants.sh`, `experiments/mutants-results.txt`; `./zn capture c0374` (35b72a5cb) and the idea commit 63f187d0d; origin/main 234d4dd3f (no change to `c0120/finished.spec.luau` or `rewrites.luau` since the base).
Runs made for this review (each through `./zn run` or the spec runner, in a `--no-hardlinks` clone at `z-nile/.cache/review-c0374/repo`, removed afterwards; nothing written outside `.cache`):
- `stylua --check` and `selene` on the patched `finished.spec.luau` and on `reads-homes.spec.luau`: clean.
- `reads-homes.spec.luau` on the prototype: 8 passed. Two walk mutants the Rules table does not list: P1 (`$(` never pushes `paren`) 8 passed; P2 (a `#` anywhere outside double quotes starts a comment) 8 passed. Both survive. P3 (a `#` inside double quotes starts a comment) fails 3 cases.
- A probe running the prototype's `singleQuoted` with `rewrites.literals` over all 260 finished `check.sh` files: 0 unbalanced, 16 literals masked (listed in F1), 46 files contain `<<` and 10 contain `$'`.
- `tests/tooling/repo-fence.spec.luau` with both `acceptance/` files copied to `z-nile/tests/acceptance/c0374/`: 9 passed, 1 failed. The failure is `specs have no GitHub credentials and push only into fixtures`, and it fails the same way with the c0374 files removed, so it comes from the clone's environment. The scan cases pass.

### F1 [high] G1 leaves the Solution's "still fails on a path" only partly true: real bare-name paths inside single-quoted scripts stop being checked, and only a guess covers it
Where: c0374.md Solution (line 25), Design "Why bare names only (Guess (prep) G1)" (line 40), guesses.md G1
Evidence: The Solution promises that the spec "still fails on a finished `check.sh` path that neither resolves from its home nor was missing before the move". The prototype masks every bare name inside single quotes, whatever command reads it. Over the 260 finished files it masks 16 literals: the 11 hits, plus 5 the Design never names:
- `pickman/.tracker/rafts/done/R0032/check.sh:18` and `R0037/check.sh:14`, `bash -c 'git diff --quiet origin/main...HEAD -- … default.project.json lobby.project.json'`. Those are real git pathspecs.
- `z-nile/.tracker/issues/done/c0115/check.sh:68`, `bash -c '… && cd .. && ./zn busy …'`.

They resolve today, so no verdict changes now. But if one goes stale it is no longer reported. The same holds for any later `check "ACn" bash -c 'test -x zn'` with no cd: a stale root-file path that the spec reports today and will not report after this change.

G1 records the trade as "loses the least checking", with no measurement. It also reads the capture's helper wording more narrowly: a folder path inside a helper's single-quoted message (`vocabulary 'run src/server …'`) is still read as a path, although the Solution says text passed to a check's own helper is not.
Critique: This is a (prep) choice that leaves an outcome only partly true, so it needs a `Decided with the user` line, not a Guess marker (lesson below). The tempting fix is to reword the Solution or G1's "Why" to describe the masking rule. That rewords a captured outcome away.
Consequences: Neither outcome can be kept whole without moving a fence. c0371's hit (`./zn` after `cd "$ZN_ROOT"` inside `bash -c '…'`, which landed after the idea stage) can be cleared only three ways:
- treat single-quoted script text as text (G1, which loses real paths);
- add cd handling, which the idea-stage Non-goal fences on a premise that c0371's landing has since made false ("No hit comes from a command after a cd to the repo root", idea-review-001 F1);
- add an exemption.
Each one changes what the Solution or the Non-goals promise. None of them is a reviewer's call or the author's.
Recommendation: escalate to the user (under the dispatcher, `questions.md`), with these options and their costs:
- (a) Keep G1 as designed, recorded as `Decided with the user (…)`. Cost: bare root-file names in any single quotes are never checked again. Today that is R0032:18, R0037:14 and c0115:68, and every future `bash -c '… zn …'` or `'… AGENTS.md …'` path.
- (b) The capture's own rule plus a scoped cd rule. Every literal inside a single-quoted argument of a helper the check defines, or of ac.sh's `cases`, is text, folder paths included. Inside a single-quoted script, `./zn` after `cd "$ZN_ROOT"` in the same script is read from the root. Cost: the user lifts the "no cd handling" Non-goal; the reader is larger (function definitions, command position, script-scoped cd) and needs more cases and mutants. R0032 and R0037 keep their check.
- (c) The helper rule of (b) plus one exemption for c0371:26, pinned by blob the way c0120 exempts its four restamped files. Cost: the rule gains an exemption list, which the Non-goal's "the rule stays as it is" must allow. The entry leaves when c0371's file changes. There is no cd handling.

Whichever option is ruled:
- name the 5 extra masked literals in the Design;
- add a reads-homes case pinning what happens to a bare root file inside `bash -c '…'` with no cd (reported under (b) and (c), text under (a)), with its mutant row;
- rerun E3.
Lesson: z-design/never-narrow-captured-scope
Erred: z-design
Upstream: none

### F2 [high] `reads-homes.spec.luau` becomes a permanent fast-tier spec at `./zn done`: a full-repository clone plus 7 nested suite runs in every full gate, and the live finished scan moves out of the slow tier
Where: c0374.md Affected specs ("run by `check.sh` only", line 75), "No behaviour change … the gate's fast tiers are unchanged" (line 42), check.sh AC1
Evidence: `./zn done` moves `acceptance/` to `z-nile/tests/acceptance/c0374/`, "where they become permanent regression specs" (zz-test). `tests/run` with no paths runs "every fast-tier tests/**/*.spec.luau" (`z-nile/tests/run.luau:4`). `slow.tsv` gains no row for the new spec.

So every `--full` gate (and the watch-net's fast suite on main) would then do three things:
- run `git clone --no-hardlinks` of the whole repository (115 MB of objects plus a full checkout, E2);
- run 7 nested `lune run tests/run` (about 3 s each, E2);
- run the live "every finished check.sh … resolves" scan.

Today that scan runs only with `--slow`. A future finished `check.sh` with a stale path would turn main's full gate red, where today it turns only the slow tier red. With no `tests/inputs.tsv` row (finished.spec has `*`), `--affected` would also never select the spec when a finished `check.sh` changes, so the red would first show in a full gate or the net.
Critique: Two claims the Design states are false: "run by check.sh only" and "fast tiers unchanged". The user's standing rule is that a proof needing real work (big fixtures, mass writes) is never promoted into the suite. The tempting fix is to delete the "passes on the repository as it is" case. That loses AC1's live-tree proof, which is the Problem's outcome.
Consequences: A slow-tier row changes the slow-tier membership spec (`tests/tooling/slow-tier.spec.luau` pins "names 101 existing z-nile specs"), and another in-flight item adding a row collides on that count. A check.sh-only rename loses the runner's jail for the outer script, so review must then confirm that it writes only under `.cache`.
Recommendation: Keep the spec out of the fast tier, and say how in the Design. Preferred: keep it as a jailed spec and add `tests/acceptance/c0374/reads-homes.spec.luau` to `z-nile/tests/slow.tsv` (slow-tier.spec accepts a row whose file is still sequestered). Also:
- change slow-tier.spec's count to 102;
- add a `*` row to `tests/inputs.tsv`, as finished.spec has;
- add all three files to Touched modules;
- add a check or an experiment showing that `--full` no longer selects the spec and that slow-tier.spec stays green.

The alternative is the check.sh-only pattern of zz-test/specs-never-burn-real-resources:
- rename the spec to a name without `.spec.luau`;
- run it only while `$HERE/acceptance` exists;
- give AC1 a stated outcome after done.

Either way, correct the two false sentences.
Lesson: zz-test/specs-never-burn-real-resources
Erred: zz-test
Upstream: z-design

### F3 [medium] Two plausible walk mutants survive every case: no `$(` context, and a `#` inside a word read as a comment
Where: c0374.md Rules and mutants row "the walk reads a comment, an escaped quote and a `$( )` as the shell does" (line 102); `acceptance/reads-homes.spec.luau`
Evidence: The Design says the quotes inside a `$( )` are read as the shell reads them, but no case puts a quote inside `$( )` inside double quotes. P1 (`elseif c == "(" and prev == "$" then` replaced by `elseif false then`) passes 8/8. On `x="$(echo "it's")"` followed by `./zn find c9999`, P1 reports `its quotes do not balance`, where the prototype reports one `./zn` and no imbalance. P2 (drop `and string.find(prev, "^[%s;|&(]$")`) passes 8/8. On `echo issue#1 'see ./zn` / `here' ./zn find c9999`, P2 reports an imbalance and two `./zn`, where the prototype reports one `./zn` and no imbalance. Both differences were checked with the prototype's own `singleQuoted` and `rewrites.literals`.
Critique: A Rules row whose named behaviour has no case that can fail it is the gap item 0 asks about. A later edit to the walk can drop either rule with every check green. The tempting fix is to add the mutants to the table without a case.
Consequences: none beyond two cases and two rows.
Recommendation: Add one reads-homes case with both texts as separate lines of c9999's `check.sh`, asserting `its quotes do not balance` 0 times and `c9999/check.sh: ./zn (from z-nile)` exactly 2 times (the `$(…)` line's following `./zn`, and line 2 of the `#` text). Add rows P1 and P2 to the Rules table, add them to `mutants.sh`, and rerun E3 with the outcomes recorded.
Lesson: zz-test/shell-readers-carry-state-across-lines
Erred: zz-test
Upstream: z-design

### F4 [medium] The walk is not measured on the corpus for what it loses, and its unmodelled forms can misread silently, contrary to "never skipped quietly"
Where: c0374.md Design step 1 (line 34: "a file where one of them unbalances the walk is reported (rule 3), never skipped quietly"), E1 (line 79)
Evidence: E1 records only that the 11 hits go away and that all 260 files balance. Balanced is not the same as read right. In `cat > x.sh <<EOF` / `we don't` / `test -x zn` / `it's done` / `EOF`, the walk balances and masks `zn` on line 4 with no report. Before the change, the spec judged that word as a path. 46 finished files contain `<<` and 10 contain `$'`, the two forms the Design says it does not model. No experiment lists the literals the change stops reading (the probe above finds 16, of which the Design names 11).
Critique: The design cites measure-hand-written-readers-on-the-corpus but does not follow its "How to apply". It keeps no old-versus-new experiment, and it does not list the unmodelled forms as known edges. Instead it claims a property ("never skipped quietly") that an even number of misread quotes breaks. The tempting fix is to drop the sentence.
Consequences: Making heredoc bodies modelled (skip a body to its delimiter) is more reader, with cases and mutants. Listing them as edges keeps the silent miss and must say so.
Recommendation: Commit the corpus probe as `experiments/` and record its output in E1: every literal the change stops reading over the finished files (and over `check.sh` files in open worktrees, as the lesson asks), each one judged. Also:
- list heredoc bodies, `$'…'`, backticks inside double quotes, `\$(` and `case` patterns as Known edges;
- reword step 1 to say that a balanced misreading is silent;
- add a reads-homes case pinning the heredoc reading the design settles on (modelled, so `zn` is reported, or a listed edge, so it is masked) so that a later change shows.
Lesson: zz-test/measure-hand-written-readers-on-the-corpus
Erred: zz-test
Upstream: z-design

### F5 [low] Existing work misses active c0137 (R0061), whose AC2 needs this spec green
Where: c0374.md Existing work (line 44)
Evidence: `z-nile/.tracker/issues/active/c0137/check.sh:37`: `check "AC2: c0120's finished-file and c0115's absence specs still pass" lune run tests/run -- tests/acceptance/c0120/finished.spec.luau …`. The Design's own named search (`grep -rlF "c0120/finished"` outside `done/`) finds it, but the list names only c0325, d0331, c0251 and c0369.
Critique: An active raft whose finish is blocked by today's red is the main consumer of this chore. Whoever rafts or orders work cannot see that from the document.
Consequences: none (c0137 does not edit the file, and AC2 does not pin anything c0137 changes).
Recommendation: Add c0137 to Existing work. Say that R0061's AC2 stays red until c0374 lands, and that c0374 needs no edge, since it is not in R0061.
Erred: z-design
Upstream: none

### F6 [low] No guard-scan dry run of the promoted files is recorded
Where: c0374.md Unknowns & experiments
Evidence: No experiment runs `tests/tooling/repo-fence.spec.luau` with `acceptance/reads-homes.spec.luau` and `acceptance/narrow.py` at their promoted place. This review's run passes the scan cases (the one failure is environmental, as Inputs says).
Critique: `promote-check` neither copies non-spec files nor runs the scan. The lesson asks for the run to be recorded after the last edit, so a round's fixes are covered too.
Consequences: none.
Recommendation: After this round's edits, record the run in Unknowns & experiments: copy every file of `acceptance/` to `z-nile/tests/acceptance/c0374/` in a throwaway clone, run repo-fence.spec, and give the result (and the control for any environmental failure).
Lesson: zz-test/dry-run-promoted-specs-under-the-guard-scan
Erred: zz-test
Upstream: z-design

### F7 [low] `cut()` carries dead code that exists only to quiet an unused-variable warning
Where: `acceptance/reads-homes.spec.luau:45` and `:48`
Evidence: `local spec = string.sub(text, nextLine + 1, #text)` is used only in `.. (if #spec < 0 then "" else "")`, which always appends `""`.
Critique: A reader of a sequestered spec has to work out that the two lines do nothing, and they cannot be cleaned up after promotion.
Consequences: none.
Recommendation: Delete both lines, then rerun stylua, selene and `./zn check c0374`.
Erred: zz-test
Upstream: z-design

Verdict: changes
