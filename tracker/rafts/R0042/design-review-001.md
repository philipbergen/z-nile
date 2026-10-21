# Review 001: R0042 (design mode)
Inputs: branch `prep-z-nile` at 59ed0a9 plus the uncommitted prep tree: `tracker/rafts/R0042/{R0042.md,check.sh}`, `tracker/issues/c0114..c0118/{<id>.md,check.sh,acceptance/*}`, `tracker/issues/c0117/experiments/rank.luau`; compared with `scripts/tracker/{main,store,ledger,publish,claims,board}.luau`, `scripts/tracker.sh`, `scripts/check.sh`, `scripts/affected.luau`, `scripts/lib/graph.luau`, `tests/lib/trackerfix.luau`, `tests/acceptance/c0082`, `c0084`, and the architecture, testing and tracker skills.

### F1 [high] c0114: a missing `projects.toml` is an error, but no tracker fixture carries one, so about 26 promoted spec files go red, and AC2 itself cannot pass
Where: c0114 Design ("`read` fails if the file is missing", "Finds walk every root in `projects.read`"); `Overrides: none`; `tests/lib/trackerfix.luau:46-49`; `tests/acceptance/c0082/cli.spec.luau` setup
Evidence: `trackerfix.new` copies only `scripts/` and `tracker/templates` into the fixture. `c0082/cli.spec` and the other self-built fixtures copy `scripts` and `.luaurc`. 26 spec files under `tests/` build a tracker this way (`rg -l` on trackerfix and the `cp -R scripts` pattern). None of them has `z-nile/projects.toml`. If every `find` (and so `get`, `members`, `ready`, `status`, `audit`, `list`) calls `projects.read`, which "fails if the file is missing", every one of those specs fails. If the implementer softens this to "missing file means pickman only", then c0114's own AC2 fails: `home.spec` "create lands in the named root" runs `--project z-nile` in a plain `trackerfix.new("c0114-home")` fixture, where z-nile is not a known project. The only way out is to edit `tests/lib/trackerfix.luau`, which is not in Touched modules, and the overrides are declared as `none`.
Critique: The design contradicts its own spec and silently overrides the promoted suite. The tempting fix is "default to pickman when the file is missing" plus a quiet trackerfix edit.
Consequences: A silent default means a typo'd or deleted `projects.toml` on main quietly drops the z-nile root: its issues vanish from `find`, and ids there can be handed out again. A trackerfix edit is a `tests/lib` change (a full run), and the self-built fixtures (c0082 and similar) would still lack the file.
Recommendation: Decide the rule explicitly. A missing file is the single project `pickman` at `tracker`, and that is the only fallback. A file that exists but is malformed is an error. Add `tests/lib/trackerfix.luau` to Touched modules, with a `projects` seed option (or copy `z-nile/projects.toml` when it is present), and say so in the design. Add spec cases for: a missing file gives pickman only; a duplicate id is an error; an empty root is an error. Re-run the Overrides audit (`grep -rlF scripts/tracker tests/` and the fixture builders) and list the result, even if it is still none.

### F2 [high] c0114: the second root is half-wired; publish, claims, ids, ready, stop, status, compact, audit and board all hard-code `tracker/`
Where: c0114 Design ("Other commands that already take an id find the item by scanning every project root"); Touched modules lists only `projects.luau`, `main.luau`, `store.luau`
Evidence:
- `publish.allowed` (`scripts/tracker/publish.luau:29`) accepts only `^tracker/(issues|rafts)/…`. `new issue` publishes when `publishing()` is true (main.luau:694-745), so AC2's `z-nile/tracker/issues/<id>/<id>.md` is refused with "is not a tracker item file".
- `claims.taken` greps only `-- tracker/` (claims.luau:17), so a claim stamp used in z-nile is not seen, and stamps stop being unique.
- `idsOf`, `docPath`, `stateOfPath`, `moveOnOrigin` (used by `ready` and `stop`), `compact`, `audit`, `history` and `board.build({root}/{store.ROOT})` read `tracker/` (29 literal uses in main.luau alone).
- The design never says whether z-nile ids share the `tracker/next` counter. If they don't, c0120 can exist in both roots, and a "find walks every root" hits two directories.

