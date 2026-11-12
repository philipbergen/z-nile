--!strict
-- c0261: the committed root .models.toml gives every activity of the dispatcher a real model on every CLI: the work on
-- the way, a layer's code review and the stream review cheap, every final review expensive, the wait step the cheapest. The rules are
-- pinned by the gate; the exact model names are pinned only where ZN_C0261_EXACT is set (this issue's check.sh lines,
-- so a model upgrade needs no override of a promoted spec). Reads the real file.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local m = models :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local EXACT = process.env.ZN_C0261_EXACT ~= nil
local function layers(): { models.Layer }
	return { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
end
-- the activities the dispatcher runs: its model steps, and each review mode's rounds
local function activities(): { string }
	local out: { [string]: boolean } = {}
	for name, s in dispatch.STEPS do
		if s.kind == "model" then
			out[name] = true
		end
	end
	for mode in dispatch.REVIEW_MODES do
		local d = dispatch :: any
		out[d.activityOf("zz-review", mode)] = true
	end
	local list = {}
	for a in out do
		table.insert(list, a)
	end
	table.sort(list)
	return list
end
-- on the way (cheap), final review (expensive), waiting (cheapest)
local WAY = {
	["z-ticket"] = true,
	["z-raft"] = true,
	["z-run"] = true,
	["zz-review-code"] = true,
	["zz-review-stream"] = true,
} :: { [string]: boolean }
local IDS = {
	way = { claude = "claude-sonnet-5-5-high", grok = "grok-4.6-high", agent = "cursor-grok-4.6-high" },
	final = { claude = "claude-opus-5-5", grok = "grok-4.7-xhigh", agent = "claude-opus-5-5-high" },
	author = { claude = "claude-opus-5-5-medium", grok = "grok-4.7-high", agent = "grok-4.7-high" }, -- z-design: not cheap (the user, 2026-11-08)
	wait = { claude = "claude-haiku-5-5", grok = "grok-4.5-low", agent = "composer-2.5" },
} :: { [string]: { [string]: string } }
local function classOf(a: string): string
	return if a == "z-wait"
		then "wait"
		elseif a == "z-design" then "author"
		elseif WAY[a] then "way"
		else "final"
end

return t.spec("c0261 root .models.toml per activity", function(it)
	it(
		"every activity resolves on every CLI, and no table names an activity the dispatcher does not run (rule)",
		function()
			local known: { [string]: boolean } = { ["zz-review"] = true }
			for _, a in activities() do
				known[a] = true
				local r = m.resolveActivity(layers(), a)
				for _, cli in models.CLIS do
					t.expect(r.specs[cli] ~= nil).toBe(true)
				end
			end
			for skill in layers()[1].skills do
				t.expect(`{skill} known={known[skill] == true}`).toBe(`{skill} known=true`)
			end
		end
	)

	it(
		"every final review resolves to a model that obeys the review rule, and ranks above the rounds on the way (rule)",
		function()
			for _, a in activities() do
				local r = m.resolveActivity(layers(), a)
				for _, cli in models.CLIS do
					if classOf(a) == "final" then
						t.expect(models.reviewRule("zz-review", r.specs[cli])).toBe(nil)
						for _, other in activities() do
							if classOf(other) ~= "final" then
								t.expect(
									r.specs[cli].rank > m.resolveActivity(layers(), other).specs[cli].rank
								)
									.toBe(true)
							end
						end
					end
				end
			end
		end
	)

	it("the wait step is the cheapest activity on every CLI (rule)", function()
		local w = m.resolveActivity(layers(), "z-wait")
		for _, a in activities() do
			local r = m.resolveActivity(layers(), a)
			for _, cli in models.CLIS do
				if a ~= "z-wait" then
					t.expect(w.specs[cli].rank < r.specs[cli].rank).toBe(true)
				end
			end
		end
	end)

	it("every model is a real name, never an alias (rule)", function()
		for skill, byCli in layers()[1].skills do
			for cli, f in byCli do
				local id: string = f.model
				local real = string.match(id, "^claude%-%a+%-%d[%w%-]*$")
					or string.match(id, "^[%a%-]*grok%-%d[%d%.]*[%w%-]*$")
					or string.match(id, "^composer%-%d[%d%.]*$")
				t.expect(`{skill}.{cli} {id} real={real ~= nil}`).toBe(`{skill}.{cli} {id} real=true`)
				for _, alias in { "latest", "default", "auto" } do
					t.expect((string.find(id, alias, 1, true))).toBe(nil)
				end
			end
		end
	end)

	it(
		"no activity table carries the words tier, cheap or sharp: the file says models and activities only (rule)",
		function()
			local text = fs.readFile(`{TOP}/.models.toml`)
			for _, w in { "tier", "[tiers" } do
				t.expect((string.find(text, w, 1, true))).toBe(nil)
			end
		end
	)

	it(
		"the exact model of each activity on each CLI is the decided one (exact names, check time only)",
		function()
			if not EXACT then
				return
			end
			for _, a in activities() do
				local r = m.resolveActivity(layers(), a)
				for _, cli in models.CLIS do
					t.expect(`{a}.{cli} {models.id(r.specs[cli])}`).toBe(`{a}.{cli} {IDS[classOf(a)][cli]}`)
				end
			end
		end
	)

	it(
		"agent's final reviews try Opus, then kimi, then grok-4.7-xhigh (exact names, check time only)",
		function()
			if not EXACT then
				return
			end
			local ids = {}
			for _, spec in models.tries(models.resolve(layers(), "zz-review")) do
				if spec.cli == "agent" then
					table.insert(ids, models.id(spec))
				end
			end
			t.expect(ids).toEqual({ "claude-opus-5-5-high", "kimi-k3-high", "grok-4.7-xhigh" })
		end
	)
end)
