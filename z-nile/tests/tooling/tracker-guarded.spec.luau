--!strict
-- R0025 review 001 F5: the commands this raft added change a repository (ready, stop and land publish; prompt reads
-- the main checkout), so they run the repository guard: none is in main.luau's READ_ONLY table, which is exactly
-- the read-only set c0053's lost-.git case exempts.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function readOnly(): { string }
	local text = fs.readFile(`{engine.TOP}/z-nile/engine/main.luau`) -- from the top: specs run in their home (c0120)
	local block = string.match(text, "\nlocal READ_ONLY: { %[string%]: boolean } = {\n(.-)\n}\n")
	assert(block, "main.luau has no READ_ONLY table")
	local out: { string } = {}
	for line in string.gmatch((block :: string) .. "\n", "([^\n]*)\n") do
		local name = string.match(line, '^%s*%[?"?([%w%-]+)"?%]?%s*=%s*true,?%s*$')
		if name then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

return t.spec("tracker commands that change a repository are guarded", function(it)
	it("READ_ONLY is exactly the read-only set", function()
		t.expect(readOnly()).toEqual({
			"audit",
			"board",
			"find",
			"list",
			"members",
			"metrics",
			"promote-check",
			"stack",
			"stamp",
			"trace",
			"workstreams",
		})
	end)

	it("ready, stop, land and prompt are not read-only", function()
		for _, name in readOnly() do
			t.expect(table.find({ "ready", "stop", "land", "prompt", "sync", "worktree" }, name)).toBe(nil)
		end
	end)
end)