Critique: The design describes `new` and `find`, but a z-nile issue that can be created cannot be readied, stopped, status-moved, audited, compacted or claimed safely. The raft's purpose (z-nile has its own tracked issues) is not met, and the executor has to design all of this mid-flight. The tempting fix is to replace `store.ROOT` with a loop everywhere.
Consequences: A loop everywhere touches the publish guard (see F3), the claim uniqueness rule (R0025), the compaction map and `renamed.luau`, and duplicate-id detection across roots. Each of these is a separate decision.
Recommendation: Either (a) shrink scope: keep every item in `tracker/` and add a frontmatter key `project: <id>` (default `pickman`) that `new issue --project` writes and the view filters on. `projects.toml` then only names tabs. This needs no publish, claim, counter or compaction change, and it fits "No tracker document moves between roots". Or (b) list every command in a table with its behaviour for a z-nile item, and pick one id space (one `tracker/next` and one claim namespace over all roots). Add `publish.luau`, `claims.luau`, `ids.luau`, `compact.luau`, `audit.luau` and `history.luau` to Touched modules, and add spec cases for `ready`/`stop` of a z-nile raft and for the same id existing in two roots. I recommend (a).

### F3 [high] c0114: widening the publish guard to roots read from `projects.toml` opens a path for unreviewed writes to main
Where: c0114 Design (`read` validates only "an id repeats, or a root is empty"); `publish.allowed`
Evidence: To make AC2 publish, `publish.allowed` must accept `<root>/issues/...` for each project root. As designed, `root = "src"`, `root = "."` or `root = "../x"` passes `read`. A branch that edits `z-nile/projects.toml` in its working tree would then let `tracker.sh` push `src/issues/c0010/c0010.md`, or with `.`, `issues/...` at the repo root, straight to `origin/main` without a PR.
Critique: `publish` is the one path that writes to main without review. Its whitelist is a guard, and the design widens it from a file the branch controls.
Consequences: If the root list is read from the working tree, any branch can redirect publishes. If it is read from `origin/main`, a new project needs a PR to main before its first issue, and the c0114 PR itself must land the file before AC2 can publish in production. That is fine, but it should be stated.
Recommendation: If F2 option (b) is kept: `projects.read` rejects absolute paths, `..`, `.` and any root that is not `tracker` or `<seg>/tracker`. `publish.allowed` takes its root list from `origin/main`'s `z-nile/projects.toml` (the same `read(path)` the publish callback already has), never from the working tree. Add spec cases for `root = "src"` and `root = "../x"` being rejected, and for a working-tree-only project root being refused by publish. Option (a) in F2 removes this finding.

### F4 [high] c0114: AC2 can be passed by printing the right path, and the find-across-roots rule has no spec
Where: `c0114/acceptance/home.spec.luau` "create lands in the named root"; Rules and mutants table; Implementation step 4
Evidence: The case asserts only that stdout contains `z-nile/tracker/issues/`. An implementation that writes to `tracker/issues/` and prints `z-nile/tracker/issues/...` passes. "`find` walks every project root" (step 4, and the basis of "a z-nile issue is found without the flag") has no row and no case, and neither have `list --project` or the three `read` errors. The table also says "The three cases fail on today's tracker", but "omitted flag uses pickman" passes today: `new issue` already prints `tracker/issues/c…`.
Critique: The criterion that defines the feature can be faked, and the behaviour that other issues rely on (c0116's "same project root", c0118's per-project view) is unspecified.
Consequences: Checking the file on origin needs a `git show origin/main:<path>` in the fixture, which is cheap and stays in `.cache`.
Recommendation: In AC2, assert that `git -C <fixture> show origin/main:z-nile/tracker/issues/<id>/<id>.md` succeeds and that `tracker/issues/<id>` does not exist. Then assert that `tracker.sh find <id>` with no flag prints the z-nile path. Add rows and cases for `find` across roots, for `list --project z-nile` excluding pickman ids, and for the `read` errors from F1. Correct the "fail on today's tracker" sentence.

### F5 [high] c0115: two copies of every skill; the tooling and the harness keep using the old ones, and they drift from the first edit
Where: c0115 Solution and Design; `scripts/tracker/main.luau:2537-2563` (`SKILLS_INLINED`); AGENTS.md
Evidence:
- `renderPrompt` inlines `.claude/skills/{execute-raft,tracker,architecture,testing,review}/SKILL.md` into every readied raft's `prompt.md`. After c0115, AGENTS.md says to read `z-nile/skills/*`, but every executor prompt still contains the old files.
- The harness discovers skills only under `.claude/skills/<name>/`, so `/z-run`, `/z-ready` and `/z-raft` do not exist as invocable skills.
- c0116 then edits only `z-design` and `zz-rules`. From that point `ticket-prep` (still discoverable, still described by `tracker/SKILL.md` lines 57 and 62) and `z-design` disagree about raft creation, and the prompt carries the old `tracker` rules without `recombine`.

