# Review 001: R0140 (design mode)
Inputs: base aa06e7c plus the uncommitted prep files: tracker/rafts/R0140/{R0140.md,check.sh}, tracker/issues/c0450/{c0450.md,check.sh,acceptance/override-check.spec.luau}, tracker/issues/c0460/{c0460.md,check.sh,acceptance/*.spec.luau}. I ran `tracker.sh check c0450` (2/5, the expected failures), `tracker.sh check c0460` (3/7, the expected failures) and `promote-check R0140` (OK). I also ran mutation checks on a scratch copy (scratchpad/r0140).

### F1 [high] setup-skip-gate.spec passes an inverted guard that silently removes the full gate from check.yml
Where: tracker/issues/c0460/acceptance/setup-skip-gate.spec.luau (both guard cases); c0460 Regression guard; R0140 Risks ("a spec covers the unset case")
Evidence: In a scratch copy I replaced the final stage of `scripts/setup.sh` with `if [[ -z ${PICKMAN_SKIP_GATE:-} ]]; then say "gate (skipped: …)"; else say "gate"; scripts/check.sh --full; fi` (`-z` instead of `-n`) and added a mention to SETUP.md. Result: `setup-skip-gate.spec.luau` gave 3 passed, 0 failed, and `bash -n` was OK. With this mutant, `check.yml` (which doesn't set the variable) skips the gate and reports green on every PR and on `main`. No AC catches it:
- AC7 runs `scripts/check.sh --full` directly, not through setup.sh.
- `tests/acceptance/c0010/ci-workflow.spec.luau` only checks that check.yml runs `scripts/setup.sh` with GH_TOKEN.
- OC1 looks only at the board run.

The same goes for `… || true`, a guard placed above an unconditional `scripts/check.sh --full`, or `PICKMAN_SKIP_GATE: "1"` pasted into check.yml's env (nothing asserts check.yml lacks it). All three cases match text, and the "unset or empty" case only checks that the substring `${PICKMAN_SKIP_GATE:-}` exists somewhere.
Critique: This is the one change in the raft that can disable the repo's only CI gate, and the spec meant to guard it can't fail on the most likely slip, an inverted test. The tempting fix is more text matching, such as requiring `-n` before the variable. That still passes `-n … ]] || true`, a reordered if/else, or an `else` branch that skips.
Consequences: A behavioural spec has to run the stage, but setup.sh as a whole can't run in a test (it installs tools). So the spec must cut out the stage, which means the stage needs a stable, extractable shape. The shell runs with `set -u` in setup.sh, so the extracted block must be run the same way, or `${PICKMAN_SKIP_GATE}` without `:-` (a listed mutant) would go unnoticed. A developer whose shell exports the variable would make the "unset" case lie unless the spec unsets it explicitly.
Recommendation: Replace the two text cases with one behavioural spec:
- Read setup.sh and take the block from the line starting `if [[ -n ${PICKMAN_SKIP_GATE:-} ]]` up to the next line that is exactly `fi`. Assert that this is the only block mentioning `scripts/check.sh --full`, and that no `scripts/check.sh` line appears outside it.
- In a temp dir that holds a stub `scripts/check.sh` (it echoes `GATE-RAN`), run `bash -c 'set -euo pipefail; say(){ printf "%s\n" "$1"; }; unset PICKMAN_SKIP_GATE; <block>'`, then the same with `PICKMAN_SKIP_GATE=` and with `PICKMAN_SKIP_GATE=1`.
- Expect GATE-RAN, GATE-RAN, and no GATE-RAN plus the `gate (skipped` text.

Add a case that no file in `.github/workflows/` other than `board.yml` contains `PICKMAN_SKIP_GATE`. Add Rules and mutants rows for `-z` inversion, `|| true`, `${PICKMAN_SKIP_GATE}` without `:-` (an unbound-variable error under `set -u`), and the variable pasted into check.yml. Pin the extractable block shape in Design as exact text, which it already is.

### F2 [high] The Override check relies on `scripts/affected`, which can't see the promoted specs that pin documents, and c0450's own Regression guard shows it
Where: c0450 Design ("`scripts/affected` over an issue's Touched modules lists exactly the promoted specs that could turn red"), Solution bullets 1–2, Regression guard ("Overrides: none (… no promoted spec pins skill or template text)")
Evidence: Several promoted specs read exactly the files these chores edit, as text:
- `tests/acceptance/c0410/review-skill.spec.luau` and `format.spec.luau` read `.claude/skills/review/SKILL.md`.
- `tests/acceptance/c0410/ticket-prep.spec.luau` reads `.claude/skills/ticket-prep/SKILL.md`, by section `## 3.`, where c0450 inserts its bullet.
- `tests/acceptance/c0410/table.spec.luau` reads `tracker/templates/issue/doc.md`.
- `tests/acceptance/c0010/ci-workflow.spec.luau` reads `.github/workflows/check.yml`.

`lune run scripts/affected -- .claude/skills/tracker/SKILL.md tracker/templates/issue/doc.md` prints nothing. c0450 itself admits the selector is "blind to documents a spec reads at runtime", yet makes that selector the whole mechanism of the check and of the review's "mechanical" verification. The Regression guard statement that no promoted spec pins skill or template text is false.
Critique: Tracker and process chores are the main users of the Override check, and they are exactly the issues whose overrides it misses. A prep agent and its reviewer will both write and accept `Overrides: none`, which is the false confidence the issue exists to remove. The tempting fix is a sentence saying "also think about specs that read files". That isn't mechanical and the review can't verify it.
Consequences:
- A text search reports references that aren't overrides, which is fine because the agent reads them anyway.
- It misses specs that build paths by concatenation or walk directories (`fs.readDir("tracker/rafts")` in c0410/rounds). That residual has to be stated, not hidden.
- The review must run the same two commands, or it can't detect an unnamed override.
- The c0450 spec must pin the new command in both sections, or the next skill rewrite drops it.
Recommendation:
- Make the Override check the union of `lune run scripts/affected -- <Touched modules>` and `grep -rlF -e <path> tests/acceptance`, run once per Touched path (also listed in the Affected specs paste). Do the same in review item 4.
- Add a `grep -rlF` token (or whichever exact command you choose) to the required tokens of both the ticket-prep and review cases in `override-check.spec.luau`, with mutant rows for each.
- State the directory-walk residual in Maintainability.
- Correct c0450's Regression guard: list the four c0410 specs as at risk but not overridden (the new bullet must stay inside `## 3.`, and the template must keep `## Test plan` → `### Rules and mutants` → `## Acceptance criteria`).
- Recheck c0460's Regression guard the same way. c0010/ci-workflow reads check.yml, which is untouched, so it is fine, but say so.

### F3 [high] The "chore lands first and the feature depends on it" route is unlandable or recursive as written
Where: c0450 Solution bullet 1 and Design "Why a chore and a `depends_on`"
Evidence: A promoted spec S pins behaviour X, and feature f changes X to Y. The rule says to file a chore c that "updates" S, which "lands first in its own raft", and f depends on c.
- If c makes S assert Y, `main` doesn't do Y yet. c's own "full gate passes" criterion fails, `done` refuses, and c can never land.
- The only landable reading is that c deletes or narrows S, and the documents never say so.
- c is also an issue that goes through prep. Its Touched modules contain `tests/acceptance/<id>/S`, so the Override check lists S, and c "deliberately changes" it. Read literally, the rule makes c file another chore, and the review rates any shortcut **high**.
- When the overriding issue is itself a chore, the testing skill already lets it change S, so a separate raft is pointless there.
- `tracker.sh start` doesn't check `depends_on` across rafts (only `board`'s `blockedBy` and `workstreams` within a raft read it), so "lands first" isn't enforced anywhere.
Critique: This is the core prescription of the issue, and an agent following it mechanically either produces a chore that can't pass its own gate or loops. The tempting fix is to change "updates" to "removes". Without the consequences below, that leaves a coverage gap and the chore-on-chore loop.
Consequences: Removing or narrowing S opens a window in which X/Y is unpinned. The feature's own acceptance specs must re-pin Y, and say they do. The chore needs an exemption from its own Override check. The dependency order needs someone to enforce it.
Recommendation: Rewrite the bullet and the Design paragraph:
- (a) If the overriding issue is a chore, it names S on `Overrides:` and changes S in its own raft, with no extra chore.
- (b) Otherwise the prep agent files chore c whose only job is to remove or narrow S to what f keeps, so `main` stays green. c names S on its `Overrides:` line, which satisfies the check for c itself. f's Test plan must contain a case that pins the new behaviour Y, and f's `Overrides:` line names S and c.
- (c) f's raft document lists c under Order & dependencies as "must be in done/ before `start`", and make-prompt or the executor checks this. Alternatively, file a follow-up to make `start` refuse unfinished cross-raft `depends_on`.

Add tokens to the spec so these sentences can't silently disappear: for example, `remove or narrow` in the prep section, and the self-naming exemption.

### F4 [medium] board-workflow.spec passes workflows that fail or never run on GitHub
Where: tracker/issues/c0460/acceptance/board-workflow.spec.luau; c0460 Rules and mutants; R0140 Risks ("its structure is pinned by a spec")
Evidence: Scratch runs against the Design's exact YAML gave 6/6 for the original and also 6/6 for each of these mutants:
- (a) `GH_TOKEN` env removed from the setup step. setup.sh then dies in CI with "CI: GH_TOKEN missing or invalid", because `gh api rate_limit` has no token.
- (b) `if: github.event_name == 'workflow_dispatch'` on the upload step, a plausible copy from check.yml's last step. The board is built and never uploaded on push.
- (c) a job-level `if: false`.
- (d) `continue-on-error: true` on the build step.
- (e) `group: board-${{ github.run_id }}`, so the "serializes runs" case passes while nothing is serialized.

All of these show up only after merge (E3 and OC1), which is exactly the window the spec is meant to cover.
Critique: The workflow can't run before merge, so the spec is its only pre-merge proof, and it leaves out the inputs the Design calls exact. The tempting fix is to compare the whole decoded YAML to the Design literal. That is a valid, strong option, but it fails on harmless edits such as a comment-free reformat or step names.
Consequences: Exact equality makes every later edit a spec change through a chore, which is the accepted route here. Field-level assertions keep flexibility but need one assertion per fatal field.
Recommendation: Add these assertions:
- `setup.env.GH_TOKEN == "${{ github.token }}"` (the same value c0010 pins for check.yml);
- no `if` key on the job or on any step, and no `continue-on-error` anywhere;
- `runs-on == "ubuntu-latest"`;
- `concurrency.group == "board"` (or "contains no `run_id`/`run_number`/`sha`");
- `cancel-in-progress == true` if F5 keeps a single group.

Add a Rules and mutants row for each of (a)–(e).

### F5 [medium] A dispatch on any branch can cancel the main build and become "the latest board"
Where: c0460 Design (`workflow_dispatch: {}`, `concurrency: group: board, cancel-in-progress: true`, "the newest is always the current board"), the docs row `gh run download -n tracker-board -D .cache`
Evidence:
- `workflow_dispatch` can be run on any ref once the file is on main: `gh workflow run board.yml --ref R0150-x`.
- The single global group `board` with `cancel-in-progress: true` means that dispatch cancels an in-flight `main` build.
- `gh run download` without a run id "downloads the latest artifact created" in the whole repo (gh 2.83 help), so the documented command then fetches the branch's board, whose Active tab and backlog differ from `main`.
- Two merges in quick succession also cancel the first merge commit's run, so OC1's "a successful run for the merge commit" can be legitimately absent.
Critique: The docs promise the current `main` board, and nothing in the design guarantees it. The tempting fix is `group: board-${{ github.ref }}`. That stops cross-ref cancels, but the repo-wide "latest artifact" download still returns a branch board.
Consequences: Choose one:
- Restrict the job to `main` with `if: github.ref == 'refs/heads/main'`. Dispatch then only re-runs main. This interacts with F4's "no job `if`", so pin this exact value instead.
- Or keep branch dispatch and make the documented command pick the main run: `gh run download "$(gh run list -w board.yml -b main -s success -L 1 --json databaseId -q '.[0].databaseId')" -n tracker-board -D .cache`.
Recommendation: Take the first option. It is simpler and matches the Non-goal "only `main`". Pin `jobs.board.if == "github.ref == 'refs/heads/main'"` in the spec with a mutant row (if removed or changed), and keep the short `gh run download` command in the docs.

Reword OC1 to accept the latest `main` run when the merge commit's run was cancelled by a newer push.

### F6 [low] The template's `Overrides:` request sits in an HTML comment, so a missing line can look present
Where: c0450 Design (template: "one added line in the Regression guard comment"); review item 4 ("a missing line is high")
Evidence: `tracker.sh new` copies the comment verbatim, so every new issue contains the text `Overrides:` inside `<!-- … -->` under Regression guard. A `grep Overrides:` or a quick read finds it even when the author never wrote the line.
Critique: The review is supposed to be mechanical. The comment makes "the line is missing" a judgement call.
Consequences: A visible placeholder outside the comment (for example `Overrides: <spec paths and chore ids, or none>`) is unambiguous, and an unfilled placeholder is easy to spot. The c0450 spec already accepts either form, since it only searches the section.
Recommendation: Put the placeholder outside the comment, and have review item 4 treat an unfilled placeholder as a missing line.

### F7 [low] Leftover Pages wording
Where: c0460 frontmatter `slug: pages-tracker-board`; E3 fallback "fix by a defect-free chore PR"
Evidence: The decision is "not GitHub Pages", but the slug still says pages. "Defect-free chore PR" reads as a typo for "a chore PR (not a defect)".
Critique: Slugs show in the board and in branch names (`capture-…`), which misleads a reader.
Consequences: Renaming the slug is a frontmatter edit, and no paths depend on it (documents are named `<ID>.md`).
Recommendation: Set `slug: board-artifact` (or similar) and reword the E3 fallback.

Verdict: changes
