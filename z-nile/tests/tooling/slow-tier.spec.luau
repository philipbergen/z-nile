--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local slow = require("@tests/lib/slow")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("the measured slow-tier manifest", function(it)
	it("names 97 existing z-nile specs with their recorded seconds", function()
		local tiers = slow.load(root)
		local count = 0
		for path, seconds in tiers do
			count += 1
			t.expect(string.match(path, "^tests/.*%.spec%.luau$") ~= nil).toBe(true)
			t.expect(fs.isFile(`{root}/z-nile/{path}`)).toBe(true)
			t.expect(seconds > 0).toBe(true)
		end
		t.expect(count).toBe(97)
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
		t.expect(durations[25] >= 84.722).toBe(true)
	end)

	it("keep drops the slow tier or keeps only it", function()
		local tiers = { ["tests/slow.spec.luau"] = 1 }
		local files = { "tests/slow.spec.luau", "tests/fast.spec.luau" }
		t.expect(slow.keep(files, tiers, "fast")).toEqual({ "tests/fast.spec.luau" })
		t.expect(slow.keep(files, tiers, "slow")).toEqual({ "tests/slow.spec.luau" })
	end)

	it("refuses --slow together with --exclude-slow before taking the suite lock", function()
		local r = process.exec("lune", { "run", "tests/run", "--", "--slow", "--exclude-slow" })
		t.expect(r.code).toBe(2)
		t.expect(string.find(r.stderr, "conflict", 1, true) ~= nil).toBe(true)
	end)
end)