Critique: The issue's stated goal (an agent can see which names are the pipeline) is undone by having two sources of truth. "Old paths stay because specs pin them" treats the promoted specs as untouchable. But this is a chore, and the review skill allows a chore to override promoted specs itself, with every one named in its `Overrides:` line.
Consequences: Actually renaming means updating the promoted specs that read `.claude/skills/<old>` (c0003, c0043 ×3, c0047, c0048, c0050, c0052, c0057, c0064, c0081, c0082, c0107, and `tests/tooling/ready-members`, `start-pr-reuse`), `SKILLS_INLINED`, the `ready` error text ("ticket-prep makes one", main.luau:2674), AGENTS.md's table, and the tracker skill's cross-references.
Recommendation: Keep one copy. Move the skills to their new names under `.claude/skills/` (where the harness finds them), or keep the sources in `z-nile/skills/` with `.claude/skills/<new>` symlinks. Delete the old directories. List every pinned spec in `Overrides:` with the path change, and update `SKILLS_INLINED`. Add a spec case that `renderPrompt`'s inlined paths all exist and none is an old name, and one that no `.claude/skills/<old>` directory remains. If the author keeps the copies anyway, the design must say which copy each tool reads and add a spec that every old/new pair is byte-equal except the named c0116 edits.

### F6 [medium] c0115: every AC passes with empty files, and the affected-spec claim is false
Where: `c0115/acceptance/names.spec.luau`; c0115 "Affected specs"
Evidence: `skill(name)` checks only `fs.isFile`, so eleven empty `SKILL.md` files pass AC1 and AC2. AC3 passes with one line, `tracker skills dispatcher .models.toml board`. `lune run scripts/affected -- AGENTS.md` prints nothing (run during this review), not `ALL` as the document says, so the "full gate is the regression" reasoning rests on a wrong premise.
Critique: The testing skill requires "at least one case that a hard-coded or partial implementation would fail".
Consequences: A content check has to survive c0116's edits to `z-design` and `z-raft`.
Recommendation: For each new `SKILL.md`, assert frontmatter `name: <dir>` and a non-empty `description:`. For each copied skill, assert that its source's first `# ` heading line (or another stable marker) is present. Assert that `z-run` contains a marker from both launch-raft and execute-raft. For the README, assert that the flowchart block (```` ```mermaid ````) comes before the first paragraph. Correct the Affected specs text.

### F7 [high] c0116: the z-raft policy can't be carried out: `new raft` refuses prepared issues, and `ready` sends raftless issues back to ticket-prep
Where: c0116 Problem and Design ("`z-design` designs one issue to `design: ready` and status `prepared`… `z-raft` groups prepared issues"); `main.luau:815-818`, `2672-2675`; tracker skill lines 57 and 62
Evidence: `new raft` returns "`{id} is {st} on origin/main, not new`" for any member whose effective status is not `new`. After `z-design`, every issue is `prepared`, so `z-raft` with no argument cannot create any raft with today's command, and c0116 does not change `new raft` ("does not change `new raft`"). `ready <issue>` fails with "has no raft: ticket-prep makes one". The tracker skill still says "A lone issue gets a `single: true` raft made by ticket-prep" and "a raftless issue goes back to ticket-prep". A raft made after design also needs its own `design: ready` (main.luau:2735) and a `prepared` status, and nothing says who sets them.
Critique: The core workflow change is unimplementable as written, and the rules skill contradicts it. The tempting fix is to let `new raft` accept `prepared` members.
Consequences: Accepting `prepared` members means `new raft` must preserve their status, or re-stamp them with the raft's claim, which interacts with R0025's claim stamps and `stop`. The raft document needs a design state that doesn't wait for a design review it never had.
Recommendation: Specify a `new raft` change. With `--prepared`, or by default, it accepts `new` or `prepared` members that have no raft, stamps the raft `prepared` with `design: ready` when every member is `design: ready`, and leaves member statuses unchanged. Add `main.luau`'s `new raft` and `ready` messages to the design, and update `zz-rules` and the tracker rules (see F5) so "raftless goes back to ticket-prep" becomes "goes to z-raft". Add spec cases: `new raft` over two prepared chores succeeds, and the result can be readied; `new raft` over an `active` issue is refused.

