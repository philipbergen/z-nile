--!strict
-- c0064 AC5, overridden by c0172: the deploy job publishes both places. Runtime suites are not workflow steps.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from its home: the checkout's files are read from the top
local text = fs.readFile("../.github/workflows/deploy.yml")
local wf: any = serde.decode("yaml" :: "yaml", text)
local deploy: any = wf.jobs.deploy

local KEY = "${{ secrets.ROBLOX_API_KEY }}"
local UNIVERSE = "${{ vars.ROBLOX_BETA_UNIVERSE_ID }}"
local PLACE = "${{ vars.ROBLOX_BETA_PLACE_ID }}"
local GAME = "${{ vars.ROBLOX_BETA_GAME_PLACE_ID }}"

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

local function stepWith(needle: string): any
	for _, step in deploy.steps do
		if has(step.run, needle) then
			return step
		end
	end
	return nil
end

return t.spec("c0064 deploy job with two places", function(it)
	it("the deploy gets the game place's variable beside the three it had, and nothing else", function()
		local publish = stepWith("lune run scripts/deploy-beta")
		t.expect(publish ~= nil).toBe(true)
		t.expect(publish.run).toBe("lune run scripts/deploy-beta")
		t.expect(publish.env).toEqual({
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = UNIVERSE,
			ROBLOX_BETA_PLACE_ID = PLACE,
			ROBLOX_BETA_GAME_PLACE_ID = GAME,
		})
	end)

	it("the comment step is present and gets no Roblox setting", function()
		local step = stepWith("gh pr comment")
		t.expect(step ~= nil).toBe(true)
		t.expect(step.env).toEqual({
			GH_TOKEN = "${{ github.token }}",
			PR = "${{ github.event.pull_request.number }}",
			VERSION = "${{ steps.deploy.outputs.version }}",
			SHA = "${{ github.event.pull_request.head.sha }}",
		})
	end)

	it("the secret is named once, in the deploy step's env", function()
		t.expect(count(text, "secrets.ROBLOX_API_KEY")).toBe(1)
		for _, step in deploy.steps do
			local named = has(serde.encode("json" :: "json", step), "ROBLOX")
			t.expect(named).toBe(step.id == "deploy")
		end
		t.expect(deploy.env).toBe(nil)
	end)
end)
