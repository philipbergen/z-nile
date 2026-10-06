# Review 002: R0025 (design mode)
Inputs: 2f3100c (prep-ready-raft; origin/main eb2ba87); R0025.md, R0025/check.sh; c0067, c0068, c0069, c0070 (documents, check.sh, acceptance specs); `git diff origin/main -- tracker/issues/done tests/acceptance`; design-review-001.md, design-refute-001.md; scripts/tracker/{main,publish,store,board}.luau, scripts/tracker.sh, scripts/ci-verify.sh, .github/workflows/check.yml; promoted specs c0001, c0005, c0015, c0042, c0045, c0047, c0049, c0050, c0053; done check.sh files.
Dropped from review-001: none. F1, F3, F4, F5, F7, F8 and F10 are fixed as stated. F2, F6, F9 and F11 are mostly fixed; what they still miss is in F3, F4 and F5 below.

Verification run for this round:
- Case-name resolution: every `cases_pass` name in the four member `check.sh` files (42 lookups) resolves with the line-joined grep. None miss.
- `AC_LIST=1` lists 12, 7, 6 and 5 criteria for c0067–c0070 and 12 for R0025. `bash -n` passes on all five scripts.
- `stylua --check` and `selene` are clean on all six new specs.
- `cmp` confirms c0053's two replacement copies equal the promoted c0005 and c0015 specs.

### F1 [high] c0070's spec collides with c0042's fixture directory once promoted, so the full gate goes red after `done`, where nothing can fix it
Where: tracker/issues/c0070/acceptance/board-refresh.spec.luau:3, :112, :183, :239; tests/acceptance/c0042/cli.spec.luau:2, :25-29; tests/acceptance/c0049/spec-isolation.spec.luau (case "no two spec files in the repo share a fixture directory").
Evidence:
- c0049's scanner treats every literal `.cache/<[%w_-]+>` as a use of that directory. `.cache/board.html` counts as the directory `board`.
- board-refresh.spec has `{main}/.cache/board.html` three times, plus the header comment, so it uses `board`. c0042's cli.spec (`".cache/board.html"`) already uses it.
- I ran the same scan over `tests/` plus the four acceptance folders. It reports exactly one collision: `board: tests/acceptance/c0042/cli.spec.luau tracker/issues/c0070/acceptance/board-refresh.spec.luau`.
- Nothing catches it before `done`. The scanner only reads `tests/`, so RC0's `check.sh --full` runs while the spec is still in `tracker/`. `promote-check` and `done`'s `promotedChecks` run only the type check, `tests/meta/architecture.spec.luau` and the promoted specs, not c0049's spec.
- So `done` succeeds, and then Merging condition 2 (`scripts/check.sh --full` on the final head) and CI's gate fail on c0049. A promoted spec can't be edited, so the raft is stuck at merge.
Critique: the obvious fix is to rename c0070's fixture, but the collision isn't about the fixture name (`c0070-board`). It comes from naming the main checkout's board file literally.
Consequences: this applies to every spec that names the board file. c0067's ready.spec writes `{base}/board.html` under its own fixture, which is fine.
Recommendation: in board-refresh.spec, build the path without the literal, the way c0049's own spec does (`local BOARD = "." .. "cache/board.html"`, then `{main}/{BOARD}`), and reword the header comment ("its board page"). Add a prep step: run the c0049 scanner over `tests/` plus every member's `acceptance/` before the review, because `promote-check` doesn't. Optionally add an RC that runs `tests/acceptance/c0049/spec-isolation.spec.luau` with the member specs copied in, so the raft's own exit criteria catch a collision.

### F2 [high] CI's `workflow_dispatch` gate runs every readied raft's acceptance specs, so `ci-verify.sh` turns red for a correct raft once two rafts are readied
Where: .github/workflows/check.yml:28-32; scripts/ci-verify.sh; tracker skill, Merging step 3 ("dispatch one with `scripts/ci-verify.sh` … If the dispatched run fails, treat it as red"); tests/acceptance/c0001/ci-workflow.spec.luau:48-60. Not in any issue's Touched modules or Regression guard.
Evidence:
- The dispatch step runs `find tracker -path '*/active/*/acceptance/*.spec.luau'` and feeds every match to `tests/run`.
- Before this raft, only the branch's own raft was ever in `active/`. After it, `main` holds every readied raft in `active/`, and a raft branch merges `origin/main` (Phase 5, `sync`).
- Example: R0026 is readied while R0025's branch is at its merge. R0025's dispatched gate then runs R0026's sequestered specs, whose code doesn't exist, and fails.
- The Merging procedure says to dispatch exactly when the `gate` check is missing or `SKIPPED` on the final sha, which is a common case. The result is a correct raft with red CI, and the merge is blocked.
Critique: the tempting fix is to delete the step. That loses the only Linux run of a raft's acceptance specs before `done`. c0001's promoted spec also pins the literal `*/active/*/acceptance/*.spec.luau` in that step's `run`.
Consequences: the step has to find its raft from the dispatched ref. `workflow_dispatch` checks out the branch, so `GITHUB_REF_NAME` is `R0026-<slug>`. On a legacy-started raft the result is the same, because only its own raft is in `active/` on its branch.
Recommendation:
- Add `.github/workflows/check.yml` to c0067's Touched modules. Keep the literal glob and filter it by the branch's raft, for example:
  `r=${GITHUB_REF_NAME%%-*}; dirs=$(scripts/tracker.sh members "$r" 2>/dev/null) || dirs=; files=$(for d in $dirs; do find "$d" -path '*/active/*/acceptance/*.spec.luau'; done | sort)`.
