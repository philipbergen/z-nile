--!strict
-- c0140 AC6: someone setting up the repo can find out how Beta publishing is configured and what it does.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local setup = fs.readFile("../SETUP.md")

local function has(needle: string): boolean
	return string.find(setup, needle, 1, true) ~= nil
end

return t.spec("c0140 SETUP.md documents Beta publishing", function(it)
	it("names the secret, the two variables and the key's publish scope", function()
		for _, needle in
			{ "ROBLOX_API_KEY", "ROBLOX_BETA_UNIVERSE_ID", "ROBLOX_BETA_PLACE_ID", "universe-places" }
		do
			t.expect(has(needle)).toBe(true)
		end
	end)

	it("says what triggers a publish, that a missing setting skips, and that forks get no secret", function()
		t.expect(has("ready for review")).toBe(true)
		t.expect(has("skips")).toBe(true)
		t.expect(has("Forks")).toBe(true)
		t.expect(has("gates finish")).toBe(true) -- the order is gate completion, and the comment names the commit
	end)

	it("documents the tools-only setup mode and how to publish by hand", function()
		t.expect(has("z-nile/setup.sh --tools")).toBe(true)
		t.expect(has("lune run scripts/deploy-beta")).toBe(true)
	end)
end)
