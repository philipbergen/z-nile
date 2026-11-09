# Review 008: c0246 (design mode)
Inputs: prep worktree at b403cd39 plus its uncommitted draft (`c0246.md`, `check.sh`, `acceptance/paths.spec.luau`, `harvest.md`, `design-review-001..007.md`, `design-refute-001..007.md`, the lesson notes on `zz-arch/guards-decide-from-the-tools-resolution.md` and `z-design/spec-design-correspondence.md`, `zz-test/lessons/sort-cases-defeat-pre-order.md`). Also read: `z-nile/lib/graph.luau`, `z-nile/tests/lib/home.luau`, `c0184/homes.spec`, `c0185/library.spec`, `rokit.toml`, `SETUP.md`, `z-nile/lib/workspace.luau`, `./zn capture c0246` (capture 65cfc7b2, no marker), and the lead's prototype `proto8/` (graph.luau, home.luau, README.md).
Prototype: I copied `git archive HEAD`, the c0246 folder and `proto8/` into a scratch `git init` copy (committed as `r@example.invalid`). `paths.spec` passes 13 of 13. Check AC7's list passes too (with the prototype, 51 of 51 together with `paths.spec`). `homes.spec` and `library.spec` take about 0.9 s more than on main's `home.luau` (2.0 s against 2.9 to 3.4 s for the pair plus `paths.spec`). Every real top-level project file gets exit 0 from `rojo sourcemap --include-non-scripts`; the largest lists 42 file nodes. Rojo fixtures were under the scratch copy's `.cache` and were removed afterwards. Every probe ran with Rojo 7.7.1 through `./zn run`, except one read-only count of `filePaths` over the seven real project files, which I ran directly.
Dropped from review-007: none repeated. Round 7's F1 (casing) and F2 (loop assertion) are closed by the redesign. Rojo reports `DEFAULT.PROJECT.JSON` as `default.project.json`, and the loop case now asserts that the net prints no line.
What I probed against the net's completeness, and found sound: meta files (`init.meta.json` alone in a folder, `init.meta.json` next to `init.luau`, `a.meta.json` next to `a.luau`), `.model.json`, `.csv`, `.toml`, `.yaml`, `.txt` and `.json`, all in a folder outside the home that a link reaches. Each one appears in `filePaths`. Meta files are listed lexically through the link (`src/a/O/onlymeta/init.meta.json`) and the others by their target (`../out/files/a.luau`). `realpath` resolves both to the outside folder. Neither an empty folder nor a file of unknown extension is read. A file name with an embedded newline adds a line, so `realPaths` sees a count mismatch and fails closed. Paths are prefixed with `{top}/{h}/`, so none begins with `-`.
Scope (item 11): the Problem keeps the capture verbatim and adds four dated decisions. The 2026-11-08 decision brings in the Rojo-driven check, and AC5 and AC6 carry it. Every outcome has a Design and a Checked AC. The 2026-11-07 line's "a Rojo-driven check … separate chores" is superseded by a dated later line, so it is not a contradiction.

### F1 [high] The net allows the library's two folders wherever Rojo puts them. A chained link or a `syncRules` project puts `arcade/src/server` into `ReplicatedStorage`, and nothing is reported.
Where: Design, "The Rojo-driven check", third bullet ("every file Rojo reads must lie, by its real path, inside the real path of the home or of the library's `src/shared` or `src/server`"). Prototype `home.luau`, the `roots` loop. Rules row "the library's two folders are the one place outside the home Rojo may read".
Evidence (run, prototype `home.problems` plus `rojo sourcemap` and `rojo build` on a fixture home `pong`): `pong/default.project.json` is a DataModel that maps `../arcade/src/shared` at `ReplicatedStorage/Arcade`, `src/shared` at `ReplicatedStorage/Game` and `../arcade/src/server` at `ServerStorage/Arcade`. `arcade/src/server/Secret.luau` is `return 'server secret'`.
- Chained link: `pong/src/shared/L -> ../../stash` and `pong/stash/S -> ../../arcade/src/server`. The rule prints no line. The sourcemap lists `Secret` at `/ReplicatedStorage/Game/L/S/Secret` from `../arcade/src/server/Secret.luau`, and `rojo build` succeeds with the server source in the place twice. The old `find -type l` check sees only `L`, which stays inside the home. The net sees a real path inside `arcade/src/server` and accepts it.
- `syncRules`: the same tree plus `"syncRules": [{"pattern": "*.txt", "use": "project"}]`, and `pong/src/shared/ev.txt` = `{ "name": "Leak", "tree": { "$path": "../../../arcade/src/server" } }`. The rule prints no line. The sourcemap lists `Secret` at `/ReplicatedStorage/Game/Leak/Secret`, and the build holds it twice.
- A direct link `src/shared/S -> ../../../arcade/src/server` is still caught by the old line (`holds a link out of the home`).

