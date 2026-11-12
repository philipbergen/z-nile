# Review 001: c0246 (design mode)
Inputs: prep worktree at b403cd39 plus its uncommitted draft: `c0246.md`, `check.sh`, `acceptance/paths.spec.luau`; `z-nile/lib/graph.luau`, `z-nile/tests/lib/home.luau`, `z-nile/README.md`, `pickman/scripts/lib/beta.luau`; `./zn capture c0246` (capture 65cfc7b2, no marker) and the scope commit 289a38ab (#249); `./zn check c0246` (1/5 pass: AC1-AC4 fail on `graph.unreadable` being nil, the missing report lines and the missing README sentence, which are the right reasons; AC5 passes); a rerun of E1 with Rojo 7.7.1 (`["src"]`, `["../out"]`, `{"optional":"src","x":1}` and `{"optional":"../out"}` build and map the folder; `5`, `[]`, `{}`, `{"optional":5}` and `["src","src"]` fail to parse: the record holds); `lune run z-nile/affected -- snake/default.project.json` prints `ALL` (so an edit to a project file runs every home rule, as Non-goals says).

Scope (item 11): the capture asks for (a) the `optional` form read through the same checks and (b) every other non-string `$path` reported. The user's `Scope decision (user, 2026-11-06)` records (a) as delivered by c0185, and `tests/acceptance/c0185/library.spec.luau:265-271` does pin it (`{"optional": "../pong/src"}` is reported as outside the home). (b) has a Design and AC1/AC3/AC4. The array form, which the scope line doesn't list, is reported too, which is wider, not narrower. No scope finding.

### F1 [high] AC1's sort case passes an implementation that never sorts
Where: `acceptance/paths.spec.luau` case "AC1: the tree node (instance "") and nested nodes are read, sorted by instance"; Design, `graph.unreadable` ("sorted by `instance`"); Rules and mutants row "result is sorted by instance" (M4).
Evidence: the walker appends a node's own `$path` before it recurses, so the tree node `""` always comes first, and Lune iterates that fixture's decoded tree as `A,Z,$path` (probe, three runs). So a pre-order walk with no `table.sort` yields `"", "A/B", "Z"`, which is exactly the expected list. I ran the design's walker without the sort on the spec's own JSON (scratch probe, through `./zn run`): output ` | A/B | Z`, sorted ` | A/B | Z`, `same: true`. The recorded mutant M4 ("reverse order") is not the plausible one; "forgot to sort" is, and it passes AC1's check.
Critique: AC1 says "sorted by instance" and the check can be passed by an implementation that doesn't sort. The author's likely fix, reordering the keys of the fixture's JSON, still depends on the hash order Lune happens to use, so it can go green for a non-sorting walker on another build.
Consequences: a fixture whose sorted order no pre-order walk can produce, whatever the hash order, relies on Luau's `<` comparing bytes (`'-'` 0x2D before `'/'` 0x2F). I probed it: `"A-" < "A/Z"` is `true`.
Recommendation: in the same sequestered case, add `decode('{ "tree": { "A": { "$path": 5, "Z": { "$path": 5 } }, "A-": { "$path": 5 } } }')` expecting `{ A, A-, A/Z }` (all `"a number"`). A pre-order walk keeps `A` and `A/Z` adjacent, so it gives `A, A/Z, A-` or `A-, A, A/Z`, never the sorted order (probe: walk `A | A/Z | A-`, sorted `A | A- | A/Z`). Add a mutant row "M11: no sort", run it on the prototype, and record that this assertion kills it. Keep the existing assertions.

### F2 [low] The Rules row for nested nodes names a case that has no nested node
Where: Rules and mutants, row "nested nodes are walked | AC1 :: names every $path | M3".
Evidence: `withPath` builds a single top-level node `A`, so "names every $path" never reaches a child. M3 ("the recursion drops the list") is killed only by the sorted case's `A/B`.
Critique: this is the lesson z-design/spec-design-correspondence ("is each new case's recorded mutant killed by that case itself?"). As written, the table claims coverage the case doesn't give.
Consequences: none.
Recommendation: point the row at "AC1 :: tree node and nested nodes", where `A/B` is the only nested node, so deleting that case would let M3 live. With F1's fixture, `A/Z` also covers it.
Lesson: z-design/spec-design-correspondence

### F3 [low] The design says one reader reads `$path`, but `beta.luau` reads it too
Where: Problem's scope line ("c0185 … moved every `$path` read into `graph.mappings`"), Solution ("what is read and what is reported cannot drift apart"), Design "Existing work" and "Restated rules".
Evidence: `git grep -nF '"$path"' -- '*.luau' '*.sh' zn` (excluding tests and c0246) hits `z-nile/lib/graph.luau` (the walker) and `pickman/scripts/lib/beta.luau:112-114`. That second reader is `rewrite`, which turns a string `$path` and an `optional` string into absolute paths and leaves any other value as written. So a `["../x"]` would stay relative in deploy-beta's copy, which is built from another folder.
Critique: this isn't a defect today, because the new rule refuses such a value in every registered home's project files before deploy-beta could read one. But a later change that teaches `walkMappings` the array form (Non-goals rules it out now) would leave `beta.luau` behind unseen (zz-arch/one-reader-per-format).
Consequences: none for this issue's behaviour.
Recommendation: add one sentence under Existing work: `pickman/scripts/lib/beta.luau` `rewrite` is the other reader of `$path` (strings and `optional` strings only), it relies on this rule to never see another value, and any change to the spellings `walkMappings` reads changes it too. No spec needed.
Lesson: zz-arch/one-reader-per-format

### F4 [low] The walker's comment and the `bad` parameter's type are stated wrong for the executor
Where: Design, `z-nile/lib/graph.luau` bullets; `graph.luau:166-168` comment.
Evidence: the Design gives `walkMappings(node, prefix, out, bad: Unreadable?)`, but it appends to `bad`, so the type is `{ Unreadable }?`. The existing comment says the walker reads "both of Rojo's forms (a string, or the `optional` string of a table)", but E1 shows a third that Rojo builds (a one-element array).
Critique: in strict mode the type is a compile error the executor has to fix by guessing, and the stale comment restates a rule this issue changes (z-design/restated-rules-move-together).
Consequences: none.
Recommendation: write the parameter as `bad: { Unreadable }?`, and add an implementation step 1 sub-item that rewords the comment: it reads two of Rojo's three spellings (a string, an `optional` string), and the third (a one-element array) and every other value go to `bad`, which `graph.unreadable` reports.

### F5 [low] AC3's ownership loop can't fail, and no nested node's line is pinned
Where: `paths.spec.luau` AC3 first case, `for _, l in lines(found, "pong: ")`; Rules row "the line names the node" (M6).
Evidence: `lines(found, "pong: ")` keeps only lines that contain `pong: `, and then asserts that each starts with it. That fails only if `pong: ` appears in the middle of a line, which no implementation does. Also, every unreadable node in `weird.project.json` is at the top level, so a mutant that words `<where>` from the leaf key (`node B` for `A/B`) passes AC3. Only the tree root and depth-1 nodes are pinned.
Critique: one loop asserts nothing, and the `<where>` wording of `instance` is pinned only where the leaf and the instance path are the same.
Consequences: none.
Recommendation: replace the loop with one over all of `weird` asserting `string.sub(l, 1, 6) == "pong: "`, or delete it. Add a nested node to `weird.project.json` (`"R": { "S": { "$path": 5 } }`) and assert `hasLine(weird, "node R/S", "a number")`, then record in M6's row (or a new row) the leaf-name mutant that it kills.

### F6 [low] AC4's real-tree half reruns homes.spec's real-tree run in every full gate
Where: `paths.spec.luau` AC4, `home.problems(top, projects.load(top))`; check AC5, which runs `c0184/homes.spec.luau`.
Evidence: `c0184/homes.spec.luau:48-54` already runs `problems(TOP, projects.load(TOP))` and expects no problems at all (`table.concat(found, "\n") == ""`), which is strictly stronger than AC4's "no line has `has a $path`". The rule shells out to `realpath` per mapped path and `find` per mapped folder, so the promoted c0246 spec repeats that walk over every home in every full gate.
Critique: this is the user's fast-tests rule. The assertion adds no catch: it passes before the change and after.
Consequences: AC4's label still says "the real tree holds none", so the label has to name where that is checked.
Recommendation: keep the README half in `paths.spec` AC4, and let AC4's `check` line also run `tests/acceptance/c0184/homes.spec.luau` for the real-tree half (it is already in AC5). Or keep the duplicate and say in the design why. This is the author's call: it changes speed, not scope.

Lesson candidates (for the lead, not written here):
- zz-test/sort-cases-defeat-pre-order: a case that pins "sorted by key" over a tree walk must use keys whose sorted order no pre-order walk can produce (siblings `A`, `A-` with a child `A/Z`), because the walk emits parents first and a decoded table's hash order can match sorted order by chance. Check: would this case pass if the sort were deleted, under every hash order?

Verdict: changes