### F8 [high] c0116: recombine's write path is unspecified and the publish guard forbids it; the spec misses the keeper's list and two refusal rules
Where: c0116 Design (`recombine <keeper> <retired>`); `publish.luau:381-387`; `recombine.spec.luau` "members move"; Rules and mutants table
Evidence:
- The design doesn't say whether recombine publishes to `origin/main` (as `new` and `status` do) or edits the worktree. Publish refuses any change to an existing document other than its `status:` line, and it has no deletion. So rewriting `raft:` and `issues:` and removing `tracker/rafts/<retired>` cannot publish. Until a PR lands, origin/main keeps the retired raft, which another session can `status`, `ready` or claim.
- The moved issue keeps the retired raft's claim stamp, so the keeper's claimed set (claims are "exactly the issues carrying the raft's own stamp", main.luau:2807-2811) is split.
- The spec checks only `b`'s `raft:` line and that the directory is gone. A mutant that never adds `b` to the keeper's `issues:` passes, yet `ready` then fails with "issues: list and its members' raft: fields disagree" (main.luau:2718-2724).
- "Refuses unless both are backlog" and "same project root" have no row and no case.
- Deleting the retired directory also deletes its `design-review-*.md`, which `metrics` counts.

Critique: AC1 can be passed by an implementation that leaves an unreadyable raft, and the concurrency story is missing.
Consequences: Making recombine a local edit means it lands only by PR (a capture `land` refuses `raft:` and `issues:` edits), so it runs in a prep worktree. Re-stamping members needs the keeper's stamp.
Recommendation: State that recombine runs in a prep worktree, edits the tree, and lands with the prep PR. It first publishes a status-only claim of both rafts (and their members) with the keeper's stamp, so other sessions see them as held. Then it rewrites the `issues:` lists, `raft:` fields and member statuses, and refuses when the retired raft has review files (or moves them). Add spec assertions: the keeper's `issues:` contains `a` and `b`; `b`'s status equals the keeper's; `tracker.sh ready <keeper>`'s member check passes (or `audit` is clean). Add cases: recombining an `active/` raft is refused and moves nothing; rafts in two projects are refused (or drop that rule if F2 option (a) is taken).

### F9 [high] c0117: AC4 and AC5 can be passed by wrong implementations, and model cells are not protected by append-only
Where: `c0117/acceptance/models.spec.luau` "ready is a script", "nine columns stay, model cell round-trips"; Rules table; `ledger.luau:218-228` (`same`)
Evidence:
- `dispatch.plan` returning `script` for every skill passes AC4. Nothing asserts that `z-design` or `z-run` is `model` with the given spec.
- The AC5 case calls only `ledger.parse`. It never calls `render`, `append` or `appendOnly`. So the listed mutant "always write ten cells" is not killed, and neither is "render drops the model cell". The case's 9-cell half passes today.
- `same()` compares every field except anything new. Unless `model` is added to it, `appendOnly` lets a publish rewrite an already-published row's model, and `ledger.extends` treats a changed model as the same row.

Critique: The rows table claims kills that the spec cannot make, and the change opens a hole in the append-only rule.
Consequences: Including `model` in `same` means a 9-column file re-rendered as 10 columns must give `nil` models for old rows, which the parse of an empty 10th cell must preserve, not turn into `""`.
Recommendation: AC4: add `plan("z-design", spec)` gives `kind == "model"` with the same spec, plus `plan("spend", spec)` and `plan("recombine", spec)` give script. AC5: render rows without a model and assert `ledger.HEADER` with nine cells; append a row with a model and assert a ten-cell header, the earlier rows parsing back with `model == nil`, and the new row with its model; then `appendOnly(old, new)` gives nil, and `appendOnly` of a file where row 1's model changed returns an error. Add `model` to `same`, and add a row to the rules table.

