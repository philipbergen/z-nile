--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local slow = require("@tests/lib/slow")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- A row names the path `./zn done` promotes the spec to. Until that move, the file is still
-- in the issue's acceptance folder. Either place counts; a path with no file does not.
local function present(path: string): boolean
	if fs.isFile(`{root}/z-nile/{path}`) then
		return true
	end
	local id, name = string.match(path, "^tests/acceptance/([fdc]%d%d%d%d)/([^/]+)$")
	if id == nil or name == nil then
		return false
	end
	local issues = `{root}/z-nile/.tracker/issues`
	local places = {
		`{issues}/active/{id}/acceptance/{name}`,
		`{issues}/{id}/acceptance/{name}`,
		`{issues}/done/{id}/acceptance/{name}`,
	}
	for _, place in places do
		if fs.isFile(place) then
			return true
		end
	end
	return false
end

return t.spec("the measured slow-tier manifest", function(it)
	it("names 104 existing z-nile specs with their recorded seconds", function()
		local tiers = slow.load(root)
		local count = 0
		for path, seconds in tiers do
			count += 1
			t.expect(string.match(path, "^tests/.*%.spec%.luau$") ~= nil).toBe(true)
			t.expect(present(path)).toBe(true)
			t.expect(seconds > 0).toBe(true)
		end
		t.expect(count).toBe(104)
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
