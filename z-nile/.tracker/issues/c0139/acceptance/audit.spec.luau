--!strict
-- c0139 AC4: `./zn audit` (which the gate runs) reports a file under a root or a skills folder holding a whole merge
-- conflict as an error naming the path and line and the recovery, so a pull request that adds one is red before it
-- lands; a clean tree has no such problem. Fixture under .cache/c0139-audit (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0139 audit reports a committed merge conflict", function(it)
	it("reports it as an error, with path, line and recovery; a clean tree has none", function()
		local f = trackerfix.new("c0139-audit", {
			["z-nile/projects.toml"] = REGISTRY,
			["pickman/.tracker/issues/.gitkeep"] = "",
			["z-nile/.tracker/issues/.gitkeep"] = "",
		})
		local clean = trackerfix.tr(f, f.main, { "audit" })
		t.expect(has(clean.stdout, "conflict-markers")).toBe(false)
		local rel = "pickman/.tracker/issues/f0002/f0002.md"
		fs.writeDir(`{f.main}/pickman/.tracker/issues/f0002`)
		fs.writeFile(`{f.main}/{rel}`, "---\nid: f0002\n---\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> side\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "a conflict committed by mistake" })
		local r = trackerfix.tr(f, f.main, { "audit" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "conflict-markers")).toBe(true)
		t.expect(has(r.stdout, `{rel}:4`)).toBe(true)
		t.expect(has(r.stdout, "resolve with plain git")).toBe(true)
		fs.removeDir(f.base)
	end)
end)
