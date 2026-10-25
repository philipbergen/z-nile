--!strict
-- c0064 AC6: SETUP.md says how Beta publishes two places and what the owner of the experience must do once,
-- in order, and the testing skill lists the lobby's runtime scripts.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from its home: the checkout's files are read from the top
local setup = fs.readFile("../SETUP.md")
local testing = fs.readFile("../.claude/skills/testing/SKILL.md")

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- the Beta publishing section of SETUP.md
local function beta(): string
	local from = string.find(setup, "## Beta publishing", 1, true)
	assert(from, "SETUP.md has a Beta publishing section")
	local to = string.find(setup, "\n## ", from + 5, true)
	return string.sub(setup, from, to)
end

return t.spec("c0064 docs for two places", function(it)
	it(
		"the Beta section names the game place's variable, both projects and which place gets which",
		function()
			local s = beta()
			for _, needle in
				{
					"ROBLOX_BETA_GAME_PLACE_ID",
					"default.project.json",
					"lobby.project.json",
					"GamePlaceId",
					"start place",
					"tests/runtime/lobby",
					"runtime-test -- --lobby",
				}
			do
				t.expect(has(s, needle)).toBe(true)
			end
		end
	)

	it(
		"the owner's one-time steps are a numbered list: create the place, set the variable, check the key",
		function()
			local s = beta()
			local create = string.find(s, "\n%s*1%. [^\n]*Creator Dashboard[^\n]*place id")
			local variable = string.find(s, "\n%s*2%. [^\n]*ROBLOX_BETA_GAME_PLACE_ID")
			local key = string.find(s, "\n%s*3%. [^\n]*ROBLOX_API_KEY")
			t.expect(create ~= nil and variable ~= nil and key ~= nil).toBe(true)
			t.expect((create :: number) < (variable :: number) and (variable :: number) < (key :: number))
				.toBe(true)
		end
	)

	it(
		"says that without the variable the game still publishes to the start place and the lobby is not live",
		function()
			local s = beta()
			t.expect(has(s, "Without it")).toBe(true)
			t.expect(has(s, "the lobby is not live")).toBe(true)
		end
	)

	it("the testing skill's runtime tier names the lobby's scripts", function()
		t.expect(has(testing, "tests/runtime/lobby/")).toBe(true)
		t.expect(has(testing, "--lobby")).toBe(true)
	end)
end)
