--!strict
-- c0180: once engine Luau files stop forcing z-nile's run, every spec that reads engine files as text or copies them
-- declares them in z-nile/tests/inputs.tsv (c0165's format), so a change to them still selects it. Runs from z-nile's
-- home; the lines are the Design's Declarations, found by prep's audit (E8).
local fs = require("@lune/fs")
local select = require("@znile/lib/select")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local A = "tests/" .. "acceptance/"
local DECLARED = {
	{ "tests/tooling/tracker-guarded.spec.luau", "z-nile/engine/main.luau" },
	{ A .. renamed.id("c0081") .. "/publish-guard.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0120") .. "/docs.spec.luau", "z-nile/engine/main.luau" },
	{ A .. renamed.id("c0116") .. "/docs.spec.luau", "z-nile/engine/main.luau" },
	{ A .. renamed.id("c0077") .. "/cache-paths.spec.luau", "z-nile/engine/" },
	{ "tests/tooling/repo-fence.spec.luau", "z-nile/engine/" },
	{ "tests/meta/architecture.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0115") .. "/absence.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0120") .. "/ci.spec.luau", "z-nile/engine/projects.luau" },
	{ A .. renamed.id("c0114") .. "/gate-cover.spec.luau", "z-nile/engine/projects.luau" },
	{ A .. renamed.id("c0059") .. "/adapt.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0114") .. "/classified.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0114") .. "/layout.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0114") .. "/registry.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0180") .. "/split.spec.luau", "z-nile/engine/" },
	{ A .. renamed.id("c0180") .. "/docs.spec.luau", "z-nile/engine/main.luau" },
}

return t.spec("c0180 engine-text readers declare their engine inputs", function(it)
	it("z-nile/tests/inputs.tsv parses and holds every declaration", function()
		local text = fs.readFile("tests/inputs.tsv")
		local inputs, problem = select.parseInputs(text, "z-nile/", { "pickman/.tracker", "z-nile/.tracker" })
		t.expect(problem).toBe(nil)
		local lines: { [string]: boolean } = {}
		for line in string.gmatch(text, "[^\n]+") do
			lines[line] = true
		end
		for _, d in DECLARED do
			t.expect(lines[`{d[1]}\t{d[2]}`] == true).toBe(true)
			local entries = (inputs :: select.Inputs)[`z-nile/{d[1]}`]
			t.expect(entries ~= nil and table.find(entries, d[2]) ~= nil).toBe(true)
		end
	end)
end)
