# Review 001: f0199 (design mode)
Inputs: prep-shared-travel at 9131fae2 plus its uncommitted prep: `arcade/.tracker/issues/f0199/f0199.md`, `check.sh`, `acceptance/{travel,places,place}.spec.luau`, the `arcade/.tracker/architecture.md` diff, and the prototype and mutation runner in `.cache/f0199-mut/` (`proto.luau`, `mut.py`). Capture: d7714681 (`./zn capture f0199`, no marker). Compared with: `pickman/src/shared/Logic/Travel/init.luau`, `pickman/tests/acceptance/f0061/travel.spec.luau`, `pickman/tests/unit/Travel/travel.spec.luau`, arcade-arch, pickman-arch, the shared place harness and placespec, and f0201's in-flight prep (`.worktree/prep-paid-play-and-receipts`, its `architecture.md` diff).

### F1 [high] AC2 passes an implementation that never calls `Travel.destination`
Where: `acceptance/places.spec.luau:60-92`; f0199.md Design part 2 (line 68: "passes each value through `Travel.destination`"), Edge cases (line 96), Rules row R18 (line 147).
Evidence: I ran the places spec from a scratch copy under `arcade/.cache` (since removed) against `.cache/f0199-mut/proto.luau` with line 143 replaced by `local n: any = tonumber(read(attributeOf(name)))` / `local id = if type(n) == "number" and n >= 1 and n == math.floor(n) then n else nil`. Result: **8 passed, 0 failed**. The unmutated prototype also gives 8 passed. That mutant publishes `"0x10"` as 16, `" 7"` as 7 and `"1e3"` as 1000, and also accepts `math.huge`, `2^53` and `"9007199254740993"`. The Edge cases bullet says none of these is an id. The spec's only non-ids are 0, `"0"`, 1.5 and a missing attribute. R18's recorded mutant (bare `tonumber(read(…))`) already dies on 0, so the row doesn't cover its rule: "values go through `destination`".
Critique: AC2 says "anything not a place id meaning not published". The Design's guarantee that `places` and `destination` agree is the only thing that makes a malformed attribute safe. The tempting fix is to add `"0x10"` to the existing case.
Consequences: one more value kills one more mutant but not the whole class. The rule is "a place is published exactly when `destination` accepts its value, for every name". A mutant could send only Portal's value through `destination` and handle the other four its own way.
Recommendation: add a case "every value goes through the place-id check, for every place". For each of the five names, and for each value of travel.spec's `bads` list (0, -1, 1.5, 0/0, math.huge, MAX_PLACE_ID + 2, "0", "", "12a", "-5", " 7", "1.5", "0x10", "1e3", "١٢٣", true, {}) plus `"9007199254740992"`, read a table that holds only that value under that name's attribute, and expect `places[name] == nil` and `count(places) == 0`. For the values that are ids (1, `"987654321"`, MAX_PLACE_ID), expect the number under that name. Write these expectations out; don't use `Travel.destination(v)` as the oracle, or the spec trusts the code it judges. Add a Rules row R18b with the mutant above, run it with mut.py, and record the result in E3.
Lesson: z-design/spec-design-correspondence (also zz-test/seed-every-enumerated-case)