### F10 [medium] c0117/c0118: code under `z-nile/` is outside the gate: not formatted, linted or type-checked, and invisible to `--affected`
Where: R0042 Whole-raft design ("New files live under `z-nile/`"); `scripts/check.sh:27` `LUAU_DIRS=(src tests scripts tracker)`; `scripts/affected.luau` FULL_RUN_PATTERNS and `graph.build({ "src", "tests" })`; `models.spec.luau:14-17`
Evidence: `lune run scripts/affected -- z-nile/engine/models.luau` prints nothing (run during this review). The c0117 spec loads modules with ``require(`@znile/{name}`)``, which `graph.build` records as `dynamic`, so even after promotion no edge leads from the spec to `models.luau` or `dispatch.luau`. `z-nile/engine/*.luau` requiring each other is never scanned, because `z-nile` is not a graph root. The testing skill: "Reliability depends on … literal requires."
Critique: The stop hook and stream checks run `--affected`, so a regression in `z-nile/engine` passes locally and is caught only by `--full`. Stylua, selene and luau-lsp never see the new Luau.
Consequences: Adding `z-nile` to the graph roots also subjects it to `tests/meta` architecture rules written for `src`. Those should apply only to `src` (they already key on the `src` prefix).
Recommendation: Add `z-nile` to `LUAU_DIRS`, to the luau-lsp tests+scripts analyze line, and to `graph.build`'s roots in `scripts/affected.luau`, or add `^z-nile/` to FULL_RUN_PATTERNS. Put `scripts/check.sh` and `scripts/affected.luau` in Touched modules. Replace the dynamic `load` with literal `require("@znile/models")` and `require("@znile/dispatch")` (the spec is sequestered, so fix it now in prep). Add a tooling case: `affected -- z-nile/engine/models.luau` selects the c0117 spec.

### F11 [medium] c0117: the dispatcher solves none of the stated Problem, and key rules are unspecified or untested
Where: c0117 Problem, Design, Rules table
Evidence:
- Nothing calls `dispatch.plan`. There is no `tracker.sh` command and no adapter, so "nothing stops an agent from being started for them" remains true after the issue.
- `resolve(repo, dir, skill)` takes a directory, but the design never says which directory an issue or raft maps to (its document under `tracker/issues/<id>`? its Touched modules?). So "a game drops a `.models.toml`" has no defined effect.
- What `resolve` returns for a skill that no file names is unspecified, though the type is non-optional and "Nothing defaults to Cursor". So is `strongest({})`.
- "A model with no rank is an error" and "Any other runtime is an error" have no rows.
- `tracker.sh spend --model` exists, but `commit` (phases `build` and `code-review`) has no `--model`, so every code-review row stays `unrecorded` and c0118's "tokens by model for code-review" chart can never show a model.

Critique: These are the decisions an executor would otherwise have to invent.
Consequences: Mapping an issue to a directory by Touched modules gives several dirs per issue, which then need `strongest` too.
Recommendation: Specify the dir rule (I suggest: the issue's tracker root's parent, so `tracker/` maps to the repo root and `z-nile/tracker/` to `z-nile/`), and specify that an unnamed skill or an empty list is an error naming the skill. Add `commit --model <id>`. Either add a `tracker.sh dispatch <skill> <id> --dry-run` that prints the plan, or restate the Problem to match the scope. Add rows and cases for the missing rank, an unknown runtime and an unnamed skill.

### F12 [high] c0118: no command writes the page's JSON, the page's actions can't run, and AC5 passes trivially while forcing hard-coded ids
Where: c0118 Design ("`z-nile/board/index.html` reads a JSON file the command writes"; "The only actions are stop, retry, and open"); Touched modules; `view.spec.luau` "page"
Evidence:
- Touched modules has no `main.luau` or `tracker.sh` change, and no command or output path is named, so nothing produces the JSON.
- A static HTML page cannot run `tracker.sh stop` or "retry" (and c0117 provides no dispatcher entry, see F11).
- AC5 accepts any file containing `pickman`, `z-nile` and `24` (`24px` or `2024` will do). The listed mutant "render one combined canvas" passes. A correct page that builds its tabs from the JSON, as the design says ("one button per project id"), would contain no literal project ids and fail AC5.

Critique: The deliverable can't be produced from the documents, and its only check rewards the wrong design.
Consequences: Generating the HTML from Lune (as `board.luau` does with `board.html`) makes it testable without a browser, but `tests/run`'s no-browser guard means any `open` must be `-O` style.
Recommendation: Add `tracker.sh view [--out PATH] [-O]`, writing `.cache/z-nile-board.html` with the view model embedded. Put `main.luau` in Touched modules. Make the actions "open" links plus copyable `tracker.sh stop/ready` command text, or drop stop and retry from this issue. Rewrite AC5 against `view.render(projects)` on a fixture with two projects named `alpha` and `beta`: one tab per id, no tab for an unlisted id, and a `data-done-hours="24"` default with bounds 1 to 720.