- Add a c0067 check that greps both the literal glob and `members` in that step.
- Name c0001's `ci-workflow.spec` in the Regression guard (its literal must stay).
- In the Risks list, say that anything else that globs `*/active/*` now sees other rafts.

### F3 [medium] `sweepPrompts` only sweeps `tracker/rafts/active/`, but `ready` and `stop` move issue directories and backlog directories too, and an untracked file left there causes the same "duplicate id"
Where: c0067 Design, `sweepPrompts()` ("For each directory `tracker/rafts/active/<dir>`"); c0068 step 3; store.luau `store.find` (it errors when an id's directory exists in two states, whatever is inside); ready.spec "sync in the main checkout sweeps…" (it plants `.DS_Store` only in `rafts/active`).
Evidence:
- E1 shows that a pull which moves a directory away leaves its untracked or ignored files behind. `.DS_Store` is the design's own example, and Finder writes one into any folder it shows.
- Concrete failure: the main checkout has `tracker/issues/c0001/.DS_Store` and the user runs `ready R0001`. The publish moves c0001 to `active/`, and the pull leaves `tracker/issues/c0001/` behind. Then `renderPrompt` → `store.members` → `store.find("c0001")` errors `duplicate id c0001`, after the push.
- The result: the raft is readied on `origin/main` with no prompt, re-running `ready` fails the same way, and `list`, `board` and every c0070 refresh fail in that checkout.
- The same happens for `tracker/issues/active/<id>/` after a merged raft or a `stop`, and for `tracker/rafts/<R>/` after `ready`.
- Before this raft, the main checkout never had item directories moved under it except to `done/`, so this is a new exposure.
Critique: the tempting fix is to add `tracker/issues/active/` to the sweep. That still misses the backlog directories that `ready` leaves.
Consequences: the sweep then covers every state of both kinds. It must never touch a directory whose document is tracked, and it must run before `renderPrompt` in `ready`.
Recommendation: make the sweep cover every `tracker/{issues,rafts}/{,active/,done/}<ID>` directory in the main checkout whose `<ID>/<ID>.md` isn't tracked at `HEAD`. Run it in `ready` (before `renderPrompt`), `stop`, `sync` and c0070's refresh. Add ready.spec assertions:
- `.DS_Store` planted in `tracker/issues/c0001/` and `tracker/rafts/R0001/` before `ready R0001`: `ready` succeeds, both directories are gone and `list` works.
- `.DS_Store` planted in `tracker/issues/active/c0004/` before the merge in the sweep case: gone after `sync`.

Rename the function (for example `sweepStale`) and update its Rules and mutants row ("sweeps only rafts/active" is the mutant).

### F4 [medium] AC2's "out of `done/`" refusal has no spec case, so a validator that checks only the target passes
Where: c0067 AC2 ("a move into or out of `done/`"); publish-move.spec.luau:255-271 (case "a move into or out of done/ is refused"); Rules and mutants row "no published move touches done/".
Evidence: the only sub-case moves backlog c0001 to `tracker/issues/done/c0001`. No sub-case has `from` under `done/`. A mutant that checks `string.find(c.path, "/done/")` only, and never `c.from`, is refused here and passes the whole spec. It would let a published `done/ → backlog` move through. Review 001 F6 asked for both sides, and the refute says the case is "a move into or out of done/".
Critique: the case name promises both sides, so nobody will notice the gap.
Consequences: the fixture needs a done item, which no other case moves or lists. The "whole-directory move" case asserts the exact list of changed paths, so a done item added to the seed doesn't disturb it.
Recommendation: seed `tracker/issues/done/c0004/{c0004.md,check.sh}`. Add a sub-case that moves it to `tracker/issues/c0004`, consistent in every other respect (status line only, check.sh = `paths.rewrite(old, { c0004 = "tracker/issues/c0004" })`), and asserts refusal with tip unchanged. Add the mutant "only the target side checked" to the row.

### F5 [medium] RC6 runs only the ready-raft and `cmp` parts of c0053's check.sh. The c0053 checks on the tracker skill's Sync and claim text, the usage text and the publisher, which this raft rewrites, run nowhere
Where: R0025/check.sh:33-37 (RC6); tracker/issues/done/c0053/check.sh AC6 (`skills_carry_sync_and_claim`), AC7 (`usage_lists_new_commands`), AC9 (`no_index`); c0067 Design (tracker skill "Sync and claim" rewrite, USAGE, publish.luau, E5 fallback).
Evidence: c0053's check.sh requires these, and they are exactly the text and code R0025 edits:
- in the tracker skill: `new -> preparing -> prepared -> active -> done`, `paths-ignore` or `tracker-only`, `status <R-id> preparing` and `Whose claim`;
- in ticket-prep: `status <R-id> prepared`;
- in USAGE: lines starting `  status ` and `  sync `, plus `--desc` and `--fetch`;
- in `scripts/tracker/`: no `read-tree`, `update-index` or `write-tree`, and `"mktree"` in publish.luau.

c0067 rewrites the claim paragraphs ("the claim is made by `ready`, not `start`") and USAGE, and publish gains removal, where E5's fallback invites another tree-building route. None of R0025's checks runs these lines: RC5 skips c0053, and RC6 copies only its ready-raft loop and AC8. A rewrite that drops `status <R-id> preparing`, or a publisher that reaches for `read-tree`, lands unnoticed. The refute justifies the targeting by AC4's cost (it reruns every spec), but AC6, AC7 and AC9 are greps that take milliseconds.
Critique: the tempting fix is to add c0053 to RC5. That reruns every acceptance and tooling spec a third time.
Consequences: none beyond copying the greps. The c0053 functions can't be sourced without running its `check` lines.
Recommendation: extend RC6, or add an RC7, with c0053's AC6 token greps, its AC7 usage greps and its AC9 `no_index` grep, copied verbatim. Name these tokens in c0067's Regression guard next to the c0050 and c0053 wording it already lists.

### F6 [low] Nothing stops `prompt` from becoming READ_ONLY, which would turn c0053's guard spec red
Where: tests/acceptance/c0053/commands.spec.luau:443-462 (the `writing` list includes `{ "prompt", "c0001", "--stdout" }`, which must fail with `repository root` in a `.git`-less sandbox); c0069 Design ("prompt writes nothing anywhere"); main.luau `READ_ONLY`.
Evidence: after c0069, `prompt` is a pure reader. The tracker skill already lists it among the read-only main-checkout commands, so adding it to `READ_ONLY` is the natural tidy-up. If that happens, the sandbox call gets "prompt takes a raft id" instead of the guard's message, and the c0053 case fails. c0067 says "`READ_ONLY` is unchanged" for `ready`, but c0069 is silent.
Recommendation: in c0069's Design and Regression guard, say that `prompt` stays out of `READ_ONLY` (the guard still runs first) and name the c0053 case. `ready` and `stop` stay out of it too.

### F7 [low] Leftover and inconsistent text an executor will trip on
Where and evidence:
- c0067 AC1 ("`paths.normalize` makes a rewritten text equal to its original"), c0067/check.sh:25 (label "paths.rewrite and paths.normalize") and R0025.md:39 (the paths row) still name `normalize`, which the Design dropped (review 001 F6). The spec doesn't call it.
- RC4 (`! grep -qw "launch"`) and prompt.spec:249 (`has(usage, "launch")`) fail if USAGE mentions `/launch-raft`. With `-w`, `launch-raft` matches, and the spec's check is a plain substring. No document says USAGE must not name the skill, and the `ready` line ("…then /launch-raft R") is a natural place for it.
- c0070 E7's fallback ("the spec compares the embedded data block only") edits a sequestered spec, which execution can't do. `board.luau` has no time source, so the risk is small, but the fallback should be "stop and escalate".
- c0070 calls `sweepPrompts()` "in the root" from a worktree's process, but c0067's signature has no root and its text says "run in the main checkout". Give it a `root` parameter (`git -C root …`).
- c0067's `start` refusal "is readied on origin/main: run tracker.sh sync first" (review 001 F11) has no spec case and no Rules and mutants row.

Recommendation: remove `normalize` from AC1, the RC label (it's a prep-time `check.sh`, so it can still change) and the raft table. Add "USAGE never contains the word launch, including `/launch-raft`" to c0069's USAGE section. Change E7's fallback to escalate. Give `sweepPrompts` a root. Add a one-assertion ready.spec case for the pre-ready worktree refusal, or mark its row `reasoned`.

Verdict: changes
