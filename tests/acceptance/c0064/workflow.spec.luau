--!strict
-- c0064 AC5: the beta job with two places, on the parsed workflow. The deploy and both runtime steps get the
-- game place's variable and nothing else new; the lobby's runtime tests run, in a step of their own, only when
-- a lobby was published; the secret is in exactly those three steps' env.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local text = fs.readFile(".github/workflows/check.yml")
local wf: any = serde.decode("yaml" :: "yaml", text)
local beta: any = wf.jobs.beta

local KEY = "${{ secrets.ROBLOX_API_KEY }}"
local UNIVERSE = "${{ vars.ROBLOX_BETA_UNIVERSE_ID }}"
local PLACE = "${{ vars.ROBLOX_BETA_PLACE_ID }}"
local GAME = "${{ vars.ROBLOX_BETA_GAME_PLACE_ID }}"

local function keysOf(tbl: any): { string }
	local out = {}
	for k in tbl do
		if k ~= "name" then
			table.insert(out, tostring(k))
		end
	end
	table.sort(out)
	return out
end

local function has(s: any, needle: string): boolean
	return type(s) == "string" and string.find(s, needle, 1, true) ~= nil
end

local function count(haystack: string, needle: string): number
	local n, i = 0, 1
	while true do
		local s, e = string.find(haystack, needle, i, true)
		if not s then
			return n
		end
		n += 1
		i = (e :: number) + 1
	end
end

return t.spec("c0064 beta job with two places", function(it)
	it("has six steps: checkout, tools, deploy, comment, the game's runtime tests, the lobby's", function()
		local steps: any = beta.steps
		t.expect(#steps).toBe(6)
		t.expect(steps[3].id).toBe("deploy")
		t.expect(has(steps[4].run, "gh pr comment")).toBe(true)
		t.expect(steps[5].run).toBe('lune run scripts/runtime-test -- "$VERSION"')
		t.expect(steps[6].run).toBe('lune run scripts/runtime-test -- --lobby "$LOBBY_VERSION"')
	end)

	it("the deploy gets the game place's variable beside the three it had, and nothing else", function()
		t.expect(beta.steps[3].run).toBe("lune run scripts/deploy-beta")
		t.expect(beta.steps[3].env).toEqual({
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = UNIVERSE,
			ROBLOX_BETA_PLACE_ID = PLACE,
			ROBLOX_BETA_GAME_PLACE_ID = GAME,
		})
	end)

	it("the game's runtime step knows where the game place is", function()
		t.expect(beta.steps[5].env).toEqual({
			VERSION = "${{ steps.deploy.outputs.version }}",
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = UNIVERSE,
			ROBLOX_BETA_PLACE_ID = PLACE,
			ROBLOX_BETA_GAME_PLACE_ID = GAME,
		})
		t.expect(beta.steps[5]["if"]).toBe("steps.deploy.outputs.version != ''")
	end)

	it(
		"the lobby's runtime step runs only when a lobby was published, with exactly these keys and env",
		function()
			local step = beta.steps[6]
			t.expect(keysOf(step)).toEqual({ "env", "if", "run" })
			t.expect(step["if"]).toBe("steps.deploy.outputs.lobby_version != ''")
			t.expect(step.env).toEqual({
				LOBBY_VERSION = "${{ steps.deploy.outputs.lobby_version }}",
				ROBLOX_API_KEY = KEY,
				ROBLOX_BETA_UNIVERSE_ID = UNIVERSE,
				ROBLOX_BETA_PLACE_ID = PLACE,
				ROBLOX_BETA_GAME_PLACE_ID = GAME,
			})
		end
	)

	it("the comment step is unchanged and gets no Roblox setting", function()
		local step = beta.steps[4]
		t.expect(step["if"]).toBe("steps.deploy.outputs.version != ''")
		t.expect(step.env).toEqual({
			GH_TOKEN = "${{ github.token }}",
			PR = "${{ github.event.pull_request.number }}",
			VERSION = "${{ steps.deploy.outputs.version }}",
			SHA = "${{ github.event.pull_request.head.sha }}",
		})
	end)

	it("the secret is named three times, in the env of the deploy and the two runtime steps only", function()
		t.expect(count(text, "secrets.ROBLOX_API_KEY")).toBe(3)
		for i, step in beta.steps do
			local named = has(serde.encode("json" :: "json", step), "ROBLOX")
			t.expect(named).toBe(i == 3 or i == 5 or i == 6)
		end
		t.expect(beta.env).toBe(nil)
		t.expect(has(serde.encode("json" :: "json", wf.jobs.gate), "ROBLOX")).toBe(false)
	end)
end)
