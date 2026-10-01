--!strict
-- c0140 AC3: scripts/deploy-beta is the thin command CI runs. Not configured, it says so and succeeds;
-- badly configured, or when the build fails, it fails before anything is sent.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
local script = `{root}/scripts/deploy-beta`
local work = `{root}/.cache/deploy-cli`

local function run(env: { [string]: string }, cwd: string?)
	return process.exec("lune", { "run", script }, { env = env, cwd = cwd or root })
end

return t.spec("c0140 scripts/deploy-beta", function(it)
	fs.writeDir(work) -- an empty directory: no Rojo project in it
	it("not configured: says so with a warning and succeeds, without building or sending", function()
		local r = run({ ROBLOX_API_KEY = "", ROBLOX_BETA_UNIVERSE_ID = "", ROBLOX_BETA_PLACE_ID = "" }, work)
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, "not configured", 1, true) ~= nil).toBe(true)
		t.expect(string.find(r.stdout, "::warning::", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout, "version=", 1, true))).toBe(nil)
	end)

	it("a missing id alone is also 'not configured'", function()
		local r =
			run({ ROBLOX_API_KEY = "k", ROBLOX_BETA_UNIVERSE_ID = "1", ROBLOX_BETA_PLACE_ID = "" }, work)
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stdout, "not configured", 1, true) ~= nil).toBe(true)
	end)

	it("an id that is not digits fails, and says which", function()
		local r = run({
			ROBLOX_API_KEY = "KEY-NOT-IN-OUTPUT",
			ROBLOX_BETA_UNIVERSE_ID = "1/2",
			ROBLOX_BETA_PLACE_ID = "3",
		}, work)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stdout .. r.stderr, "ROBLOX_BETA_UNIVERSE_ID", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout .. r.stderr, "KEY-NOT-IN-OUTPUT", 1, true))).toBe(nil)
	end)

	it("when the build fails it fails, reports it, and never reaches the API", function()
		-- configured, but there is no Rojo project in `work`; a valid key would otherwise be sent
		local r = run({
			ROBLOX_API_KEY = "KEY-NOT-IN-OUTPUT",
			ROBLOX_BETA_UNIVERSE_ID = "1",
			ROBLOX_BETA_PLACE_ID = "2",
		}, work)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stdout, "rojo build failed", 1, true) ~= nil).toBe(true)
		t.expect((string.find(r.stdout .. r.stderr, "KEY-NOT-IN-OUTPUT", 1, true))).toBe(nil)
		t.expect((string.find(r.stdout, "version=", 1, true))).toBe(nil)
	end)
end)
