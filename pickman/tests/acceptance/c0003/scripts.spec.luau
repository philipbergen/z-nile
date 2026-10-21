--!strict
-- c0030 AC4: what a runtime script is. Each tests/runtime/*.luau runs inside a real server of the
-- published place, so it can't require anything, must say it passed by returning "PASS", and is strict
-- Luau like every other file (the gate checks it).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function scripts(): { string }
	local out = {}
	for _, name in fs.readDir("tests/runtime") do
		if string.match(name, "%.luau$") then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

return t.spec("c0030 tests/runtime scripts", function(it)
	it("there is at least the structure check", function()
		local names = scripts()
		t.expect(#names >= 1).toBe(true)
		t.expect(table.find(names, "structure.luau") ~= nil).toBe(true)
	end)

	it("every script is strict, requires nothing, and ends by returning PASS", function()
		for _, name in scripts() do
			local text = fs.readFile(`tests/runtime/{name}`)
			t.expect(string.find(text, "^%-%-!strict") ~= nil).toBe(true)
			t.expect(string.find(text, "require%(") == nil).toBe(true)
			t.expect(string.find(text, 'return "PASS"%s*$') ~= nil).toBe(true)
		end
	end)

	it("the structure check asserts what the place must contain", function()
		local text = fs.readFile("tests/runtime/structure.luau")
		for _, needle in
			{
				"ServerScriptService",
				'"Server"',
				'"Main"',
				"Remotes",
				"Ready",
				"Intent",
				"Snapshot",
				"CharacterAutoLoads",
			}
		do
			t.expect(string.find(text, needle, 1, true) ~= nil).toBe(true)
		end
	end)
end)
