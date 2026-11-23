--!strict
-- f0420 with f0421 step 8b: the order, the theme and the named ticket meet the capability filter. Pure: a fixture config (the design's seed, here as text), facts in, answers out.
--   - a unit whose next activity the worker's CLI lacks is skipped for one it can do, and stays in the facts (a dependent never
--     reads it as landed);
--   - when every unit open to it needs what its CLI lacks, the answer is a wait that starts `waiting for a worker with `
--     (work.WAITING, the words ./zn model's exit 1 prints too) and the z-work skill matches that same constant;
--   - a worker that cannot be named (nil capability) gets what it always got.
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workcan = require("@znile/engine/workcan")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

-- A fixture configuration: claude has all four aliases, grok only light, kimi only heavy (an invented fixture, not the seed).
local CONFIG = [[
[clis.claude]
xlight = { model = "claude-haiku-5-5", effort = "low" }
light = { model = "claude-sonnet-5-5", effort = "medium" }
heavy = { model = "claude-opus-5-5", effort = "high" }
ultra = { model = "claude-fable-5-2", effort = "xhigh" }
[clis.grok]
light = { model = "grok-4.7", effort = "high" }
[clis.kimi]
heavy = { model = "kimi-code-k3.1-pro" }
[activities.idea]
max_tokens = 300000
all = "heavy"
[activities.idea-challenge]
max_tokens = 300000
all = "ultra"
[activities.design]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.design-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.raft]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.raft-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.code]
max_tokens = 12000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.code-review]
max_tokens = 2000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.final-review]
max_tokens = 2000000
all = "ultra"
[activities.approve]
max_tokens = 3000000
all = "heavy"
]]

local LAYERS = { models.parse(CONFIG, ".models.toml") }

local function cap(cli: string): work.Capability
	return workcan.of(LAYERS, cli)
end

-- An active raft whose one layer is finished and stacked: its next action is the code review, round 1.
local function issue(id: string, over: { [string]: any }?): work.IssueFact
	local i: work.IssueFact = {
		id = id,
		root = "z-nile/.tracker",
		status = "new",
		raft = "",
		designReady = false,
		sized = false,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

return t.spec("f0420 with the capability filter: order, theme, named ticket", function(it)
	it("a theme whose bottom dependency the CLI lacks waits, naming the CLI needed", function()
		local d = work.decide({
			tributary = "worker",
			rafts = {},
			issues = {
				issue("c0050", { tributary = "board" }),
				issue("c0030", { tributary = "worker", deps = { "c0050" } }),
				-- outside the theme and unrelated, and kimi CAN design it (risky needs heavy): the theme must not take it
				issue("c0001", { tributary = "board", level = "risky" }),
			},
			session = "s",
			capable = cap("kimi"),
		})
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d.why, "c0050")).toBe(true)
		t.expect(has(d.why, "claude, grok")).toBe(true)
		t.expect(has(d.why, "c0001")).toBe(false)
	end)

	it("a named ticket whose dependency the CLI lacks waits, naming the CLI needed, never none", function()
		local d = work.decide({
			asked = "c0100",
			rafts = {},
			issues = { issue("c0100", { deps = { "c0090" } }), issue("c0090") },
			session = "s",
			capable = cap("kimi"),
		})
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d.why, "c0090")).toBe(true)
		t.expect(has(d.why, "claude, grok")).toBe(true)
	end)

	it("work.order applies among the units the worker can do", function()
		-- c0010 is easy (design needs xlight: grok lacks it) and unblocks two; c0020 unblocks none; c0030 unblocks one
		local issues = {
			issue("c0010", { level = "easy" }),
			issue("c0020"),
			issue("c0030"),
			issue("c0040", { deps = { "c0010" } }),
			issue("c0050", { deps = { "c0010" } }),
			issue("c0060", { deps = { "c0030" } }),
		}
		local d = work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("grok") })
		t.expect(d.action).toBe("draft")
		t.expect(d.ticket).toBe("c0030")
		-- a CLI that can do everything takes c0010, which unblocks the most
		local all = work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("claude") })
		t.expect(all.ticket).toBe("c0010")
	end)
end)
