--!strict
-- c0030 AC3: scripts/runtime-test is the command CI runs against the version it just published. Here only
-- the paths that need no network: its usage, and "not configured" as a green skip.
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: pickman's home, where its specs run (its scripts, project files and .cache are there)
local root = (string.gsub(process.cwd, "/+$", ""))
local script = `{root}/scripts/runtime-test`

local NONE = { ROBLOX_API_KEY = "", ROBLOX_BETA_UNIVERSE_ID = "", ROBLOX_BETA_PLACE_ID = "" }

local function run(args: { string }, env: { [string]: string })
	local argv = { "run", script, "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("lune", argv, { env = env, cwd = root })
end

return t.spec("c0030 scripts/runtime-test", function(it)
	it(
		"needs a version number: usage and exit 2 without one, or with one that isn't a whole number >= 1",
		function()
			for _, args in { {}, { "abc" }, { "0" }, { "-3" }, { "1.5" } } do
				local r = run(args, NONE)
				t.expect(r.code).toBe(2)
				t.expect(string.find(r.stdout, "usage", 1, true) ~= nil).toBe(true)
			end
		end
	)

	it("not configured: says so with a warning and succeeds", function()
		local r = run({ "5" }, NONE)
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, "not configured", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "::warning::", 1, true) ~= nil).toBe(true)
	end)

	it("a badly configured id fails before anything is sent, and the key is not printed", function()
		local r = run({ "5" }, {
			ROBLOX_API_KEY = "KEY-NOT-IN-OUTPUT",
			ROBLOX_BETA_UNIVERSE_ID = "1/2",
			ROBLOX_BETA_PLACE_ID = "3",
		})
		t.expect(r.ok).toBe(false)
		t.expect((string.find(r.stdout .. r.stderr, "KEY-NOT-IN-OUTPUT", 1, true))).toBe(nil)
	end)
end)
