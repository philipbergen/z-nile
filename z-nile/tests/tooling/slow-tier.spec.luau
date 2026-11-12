--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local slow = require("@tests/lib/slow")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("the measured slow-tier manifest", function(it)
	it("names 62 existing z-nile specs with their recorded seconds", function()
		local tiers = slow.load(root)
		local count = 0
		for path, seconds in tiers do
			count += 1
			t.expect(string.match(path, "^tests/.*%.spec%.luau$") ~= nil).toBe(true)
			t.expect(fs.isFile(`{root}/z-nile/{path}`)).toBe(true)
			t.expect(seconds > 0).toBe(true)
		end
		t.expect(count).toBe(62)
	end)

	it("has at least the 25 slowest recorded specs", function()
		local tiers = slow.load(root)
		local durations = {}
		for _, seconds in tiers do
			table.insert(durations, seconds)
		end
		table.sort(durations, function(a, b)
			return a > b
		end)
		t.expect(durations[25] >= 85.794).toBe(true)
	end)
end)
