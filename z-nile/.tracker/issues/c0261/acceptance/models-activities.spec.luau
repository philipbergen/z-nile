--!strict
-- c0261: each activity (a command, or a command's activity: a review round, the final round) has its own table in
-- .models.toml, `[<activity>.<cli>]`, with the real model, its effort and its budget; a review activity the file does
-- not name falls back to the `zz-review` table; the final reviews obey the review rule and the rounds on the way do not.
-- Pure: models.parse, models.resolveActivity and models.reviewRule over layers built from text.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local m = models :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local function table_(activity: string, cli: string, model: string, effort: string?, rank: number): string
	return `[{activity}.{cli}]\nmodel = "{model}"\n`
		.. (if effort then `effort = "{effort}"\n` else "")
		.. `rank = {rank}\nruntime = "{models.RUNTIMES[cli][1]}"\nmax_tokens = 100\n`
		.. (if cli == "agent" then "max_calls = 9\nmax_minutes = 9\n" else "")
end
local ORDER = 'order = ["claude", "grok", "agent"]\n'
-- every CLI for one activity: the cheap models, or the expensive ones
local function cheap(activity: string): string
	return table_(activity, "claude", "claude-sonnet-5", nil, 2)
		.. table_(activity, "grok", "grok-4.6", "high", 2)
		.. table_(activity, "agent", "cursor-grok-4.6-high", nil, 2)
end
local function sharp(activity: string): string
	return table_(activity, "claude", "claude-opus-5-5", nil, 4)
		.. table_(activity, "grok", "grok-4.7", "xhigh", 4)
		.. table_(activity, "agent", "grok-4.7-xhigh", nil, 4)
end
local function layer(text: string, path: string?): models.Layer
	return models.parse(text, path or ".models.toml")
end
local function errorOf(f: () -> ()): string
	local ok: boolean, e: any = pcall(f)
	if ok then
		error("expected an error", 2)
	end
	return tostring(e)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0261 a model per activity", function(it)
	it("an activity resolves its own table: the middle round cheap, the final round expensive (AC1)", function()
		local file = ORDER .. cheap("zz-review-design") .. sharp("zz-review-design-final")
		local mid = m.resolveActivity({ layer(file) }, "zz-review-design")
		local fin = m.resolveActivity({ layer(file) }, "zz-review-design-final")
		t.expect(models.id(mid.specs.claude)).toBe("claude-sonnet-5")
		t.expect(models.id(mid.specs.grok)).toBe("grok-4.6-high")
		t.expect(models.id(fin.specs.claude)).toBe("claude-opus-5-5")
		t.expect(models.id(fin.specs.agent)).toBe("grok-4.7-xhigh")
		t.expect(fin.specs.grok.rank).toBe(4)
		t.expect(fin.skill).toBe("zz-review-design-final")
	end)

	it("an activity table nobody names falls back to zz-review, and any other falls to an error (AC1)", function()
		local file = ORDER .. sharp("zz-review")
		local r = m.resolveActivity({ layer(file) }, "zz-review-code")
		t.expect(r.skill).toBe("zz-review")
		t.expect(models.id(r.specs.claude)).toBe("claude-opus-5-5")
		t.expect(has(errorOf(function()
			m.resolveActivity({ layer(file) }, "z-wait")
		end), "z-wait")).toBe(true)
	end)

	it("a closer file replaces only the keys it sets, per activity (AC1)", function()
		local file = ORDER .. cheap("z-wait")
		local closer = layer('[z-wait.claude]\nmodel = "claude-haiku-5-5"\n', "pickman/.models.toml")
		local r = m.resolveActivity({ layer(file), closer }, "z-wait")
		t.expect(r.specs.claude.model).toBe("claude-haiku-5-5")
		t.expect(r.specs.claude.rank).toBe(2)
	end)

	it("a final review obeys the review rule: Opus on claude, Opus or a grok at xhigh on agent, grok at xhigh on grok (AC2)", function()
		local function bad(activity: string, cli: string, model: string, effort: string?): string
			return errorOf(function()
				m.resolveActivity({ layer(ORDER .. table_(activity, cli, model, effort, 4)) }, activity)
			end)
		end
		t.expect(has(bad("zz-review-design-final", "claude", "claude-sonnet-5"), "Opus")).toBe(true)
		t.expect(has(bad("zz-review-code-final", "grok", "grok-4.7", "high"), "xhigh")).toBe(true)
		t.expect(has(bad("zz-review-idea", "agent", "cursor-grok-4.6-high"), "xhigh")).toBe(true)
		t.expect(has(bad("zz-review-raft", "claude", "claude-haiku-5-5"), "Opus")).toBe(true)
		for _, a in { "zz-review-design-final", "zz-review-code-final", "zz-review-raft", "zz-review-idea", "zz-review-final" } do
			t.expect(m.resolveActivity({ layer(ORDER .. table_(a, "agent", "grok-4.7-xhigh", nil, 4)) }, a) ~= nil).toBe(true)
			t.expect(m.resolveActivity({ layer(ORDER .. table_(a, "agent", "claude-opus-5-5-high", nil, 4)) }, a) ~= nil).toBe(true)
		end
	end)

	it("the rounds on the way and the other commands take any model (AC2)", function()
		for _, a in { "zz-review-design", "zz-review-code", "zz-review-stream", "z-design", "z-run", "z-wait" } do
			local r = m.resolveActivity({ layer(ORDER .. cheap(a)) }, a)
			t.expect(models.id(r.specs.claude)).toBe("claude-sonnet-5")
		end
	end)

	it("the pin rule of a plain zz-review table stays as c0117 had it (AC2)", function()
		local pin = ORDER .. table_("zz-review", "claude", "claude-sonnet-5", nil, 4)
		t.expect(has(errorOf(function()
			models.resolve({ layer(pin) }, "zz-review")
		end), "runs on Opus")).toBe(true)
	end)

	it("every final-review activity is named, and the rounds on the way are not among them (AC2)", function()
		local finals = m.FINAL_REVIEWS
		for _, a in { "zz-review", "zz-review-design-final", "zz-review-code-final", "zz-review-raft", "zz-review-idea", "zz-review-final" } do
			t.expect(`{a}: {finals[a] == true}`).toBe(`{a}: true`)
		end
		for _, a in { "zz-review-design", "zz-review-code", "zz-review-stream", "z-design" } do
			t.expect(`{a}: {finals[a] == true}`).toBe(`{a}: false`)
		end
	end)

	it("[dispatch] wait_minutes is a whole number of minutes, 60 unless a file sets it (AC1)", function()
		t.expect(m.settings({ layer(ORDER .. cheap("z-wait")) }).waitMinutes).toBe(60)
		t.expect(m.settings({ layer(ORDER .. "[dispatch]\nwait_minutes = 5\n" .. cheap("z-wait")) }).waitMinutes).toBe(5)
		local closer = layer("[dispatch]\nwait_minutes = 9\n", "pickman/.models.toml")
		t.expect(m.settings({ layer(ORDER .. "[dispatch]\nwait_minutes = 5\n"), closer }).waitMinutes).toBe(9)
		t.expect(has(errorOf(function()
			layer("[dispatch]\nwait_minutes = 0\n")
		end), "wait_minutes")).toBe(true)
	end)
end)
