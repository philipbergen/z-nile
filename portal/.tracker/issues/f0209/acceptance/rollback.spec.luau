--!strict
-- f0209 AC4: the way back, until c0188 deletes pickman's lobby. The switch is one line of portal/experience.json: the
-- Portal place's "build": "portal". That line set back to "build": "lobby", and nothing else changed, gives a manifest
-- the reader takes whose plan publishes pickman's lobby to the start place, told GamePlaceId, as before f0209, with
-- Pickman's game still told the start place's id. Pure: no Rojo, no network. c0188 retires this file with the lobby.
local Beta = require("@scripts/lib/beta")
local Experience = require("@scripts/lib/experience")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.cwd, "/+$", ""))
local SWITCH = '"build": "portal"'
local BACK = '"build": "lobby"'

local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

-- the checked-in manifest with the switch's line set back
local function rolledBack(): (string, string)
	local text = fs.readFile("experience.json")
	local back, n = string.gsub(text, SWITCH, BACK)
	assert(n == 1, `experience.json holds {n} copies of {SWITCH}, not one`)
	return text, back
end

return t.spec("f0209 the start place goes back to the lobby by one line", function(it)
	it("the switch is one line, the Portal place's", function()
		local text, back = rolledBack()
		local a, b = lines(text), lines(back)
		t.expect(#b).toBe(#a)
		local changed: { string } = {}
		for i, line in a do
			if line ~= b[i] then
				table.insert(changed, line)
			end
		end
		t.expect(#changed).toBe(1)
		t.expect(string.find(changed[1], '"name": "Portal"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(changed[1], '"env": ["ROBLOX_BETA_PLACE_ID"]', 1, true) ~= nil).toBe(true)
	end)

	it("set back, the start place publishes pickman's lobby, told GamePlaceId, as before f0209", function()
		local _, back = rolledBack()
		local manifest, err = Experience.parse(back, root)
		t.expect(err).toBe(nil)
		local plan = Beta.plan({
			ROBLOX_API_KEY = "KEY",
			ROBLOX_BETA_UNIVERSE_ID = "111",
			ROBLOX_BETA_PLACE_ID = "222",
			ROBLOX_BETA_GAME_PLACE_ID = "333",
		}, manifest :: Experience.Manifest) :: Beta.Plan
		t.expect(#plan.targets).toBe(2)
		local game, start = plan.targets[1], plan.targets[2]
		t.expect(start.name).toBe("Portal")
		t.expect(start.placeId).toBe("222")
		t.expect(start.project).toBe("../pickman/lobby.project.json")
		t.expect(start.runtime).toBe("../pickman/tests/runtime/lobby")
		t.expect(start.attributes.GamePlaceId).toBe(333)
		t.expect(start.output).toBe("lobby_version")
		t.expect(fs.isFile(start.project)).toBe(true)
		t.expect(game.name).toBe("Pickman")
		t.expect(game.placeId).toBe("333")
		t.expect(game.attributes.PortalPlaceId).toBe(222)
	end)
end)