### F13 [high] c0118: week bucketing and five of six column mappings are untested; AC1 and AC2 run against the live repository
Where: `view.spec.luau` "two projects", "done column", "week counts"; c0118 Design (column rules, ISO week); Rules table
Evidence:
- "week counts" calls `view.tally` on a file list. No raft, date or week is involved, so the listed mutant "count backlog rafts too" cannot be killed, and an off-by-one ISO week (Sunday versus Monday, or 2026-W53 against 2027-W01) passes.
- Only `done` is checked. Mapping every other status to `ticket` passes. Statuses on disk carry stamps (`preparing-raging-heron-sunny`, `active-…`), and the design maps bare words.
- The `ready` column is "prepared with a raft", while `z-ready` moves a raft to `active` (which maps to `run`). The column names contradict the skill names.
- AC1 and AC2 read the real tree. `z-nile/tracker` is empty there, so AC1's loop over z-nile cards checks nothing, and any non-nil `doneAt` (for example `"x"`) passes AC2. The results also change as the repository changes.

Critique: The behaviours most likely to be wrong are not specified by any case, and the live-tree cases are neither deterministic nor hard to fake.
Consequences: A fixture needs controlled commit times. `GIT_COMMITTER_DATE` on fixture commits stays inside `.cache`.
Recommendation: Build the AC1 to AC3 cases on a `trackerfix` fixture (with the projects seed from F1) that contains: one item per status (stamped forms included), each asserted to its column; a done raft moved with a commit dated Sunday 23:59 UTC and another Monday 00:00, landing in adjacent ISO weeks; a backlog raft with review files counted nowhere; and a z-nile issue absent from pickman's view. Assert `doneAt` equals the fixture commit time. Rename the `ready` column (for example `rafted`) or redefine it as the readied state, and say how `effective` status is used (`statusLib.effective`). Reuse `history.read` for the done times rather than one `git log` per item.

### F14 [medium] c0118: the view's data sources (worktrees, GitHub, checks) are unspecified, so the gate may make network calls
Where: c0118 Problem ("reads the tracker, worktrees, and GitHub"; click for "the PR, the checks, the model, and the spend"); `Card` type
Evidence: `Card` has only `id`, `column` and `doneAt`, so PR, checks, model, worktree and spend have no fields. If `view.projects(root)` fetches them (via `gh` or `git worktree list`), the AC1 and AC2 specs make those calls against the real repo in every gate run. On CI, `gh` may lack auth, and the testing skill lists network actions from checks as "caught only by review".
Critique: The executor must invent the card data and might put I/O in the pure view.
Consequences: Splitting reading from shaping keeps `view` testable.
Recommendation: Make `view.build(input)` pure over a plain input record (items, spend rows, worktree list, PR map), with a separate reader. Only the CLI calls `gh`, and the reader returns an empty PR map when `gh` is missing. Add the card fields to the type, and state that specs never call the reader on the real repo.

### F15 [low] Smaller inconsistencies
Where: c0114 Design, R0042 diagram, c0114 Problem
Evidence:
- c0114 says `--project <id>` goes "before the subcommand", but the spec passes it after `new issue c …`.
- `z-nile/tracker/issues` and `rafts` are empty folders that git won't keep without `.gitkeep`.
- c0114's title and Problem say the engine and skills "move under `z-nile/`", but its Solution keeps them in place.
- The R0042 diagram draws `dispatch --> ledger.luau`, which no design implements.
- E1 tests a prototype's own `apply` function, not TOML loading or the walk, so it proves little.
- R0042 has no end-to-end raft check (a z-nile issue appearing in the z-nile view).

Critique: Each is a question an executor would have to ask.
Consequences: none
Recommendation: Pick one flag position and match the spec. Add `.gitkeep` files. Retitle c0114 to match its Solution. Fix the diagram. Either drop E1 or make it parse two real TOML strings with `serde.decode("toml", …)`. Consider an RC2 that creates a z-nile issue in a fixture and finds it in `view.projects`.

Verdict: changes
