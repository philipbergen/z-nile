--!strict
-- c0170 AC1: the helper tier's rule and the unit tier's helper rule, as tests/meta/tiers.luau decides them over a
-- require graph shaped as graph.build gives it ({ files, deps }, paths relative to pickman/): it judges every
-- *.spec.luau under tests/helper/ and tests/unit/ (at any depth) and nothing else. A helper spec lives in
-- tests/helper/<helper>/ (one folder down, tests/lib/<helper>.luau a real module) and loads tests/lib/<helper>.luau
-- at least once, tests/lib/t.luau and its own fixtures under tests/fixtures/<helper>/, nothing else; a unit spec
-- loads no tests/lib helper but tests/lib/t.luau. Judging resolved files means a relative or differently spelled
-- require of the same helper is judged the same (design review 001 F2).
-- Casts keep the spec type-legal before tests/meta/tiers exists; a missing module fails at require.
local t = require("@tests/lib/t")
local tiers: any = require("@tests/meta/tiers")

local HELPERS = {
	plain = true,
	plainx = true,
	sim = true,
	place = true,
	fakeengine = true,
	renamed = true,
	t = true,
	fold = true,
}
local T = "tests/lib/t.luau"
local PLAIN = "tests/lib/plain.luau"
local MAZE = "src/shared/Logic/Maze/init.luau"

type Entry = { file: string, deps: { string } }

-- a graph of the given files, in order
-- a graph of the given files, in order, with every file they load listed after them (as graph.build lists every
-- file of the tree), so only a case that leaves a file out on purpose meets the fail-closed rule
local function graphOf(list: { Entry }): any
	local g = { files = {}, deps = {} }
	local listed: { [string]: boolean } = {}
	for _, f in list do
		table.insert(g.files, f.file)
		listed[f.file] = true
		g.deps[f.file] = f.deps
	end
	for _, f in list do
		for _, d in f.deps do
			if not listed[d] then
				listed[d] = true
				table.insert(g.files, d)
			end
		end
	end
	return g
end

local function check(file: string, deps: { string }): { string }
	return tiers.violations(graphOf({ { file = file, deps = deps } }), HELPERS)
end

local function says(got: { string }, needle: string): boolean
	return #got == 1 and string.find(got[1], needle, 1, true) ~= nil
end

