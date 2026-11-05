--!strict
-- c0170 AC2: R0059's plain.spec (a spec of tests/lib/plain) moves from tests/unit/plain/ to the helper tier,
-- tests/helper/plain/, and still passes; architecture.spec's tier case hands tests/meta/tiers the whole require
-- graph of src and tests, as graph.build reads it, and every tests/lib helper, and fails when tiers reports a
-- violation; pickman-test names the tier and its rule. (The skills' exact tier and helper lists, which later work
-- extends, and the selector's answers are check.sh's AC4 and AC5, design review 005 F3;
-- a promoted pickman spec pins neither z-nile's files nor z-nile's tools, design reviews 001 F4 and 002 F3.) Casts
-- keep the spec type-legal before the files exist; a missing module fails at require.
local arch: any = require("@tests/meta/architecture.spec")
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local plainSpec: any = require("@tests/helper/plain/plain.spec")
local t = require("@tests/lib/t")
local tiers: any = require("@tests/meta/tiers")

local TIER_CASE =
	"helper specs sit in tests/helper/<helper>/ and load only their helper, t and their fixtures; unit specs load no other helper"

type Case = { name: string, fn: () -> () }

local function caseOf(spec: any, name: string): Case
	local found: Case? = nil
	local count = 0
	for _, c in spec.cases do
		if c.name == name then
			found = c
			count += 1
		end
	end
	t.expect(count).toBe(1)
	assert(found, "no case named " .. name)
	return found
end

-- whether fn raised one of t's assertions ("<file>:<line>: expected …"); any other error is raised here
local function fails(fn: () -> ()): boolean
	local ok, err = pcall(fn :: () -> any)
	if ok then
		return false
	end
	if not string.find(tostring(err), "^[^\n]-:%d+: expected ") then
		error("not an assertion failure: " .. tostring(err), 2)
	end
	return true
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0170 the helper spec tier", function(it)
	it(
		"plain.spec sits in tests/helper/plain/, tests/unit has no plain folder, and its cases pass",
		function()
			t.expect(fs.isFile("tests/helper/plain/plain.spec.luau")).toBe(true)
			t.expect(fs.isDir("tests/unit/plain")).toBe(false)
			t.expect(#plainSpec.cases >= 1).toBe(true)
			for _, c in plainSpec.cases do
				t.expect(fails(c.fn)).toBe(false)
			end
		end
	)

	it("the tier case hands tiers the whole require graph and every tests/lib helper", function()
		local real = tiers.violations
		local seenGraph: any, seenHelpers: any = nil, nil
		tiers.violations = function(g: any, helpers: any): { string }
			seenGraph, seenHelpers = g, helpers
			return {}
		end
		local ok, err = pcall(caseOf(arch, TIER_CASE).fn :: () -> any)
		tiers.violations = real
		assert(ok, tostring(err))
		assert(seenGraph and seenHelpers, "the tier case never called tiers.violations")
		-- every file and every file's deps, exactly as graph.build reads them from src and tests (design review 002
		-- F2: the rule picks the specs itself, so only a filtered graph could hide one)
		local g = graph.build({ "src", "tests" })
		local files = table.clone(seenGraph.files)
		local want = table.clone(g.files)
		table.sort(files)
		table.sort(want)
		t.expect(files).toEqual(want)
		t.expect(seenGraph.deps).toEqual(g.deps)
		t.expect(table.find(want, "tests/helper/plain/plain.spec.luau") ~= nil).toBe(true)
		local helpers: { string } = {}
		for name in seenHelpers do
			table.insert(helpers, name)
		end
		table.sort(helpers)
		local libs: { string } = {}
		for _, name in fs.readDir("tests/lib") do
			local base = string.match(name, "^(.+)%.luau$")
			if base then
				table.insert(libs, base)
			elseif fs.isFile(`tests/lib/{name}/init.luau`) then
				table.insert(libs, name)
			end
		end
		table.sort(libs)
		t.expect(helpers).toEqual(libs)
	end)

	it("the tier case fails when tiers reports a violation, and passes on today's tree", function()
		local real = tiers.violations
		tiers.violations = function(): { string }
			return { "tests/unit/X/x.spec.luau: loads tests/lib/sim.luau" }
		end
		local failed = fails(caseOf(arch, TIER_CASE).fn)
		tiers.violations = real
		t.expect(failed).toBe(true)
		t.expect(fails(caseOf(arch, TIER_CASE).fn)).toBe(false)
	end)

	it(
		"pickman-test names the helper tier, its rule and where sim's own spec stays (its exact lists are AC4's)",
		function()
			local skill = fs.readFile("skills/pickman-test/SKILL.md")
			t.expect(
				has(
					skill,
					"| `tests/helper/<helper>/` | one `tests/lib` helper's behavior (`tests/helper/plain/` for `tests/lib/plain.luau`) | only that helper (`@tests/lib/<helper>`), `@tests/lib/t`, its own fixtures under `@tests/fixtures/<helper>/` and `@lune/` builtins |"
				)
			).toBe(true)
			t.expect(
				has(
					skill,
					"A spec of a `tests/lib` helper itself goes in `tests/helper/<helper>/`, never in `tests/unit/`"
				)
			).toBe(true)
			t.expect(has(skill, "a spec driven through `@tests/lib/sim` stays in `tests/scenario/`"))
				.toBe(true)
			t.expect(has(skill, "a unit spec loads no `tests/lib` helper but `@tests/lib/t`")).toBe(true)
		end
	)
end)