Round 7's design reported both routes: `loadedFrom` answered "link" for any link out of the home at any depth, and any `syncRules` key got a line. The redesign dropped both and put a position-blind allowance in their place. The reader's own rule pins each library folder to one node (`maps the library's … at …, which is not its node`), because the server folder must never replicate to clients. The net does not carry that judgment over.
Critique: this is the class the redesign claims to close "by construction". The net answers "where is the file from" but not "where does Rojo put it". The library allowance is the one place where the second question decides the answer. Two fixes are tempting: restore the `syncRules` line, or add `find -L` for chained links. Either one rebuilds a model of Rojo's discovery, which is what the user's 2026-11-08 decision replaced.
Consequences: the sourcemap already prints the instance tree, so the net can judge position from Rojo's own answer:
- `rojoReads` returns each file with its instance path (the names below the root node, joined with `/`).
- The root node is the project's `name`, so it is not part of the path.
- The check applies to every project file of every home, the library's own included. Arcade's files are inside its home, so the library check must run before the home check, or arcade's own misplacement passes. The real tree is clean under it.
- A file the home maps correctly and also, through a link, a second time gets a line only for the misplaced copy.
- A non-place project file (a `Folder` root) that maps the library is held to the node too, as the reader's rule already holds it.
I sketched it on the prototype in about twelve lines. Both fixtures above got exactly one line: `makes Rojo put ../arcade/src/server/Secret.luau at ReplicatedStorage/Game/L/S/Secret, which is not the library's node (ServerStorage/Arcade)`. The clean fixture stayed clean. `paths.spec` and AC7's list, the real tree and c0185's `libraryHome` fixture included, passed 51 of 51.
Recommendation:
- In the Design, `rojoReads` returns `{ file, instance }` pairs.
- A file whose real path lies in `LIBRARY_SHARED` or `LIBRARY_SERVER` must sit at or below that folder's node (`ReplicatedStorage/Arcade`, `ServerStorage/Arcade`). If it does not, the line is `<file> makes Rojo put <path> at <instance>, which is not the library's node (<node>)`, once per file, and the check runs before the inside-the-home test.
- Add an AC5 or AC6 case with the two fixtures above (chained link, and `syncRules` with `ev.txt`), each expecting exactly one such line, plus the clean DataModel fixture expecting none.
- Add the Rules row "a library file Rojo reads sits at its node | that case | N12: the library roots accepted at any instance | run".
- Restate in the Design and the README sentence that the net judges where Rojo puts a library file, not only where the file comes from.
Lesson: zz-arch/guards-decide-from-the-tools-resolution

### F2 [medium] Two plausible mutants of the inside test survive every spec: the roots without their trailing `/`, and the whole library home allowed in place of its two folders
Where: Design, the inside test ("inside the real path of the home or of the library's `src/shared` or `src/server`"). Prototype: `local roots = { base[1] .. "/" }` and `for _, lib in { LIBRARY_SHARED, LIBRARY_SERVER }`. Rules and mutants table, which lists neither.
Evidence (run on the prototype, with `paths.spec` plus check AC7's list):
- Ma, the prefix test without the slash (`roots = { base[1] }` and `at[1]`): every case passes. A probe with a chained link `pong/src/shared/L -> ../../stash` and `pong/stash/S -> ../../pong2` gets `default.project.json makes Rojo read ../pong2/x.luau, which is outside the home` on the intended code and no line at all under Ma. `pong2` stands for any sibling whose name starts with the home's name (`snake-old`), and also for `arcade/src/shared-x` against the library root.
- Mb, the library roots widened to `LIBRARY_HOME`: every case passes, so `arcade/tests` or any other folder of the library, read through a chained link or `syncRules`, would be accepted.
- The fixtures read only `x/` and `outside/`, which share no prefix with `pong`, and no fixture reads a library folder other than the two.
Critique: the existing `physicallyInside` gets the slash right, and nothing pins that the new test does too. The tempting fix is a single prefix-sibling fixture, which kills Ma but not Mb.
Consequences: none beyond two fixtures. Both route through a chained link, the same route as F1's fixture, so they can share its setup.
Recommendation:
- In the AC5 link case, add a chained link to a sibling folder `pong2` (expect the `makes Rojo read ../pong2/…` line) and one to `arcade/tests` or `arcade/src/client` (expect the outside line).
- Add the Rules rows "Ma: the prefix test without `/`" and "Mb: the library's home in place of its two folders", both `run`.
Lesson: z-design/spec-design-correspondence

### F3 [medium] A non-zero `rojo sourcemap` exit is read as "Rojo refuses the file". In the documented setup the rokit shim exits 1 when it cannot run Rojo, so the net fails open, and the Rules row's reason for leaving that branch untested is wrong.
Where: Design, `rojoReads` ("A non-zero exit gives `nil, nil`: Rojo refuses the file, so its build refuses it too … the existing lines already name the cause"; "a rojo that cannot be run … gives `nil, "<why>"`"). Rules row N11: "none (cannot be provoked without removing rojo) … reasoned".
Evidence:
- Run: `SETUP.md` installs the tools through rokit (`~/.rokit/bin`, `rokit install` for what `rokit.toml` pins). In a folder whose `rokit.toml` pins a Rojo that is not installed (as after a `rokit.toml` bump before `rokit install`), `~/.rokit/bin/rojo sourcemap --include-non-scripts default.project.json` prints `ERROR No such file or directory (os error 2)` and exits 1. `pcall(process.exec, …)` succeeds and `res.ok` is false, so the prototype returns `nil, nil`. Every project file of every home then passes the net silently, and only the old reader lines remain. The Design's own fail-closed branch, "a rojo that cannot be run", is never reached in that setup.
- By reading: an old Rojo without `--include-non-scripts` (a clap usage error, exit 2) and a process killed by a signal take the same silent path.
- "The existing lines already name the cause" is not true for the loop. `src/loop/self -> .` stays inside the home, the old `find -type l` check passes it, and the spec asserts the net prints no line, so a top-level project file Rojo refuses gets no line from the rule at all. That is harmless, because nothing is built, but the Design should not claim otherwise.
- The branch can be tested. A spec can run `home.problems` in a child `lune` whose `PATH` starts with a fixture `bin/` holding a `rojo` stub that exits 1, which is exactly what the shim does.
Critique: zz-arch's guards fail closed. The place builds elsewhere in the gate would probably go red in the same environment, which is why this is medium and not high. But the home rule is the guard this issue builds, and its one fail-open branch is the common failure of the documented toolchain. The tempting fix is to report every non-zero exit, which adds a line to every fixture Rojo refuses (AC3's `weird`, `only` and `num` files and c0185's broken fixtures) and puts Rojo's stderr into line counts such as `has a `.
Consequences: a single `rojo --version` per `home.problems` call (about 10 ms) that must succeed. If it fails, the result is `<home>: rojo cannot be run`, once per home. That separates "cannot run" from "refuses" without changing any existing fixture's lines. A refusal stays silent, as designed, and the Design's sentence about it is reworded. A signal mid-run stays a gap. Record it as accepted, or answer it with a line only when stderr is empty.
Recommendation:
- Add the `rojo --version` probe to the Design, with its line.
- Reword the refusal sentence: a refused file gets no line from the net, and its build fails too.
- Add a `paths.spec` case that runs the rule in a child `lune` with a stub `rojo` that exits 1 and expects the `rojo cannot be run` line.
- Change row N11 to `run` against that case.
Lesson: zz-test/pin-fail-safes-where-they-act

### F4 [low] The AC6 Rules row cites an assertion the spec does not make, and the Test plan omits a case
Where: Rules row "a top-level project file is not a nested project | AC6 :: no "nested project" line | N10 … run (killed by AC7 specs too)". E11 "(N3, N6 and N10 in the AC7 specs as well)". The Test plan list.
Evidence (run):
- The AC6 case asserts no `nested project` count.
- N10 (the `real[i] ~= base/name` guard removed) passes `paths.spec` 13 of 13. Only AC7's c0185 and c0184 specs kill it, so once promoted, `c0246/paths.spec` does not pin its own AC6 text ("a top-level project file is never named a nested project").
- The Test plan lists 12 cases. The spec has 13: "AC1: a node named with a $ that Rojo does not reserve is reported, the six it reserves are not" is missing.
Critique: check.sh still fails on N10 through AC7, so nothing wrong merges. But the row's cited case cannot fail, and the doc says "as well" where the truth is "only".
Consequences: none.
Recommendation:
- Add `t.expect(#lines(found, "nested project")).toBe(0)` to the AC6 case. Its three top-level files would each get a line under N10.
- Make N10's row say which case kills it.
- Add the missing case to the Test plan.
Lesson: z-design/spec-design-correspondence

Lessons pass (item 10):
- F1 repeats zz-arch/guards-decide-from-the-tools-resolution. Its round-8 note, "ask the tool what it reads … and judge that list by real paths", is right, but judging only by real paths is the gap.
- F2 and F4 repeat z-design/spec-design-correspondence. F3 repeats zz-test/pin-fail-safes-where-they-act.
- The author's notes since round 7 (casing by path lookup; stop patching a re-modelled discovery) are general and stand. `sort-cases-defeat-pre-order` is a real, reusable lesson.

Overrides (item 4): `affected` gives `ALL`. The prototype passes check AC7's list, including the real-tree `homes.spec`. `Overrides: none` holds. The F1 sketch also passes that list.
Stale or contradictory after the redesign (asked):
- Nothing outside F3's refusal sentence and F4's row.
- E4 to E9 and M18 to M32 are marked as history.
- Non-goals now claim only the top-level `.jsonc` and the readers' return values.
- The Scope decision lines are dated and ordered.
Bounded commands (item 12): the Design starts no unbounded process. A FIFO named `*.luau` inside a mapped folder would block `rojo sourcemap`, but the spec runner's per-run bound covers that.
Repository safety (item 9): the net reads only (`rojo sourcemap` prints to stdout, and `realpath` is read-only), and the fixtures are under `.cache/c0246-paths`.

Lesson candidate (for the lead, not written here): a note on zz-arch/guards-decide-from-the-tools-resolution. When a guard replaces its model of the tool with the tool's own report, carry over every judgment the old rule made, not only whether an input is allowed. The home rule allowed the library's folders only at their nodes, and the sourcemap-based net allowed them anywhere. Check: for each allowance the old rule granted conditionally (at a node, under a name), does the new check still test the condition, using the tool's own answer (the instance path)?
Lesson candidate: a note on zz-test/pin-fail-safes-where-they-act. A "the tool refused" branch keyed on a non-zero exit also catches "the tool could not run" when the tool is reached through a shim (rokit exits 1 when the pinned version is missing). Check: does a failure branch tell refusal from absence (a `--version` probe), and is it pinned by a stub on `PATH` in a child process?

Verdict: changes