### F2 [medium] Travel names every game, which bends arcade-arch rule 1, and no decision records it
Where: Design part 2 (`PlaceName`, `Places`, `PLACES`, lines 59-75); `arcade/skills/arcade-arch/SKILL.md`, "Changes to pickman's rules" 1 and 2, and its Layout table.
Evidence: Rule 1 says "A library feature is a leaf. It knows no game". Rule 2 says "the destination place ids … are passed in by the game's adapter". Part 2 writes `"Portal" | "Pickman" | "Snake" | "Invaders" | "Asteroids"` into `Logic/Travel`'s types and data. Neither Decisions relied on nor Maintainability mentions rule 1. The sibling prep in flight reads the same rule the other way. f0201's `architecture.md` diff says "PaidPlay … never names a game: a game is a catalog entry passed in", and keeps the per-game list in `src/server/Catalog.luau`. arcade-arch's Layout table puts "types, config tables" in `src/shared/`, outside Logic.
Critique: two library features would answer rule 1 in opposite ways, and the next feature's author would have both as precedent. The tempting fix is one sentence in this issue saying the place list is data, not behaviour.
Consequences: a sentence in the issue doesn't change the skill, so the next reviewer reads rule 1 as written and raises it again. An exception has to be bounded to the place list, or later features will cite it to name games. Moving the list changes interfaces that f0208, f0187 and c0210 quote (all three are still `new` and undesigned), adds one ModuleScript to AC3, and changes the module that Rules rows R14-R19 judge.
Recommendation: move the experience's place list out of Logic into a shared config module, `arcade/src/shared/Places.luau` (ReplicatedStorage.Arcade.Places). It holds `PlaceName`, `Places`, the frozen `NAMES`, `attribute(name)` and `read(read): Places`, and requires `./Logic/Travel` for `destination`. A module outside Logic may require Logic, and `./Logic/Travel` resolves both on disk and in the instance tree. Travel then stays pickman's file unchanged, with no header sentence, so AC1's "copy" is literal and c0200's switch is a change of require path. Follow-on changes:
- places.spec requires `@shared/Places`.
- AC3 adds a case: `ReplicatedStorage.Arcade.Places` is a ModuleScript whose one require resolves to `ReplicatedStorage.Arcade.Logic.Travel`.
- The new `architecture.md` bullet and the Interfaces name `Places.read`, `Places.attribute` and `Places.NAMES` (`@arcade/Places` from portal's home, for c0210).
- The spec tier for a shared module outside Logic follows pickman-test.

If the author keeps the list in Travel instead, record the decision where rule 1 lives. Amend arcade-arch rule 1 to name the one exception (the experience's place list, `Travel.PLACES`, which is data and never branched on), and say so in `architecture.md`, so this reading and f0201's agree.

### F3 [low] Maintainability overstates two things: what a sixth place costs, and that "AC1 keeps the two copies equal"
Where: f0199.md Maintainability (line 89); Interfaces, c0200 (line 80).
Evidence:
- (a) "Adding a sixth place is one data row (a name in `PlaceName` and `PLACES`)". The `Places` record needs a field too, so that is three edits. The promoted `arcade/tests/acceptance/f0199/places.spec.luau` also pins five names (`toEqual(NAMES)`, `asked` equal to five attributes, `count == 5`), so a sixth game turns it red and needs an Overrides line and its chore.
- (b) AC1 runs f0061's cases against arcade's copy only. A fix to pickman's `Logic/Travel` made between f0199 and c0200 turns nothing red, and c0200 would then delete pickman's copy and drop the fix without anything noticing.

Critique: an executor or a later designer trusting these sentences will under-scope the next game, or lose a fix.
Consequences: a spec that compares arcade's copy with pickman's byte for byte would itself go red at c0200, so it would need its own override.
Recommendation: state both facts. A new place is three edits in one module plus an Override of f0199's places spec, made by the issue that adds the game. Between f0199 and c0200, any change to pickman's Travel must also be made to arcade's copy, and c0200's design checks this by diffing pickman's copy against arcade's before deleting it. No new spec.

### F4 [low] The Regression guard names every home's library place spec as at risk, but no step runs them before the final full gate
Where: f0199.md Affected specs (line 109), Regression guard (line 118), Implementation steps 4 (line 169).
Evidence: `lune run z-nile/affected -- arcade/src/shared/Info.luau` and `-- arcade/default.project.json` print only meta specs, and no home's `tests/place/library.spec.luau`. Yet each of those specs builds a place that maps `../arcade/src/shared`. Their watch files (`arcade/tests/place/library.watch.txt`) list only `.luaurc`, `default.project.json` and `tests/lib/place.luau`. So step 4's `arcade/check.sh --affected` never selects them, and E1 ran arcade's alone.
Critique: the guard the document names is first exercised at the merge's full gate, after review.
Consequences: none beyond about six place builds of run time.
Recommendation: step 4 adds `cd <home> && lune run tests/run -- tests/place/library.spec.luau` for arcade, asteroids, invaders, pickman, portal and snake. The Regression guard should say they are run there, not by the selector.

### F5 [low] The prototype record doesn't show a bounded mutation run or an `--affected` gate run
Where: f0199.md Unknowns & experiments, E1 and E3 (lines 112-114); Implementation steps 4.
Evidence: E3 says `.cache/f0199-mut/mut.py` "applied each mutant", but doesn't say it ran under `./zn run --time`. Its `subprocess.run(['lune','run','tests/run',…])` has no timeout. E1 and E2 ran three specs, stylua and `promote-check`, but not `arcade/check.sh --affected` (with selene). Step 4 says that gate passes.
Critique: the bounded-commands rule (item 12) and the prototype lesson both ask for the record. Selene was never run on part 2.
Consequences: none.
Recommendation: record the bounded command that ran mut.py, or re-run it as `./zn run --time 600 -- python3 -I .cache/f0199-mut/mut.py`. Run `arcade/check.sh --affected` once with the prototype in place (it is still in `.cache/f0199-mut/proto.luau`), together with the R18b row from F1, and record the result in E1.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F6 [low] Nobody lists Travel in `architecture.md`, and its `deps` comment goes stale
Where: f0199.md Design (line 73); `arcade/.tracker/architecture.md` line 72; f0201's prep diff to the same file.
Evidence: arcade-arch says the library's "features and their dependencies are listed there too". Once Travel lands, `# no features yet` is false. f0201's prep rewrites that line to `# PaidPlay is a leaf` and adds a `## Features` section, and neither of its edits names Travel. f0199 leaves both alone to avoid a conflict, so whichever of the two lands second leaves Travel unlisted.
Critique: the next reader of `architecture.md` would believe the library has one feature.
Consequences: whichever prep lands second has a one-line conflict to resolve. That conflict is cheap if the design says who resolves it.
Recommendation: the Design and step 3 say that the `deps` comment names Travel as a leaf. Whichever of f0199 and f0201 lands second resolves the conflict to name both (`# PaidPlay and Travel are leaves`), and, if f0201's Features section is already there, adds a Travel entry to it (or a `Places` entry, under F2's fix).
Lesson: z-design/design-the-execution-window

## Checked without a finding
- Scope (item 11): the capture is confirmed (d7714681) and both of its outcomes have a Design and a Checked criterion (AC1 and AC3 for the move, AC2 for the attributes). The added Non-goal (a shared teleport adapter) is not a captured outcome: `architecture.md` item 2 names only "Travel", while items 1 and 3 name their adapters.
- Overrides (item 4): `z-nile/affected` prints nothing for every Touched path. `grep -rlF` finds `z-nile/tests/acceptance/c0183/designs.spec.luau` pinning `arcade/.tracker/architecture.md` by digest, but that spec passes on any historical version of the file, so the edit cannot turn it red. c0185's specs write their own fixtures. "Overrides: none" holds.
- AC1 is f0061's `travel.spec.luau` case for case, plus pickman's two unit cases (diffed). The AC3 helpers exist (`place.load`, `resolveRequire`, `requireSpecs`), and `ServerStorage.Arcade` is a Folder (`src/server/.gitkeep`), so the leaf case's `server ~= nil` holds. The `@logic` and `@arcade` aliases are as the Design says. `ServerScriptService` is where `Beta.project` writes attributes today.
- Repository safety: the three specs only read. `check.sh` runs only `tests/run`.

## Lesson candidates (for the prep's lead)
- arcade-arch: a library feature that needs the experience's place or game list takes it from a `src/shared` config module (or as a parameter), never from data in Logic, because f0199 and f0201 read rule 1 in opposite ways. Check: does any file under `arcade/src/shared/Logic` spell a game's name?
- zz-test / z-nile (a capture, not a lesson): `z-nile/affected` selects no home's `tests/place/library.spec.luau` for a change under `arcade/src/shared` or to `arcade/default.project.json`, although `architecture.md` says (c0185) that a home's place specs re-run when anything under its `$path`s changes. Check: does `lune run z-nile/affected -- arcade/src/shared/Info.luau` list `arcade/tests/place/library.spec.luau`?

Verdict: changes