return t.spec("c0170 the helper tier's rule", function(it)
	it("a helper spec that loads its helper, t and its own fixtures passes", function()
		t.expect(check("tests/helper/plain/plain.spec.luau", { PLAIN, T })).toEqual({})
		t.expect(check("tests/helper/plain/more.spec.luau", { "tests/fixtures/plain/frames.luau", PLAIN, T }))
			.toEqual({})
		t.expect(
			check(
				"tests/helper/sim/sim.spec.luau",
				{ "tests/fixtures/sim/walker.luau", "tests/lib/sim.luau", T }
			)
		).toEqual({})
		-- t's own specs may live in its folder: the helper is t
		t.expect(check("tests/helper/t/smoke.spec.luau", { T })).toEqual({})
	end)

	it(
		"a helper spec that loads another helper, a feature or another helper's fixture breaks the rule, once each",
		function()
			for _, other in
				{ "tests/lib/sim.luau", MAZE, "tests/fixtures/sim/walker.luau", "tests/lib/plainx.luau" }
			do
				local got = check("tests/helper/plain/plain.spec.luau", { PLAIN, other, T })
				t.expect(says(got, "tests/helper/plain/plain.spec.luau: loads " .. other)).toBe(true)
			end
			t.expect(
				#check(
					"tests/helper/plain/plain.spec.luau",
					{ MAZE, PLAIN, "src/shared/Logic/View/init.luau" }
				)
			)
				.toBe(2)
		end
	)

	it(
		"a helper spec whose only own files are its fixtures, or a look-alike fixtures folder, breaks the rule",
		function()
			-- its fixtures are not the helper (design review 002 F1, R1)
			t.expect(
				says(
					check("tests/helper/plain/plain.spec.luau", { "tests/fixtures/plain/frames.luau", T }),
					"does not load its helper tests/lib/plain"
				)
			).toBe(true)
			-- tests/fixtures/plainx/ is another helper's folder (R2)
			t.expect(
				says(
					check(
						"tests/helper/plain/plain.spec.luau",
						{ "tests/fixtures/plainx/frames.luau", PLAIN, T }
					),
					"loads tests/fixtures/plainx/frames.luau"
				)
			).toBe(true)
		end
	)

	it(
		"a helper spec that never loads its own helper breaks the rule, a look-alike name not counting",
		function()
			t.expect(
				says(
					check("tests/helper/plain/plain.spec.luau", { T }),
					"does not load its helper tests/lib/plain"
				)
			).toBe(true)
			-- plainx is another helper, and plain's own is missing: two violations
			t.expect(#check("tests/helper/plain/plain.spec.luau", { "tests/lib/plainx.luau", T })).toBe(2)
		end
	)

	it(
		"a helper spec outside tests/helper/<helper>/, or named for no tests/lib module, breaks the rule",
		function()
			for _, file in { "tests/helper/plain.spec.luau", "tests/helper/plain/deep/plain.spec.luau" } do
				t.expect(says(check(file, { PLAIN, T }), "lives in tests/helper/<helper>/")).toBe(true)
			end
			t.expect(says(check("tests/helper/plan/plain.spec.luau", { PLAIN, T }), "no helper named plan"))
				.toBe(true)
		end
	)

	it(
		"a unit spec that loads a tests/lib helper other than t breaks the rule and names the helper's folder",
		function()
			t.expect(check("tests/unit/plain/plain.spec.luau", { PLAIN, T })).toEqual({
				"tests/unit/plain/plain.spec.luau: loads tests/lib/plain.luau; a helper's specs go in tests/helper/plain/",
			})
			t.expect(#check("tests/unit/Maze/maze.spec.luau", { MAZE, "tests/lib/sim.luau" })).toBe(1)
		end
	)

	it("every unit spec is judged, at any depth, and no helper but t is exempt", function()
		-- a top-level unit spec (smoke.spec is one) is judged too (design review 002 F1, R3)
		t.expect(
			says(check("tests/unit/smoke.spec.luau", { "tests/lib/sim.luau", T }), "loads tests/lib/sim.luau")
		)
			.toBe(true)
		t.expect(#check("tests/unit/Maze/deep/maze.spec.luau", { "tests/lib/place.luau" })).toBe(1)
		-- each helper breaks it (R4)
		for name in HELPERS do
			local want = if name == "t" then 0 else 1
			t.expect(#check("tests/unit/Maze/maze.spec.luau", { `tests/lib/{name}.luau`, MAZE })).toBe(want)
		end
	end)

	it("only *.spec.luau files under tests/helper/ and tests/unit/ are judged", function()
		local g = graphOf({
			{ file = "tests/unit/Maze/helpers.luau", deps = { "tests/lib/sim.luau" } }, -- a module, not a spec
			{ file = "tests/helper/plain/frames.luau", deps = { MAZE } },
			{
				file = "tests/scenario/harness.spec.luau",
				deps = { "tests/fixtures/sim/walker.luau", "tests/lib/sim.luau", T },
			},
			{ file = "tests/place/structure.spec.luau", deps = { "tests/lib/place.luau", T } },
			{ file = MAZE, deps = {} },
			{ file = "tests/unit/Pad/pad.spec.luau", deps = { "tests/lib/sim.luau" } },
		})
		local got = tiers.violations(g, HELPERS)
		t.expect(#got).toBe(1)
		t.expect((string.find(got[1], "tests/unit/Pad/pad.spec.luau", 1, true))).toBe(1)
	end)

	it("a unit spec that loads its feature and t passes", function()
		t.expect(check("tests/unit/Maze/maze.spec.luau", { MAZE, T })).toEqual({})
		t.expect(check("tests/unit/smoke.spec.luau", { T })).toEqual({})
	end)

	it("every breaking spec is reported, in order, whatever comes before or after it", function()
		local ok = { file = "tests/unit/Maze/maze.spec.luau", deps = { MAZE, T } }
		local bad = {
			file = "tests/unit/Pad/pad.spec.luau",
			deps = { "src/shared/Logic/Pad/init.luau", "tests/lib/sim.luau" },
		}
		local worse = { file = "tests/helper/sim/sim.spec.luau", deps = { T } }
		local got = tiers.violations(graphOf({ bad, ok, worse }), HELPERS)
		t.expect(#got).toBe(2)
		t.expect((string.find(got[1], "tests/unit/Pad/pad.spec.luau", 1, true))).toBe(1)
		t.expect((string.find(got[2], "tests/helper/sim/sim.spec.luau", 1, true))).toBe(1)
		t.expect(#tiers.violations(graphOf({ ok, bad }), HELPERS)).toBe(1)
		t.expect(#tiers.violations(graphOf({ worse, ok }), HELPERS)).toBe(1)
		-- a spec with no deps entry is judged with none: a helper spec then lacks its helper
		t.expect(#tiers.violations({ files = { "tests/helper/plain/plain.spec.luau" }, deps = {} }, HELPERS))
			.toBe(1)
	end)

	it(
		"a spec that reaches a helper through another test file is judged as if it loaded it (design review 003 F3)",
		function()
			-- a unit spec through a fixture, and through a sibling module
			local g = graphOf({
				{
					file = "tests/unit/Maze/maze.spec.luau",
					deps = { MAZE, "tests/fixtures/sim/walker.luau", T },
				},
				{ file = "tests/fixtures/sim/walker.luau", deps = { "tests/lib/sim.luau" } },
				{ file = "tests/unit/Pad/pad.spec.luau", deps = { "tests/unit/Pad/helpers.luau", T } },
				{ file = "tests/unit/Pad/helpers.luau", deps = { "tests/unit/Pad/more.luau" } },
				{ file = "tests/unit/Pad/more.luau", deps = { "tests/unit/Pad/helpers.luau", PLAIN } }, -- a cycle, too
			})
			local got = tiers.violations(g, HELPERS)
			t.expect(#got).toBe(2)
			t.expect(
				string.find(got[1], "tests/unit/Maze/maze.spec.luau: loads tests/lib/sim.luau", 1, true)
					~= nil
			)
				.toBe(true)
			t.expect(
				string.find(got[2], "tests/unit/Pad/pad.spec.luau: loads tests/lib/plain.luau", 1, true)
					~= nil
			)
				.toBe(true)
			-- a helper spec's own fixture may load its helper, not another one
			local h = graphOf({
				{
					file = "tests/helper/plain/plain.spec.luau",
					deps = { PLAIN, "tests/fixtures/plain/frames.luau", T },
				},
				{ file = "tests/fixtures/plain/frames.luau", deps = { PLAIN, "tests/lib/sim.luau" } },
			})
			local hv = tiers.violations(h, HELPERS)
			t.expect(says(hv, "reaches, through another test file, tests/lib/sim.luau")).toBe(true)
			-- src ends a path: a feature's own requires are not the spec's
			local s = graphOf({
				{ file = "tests/unit/Maze/maze.spec.luau", deps = { MAZE, T } },
				{ file = MAZE, deps = { "tests/lib/sim.luau" } }, -- if src were followed, this would count (review 005 F4),
			})
			t.expect(tiers.violations(s, HELPERS)).toEqual({})
		end
	)

	it(
		"a spec's loads through other test files of any kind are judged, and outside files too (design review 004)",
		function()
			-- a helper spec's fixture may not load a feature or another tier's module (F2)
			local h = graphOf({
				{
					file = "tests/helper/plain/plain.spec.luau",
					deps = { PLAIN, "tests/fixtures/plain/frames.luau", T },
				},
				{
					file = "tests/fixtures/plain/frames.luau",
					deps = { PLAIN, MAZE, "tests/unit/Maze/helpers.luau" },
				},
				{ file = "tests/unit/Maze/helpers.luau", deps = {} },
			})
			local hv = tiers.violations(h, HELPERS)
			t.expect(#hv).toBe(2)
			t.expect(string.find(hv[1], "reaches, through another test file, " .. MAZE, 1, true) ~= nil)
				.toBe(true)
			t.expect(
				string.find(
					hv[2],
					"reaches, through another test file, tests/unit/Maze/helpers.luau",
					1,
					true
				) ~= nil
			).toBe(true)
			-- a unit spec may load nothing outside pickman/, directly or through a sibling module (F1)
			local u = graphOf({
				{
					file = "tests/unit/Maze/maze.spec.luau",
					deps = { MAZE, "../z-nile/tests/lib/renamed.luau", T },
				},
				{ file = "tests/unit/Pad/pad.spec.luau", deps = { "tests/unit/Pad/helpers.luau", T } },
				{ file = "tests/unit/Pad/helpers.luau", deps = { "../pickman/tests/lib/plain.luau" } },
			})
			local uv = tiers.violations(u, HELPERS)
			t.expect(#uv).toBe(2)
			t.expect(
				string.find(uv[1], "loads ../z-nile/tests/lib/renamed.luau, outside pickman/", 1, true) ~= nil
			)
				.toBe(true)
			t.expect(
				string.find(uv[2], "loads ../pickman/tests/lib/plain.luau, outside pickman/", 1, true) ~= nil
			)
				.toBe(true)
			-- t's own outside requires are not the spec's: tests/lib/ ends a path
			local tg = graphOf({
				{ file = "tests/unit/smoke.spec.luau", deps = { T } },
				{ file = T, deps = { "../z-nile/tests/lib/t.luau" } },
			})
			t.expect(tiers.violations(tg, HELPERS)).toEqual({})
		end
	)

	it(
		"a helper kept as a folder (tests/lib/<helper>/init.luau or any file in it) is a helper too (design review 004 F3)",
		function()
			t.expect(check("tests/helper/fold/fold.spec.luau", { "tests/lib/fold/init.luau", T })).toEqual({})
			t.expect(#check("tests/unit/Maze/maze.spec.luau", { MAZE, "tests/lib/fold/init.luau" })).toBe(1)
			t.expect(#check("tests/unit/Maze/maze.spec.luau", { MAZE, "tests/lib/fold/part.luau" })).toBe(1)
			-- loading another helper instead: that file is not its own, and its own helper is missing
			local got = check("tests/helper/fold/fold.spec.luau", { "tests/lib/plain.luau", T })
			t.expect(#got).toBe(2)
			t.expect(string.find(got[2], "does not load its helper tests/lib/fold", 1, true) ~= nil)
				.toBe(true)
		end
	)

	it(
		"a spec that reaches an unlisted tests/ file, or has a dynamic require, breaks the rule (design review 005 F1)",
		function()
			-- a miscased folder: graph.build keeps the spelling, and a case-insensitive disk opens the file anyway
			local g = {
				files = { "tests/unit/Maze/maze.spec.luau", "tests/lib/plain.luau", MAZE, T },
				deps = { ["tests/unit/Maze/maze.spec.luau"] = { MAZE, "tests/Lib/plain.luau", T } },
			}
			t.expect(
				says(
					tiers.violations(g, HELPERS),
					"loads tests/Lib/plain.luau, which is not a file of the tree as listed"
				)
			).toBe(true)
			-- listed files pass, and a missing src or scripts dep is not this rule's
			local ok = {
				files = { "tests/unit/Maze/maze.spec.luau", MAZE, T },
				deps = { ["tests/unit/Maze/maze.spec.luau"] = { MAZE, T, "scripts/lib/x.luau" } },
			}
			t.expect(tiers.violations(ok, HELPERS)).toEqual({})
			-- a dynamic require in a judged spec; one elsewhere is not this rule's
			local d = {
				files = { "tests/helper/plain/plain.spec.luau", "tests/scenario/x.spec.luau", PLAIN, T },
				deps = { ["tests/helper/plain/plain.spec.luau"] = { PLAIN, T } },
				dynamic = { "tests/helper/plain/plain.spec.luau", "tests/scenario/x.spec.luau" },
			}
			t.expect(
				says(
					tiers.violations(d, HELPERS),
					"tests/helper/plain/plain.spec.luau: has a dynamic require"
				)
			)
				.toBe(true)
		end
	)
end)
