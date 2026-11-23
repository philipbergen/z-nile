--!strict
-- f0421 step 8b (the capability filter in `work next`): a worker is handed an activity only when its CLI can deliver the model
-- that activity needs at the unit's risk level. Pure: a fixture config (the design's seed, here as text), facts in, answers out.
--   - a unit whose next activity the worker's CLI lacks is skipped for one it can do, and stays in the facts (a dependent never
--     reads it as landed);
--   - when every unit open to it needs what its CLI lacks, the answer is a wait that starts `waiting for a worker with `
--     (work.WAITING, the words ./zn model's exit 1 prints too) and the z-work skill matches that same constant;
--   - a worker that cannot be named (nil capability) gets what it always got.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workcan = require("@znile/engine/workcan")
local workerlive = require("@znile/engine/workerlive")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

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

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = id,
		title = id,
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = {},
		layers = {},
		holder = "",
		since = "",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "z-nile/.tracker",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

-- An active raft whose one layer is finished and stacked: its next action is the code review, round 1.
local function reviewable(id: string, ticket: string, over: { [string]: any }?): work.RaftFact
	local r = raft(id, {
		where = "active",
		issues = { ticket },
		layers = { { position = 1, issue = ticket, name = `{id}/1/{ticket}`, commits = 3, onlyStart = false, finished = true } },
		stacked = true,
	})
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

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

return t.spec("f0421 step 8b: the capability filter of work next", function(it)
	it("models.waiting is the one wording: the need and the CLIs that deliver it", function()
		t.expect(models.waiting(LAYERS, "code-review", "normal")).toBe("code-review/normal (heavy: claude, kimi)")
		t.expect(models.waiting(LAYERS, "code-review", "risky")).toBe("code-review/risky (ultra: claude)")
	end)

	it("a worker whose CLI lacks the next activity of the only unit waits, naming activity, unit and need", function()
		local d = work.decide({
			asked = "R0100",
			rafts = { reviewable("R0100", "c0100") },
			issues = { issue("c0100", { status = "active", raft = "R0100" }) },
			capable = cap("grok"),
		})
		t.expect(d.action).toBe("wait")
		t.expect(d.owed).toBe(nil)
		t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d.why, "code-review/normal (heavy: claude, kimi)")).toBe(true)
		t.expect(has(d.why, "R0100")).toBe(true)
		t.expect(has(d.why, "grok")).toBe(true)
		t.expect(has(d.why, "is not landed yet:")).toBe(false) -- never the Stops text: the person owes nothing
		-- the same raft on a CLI that has heavy is handed the review
		local ok = work.decide({
			asked = "R0100",
			rafts = { reviewable("R0100", "c0100") },
			issues = { issue("c0100", { status = "active", raft = "R0100" }) },
			capable = cap("claude"),
		})
		t.expect(ok.action).toBe("review")
	end)

	it("answering a review is the writer's activity, not the reviewer's: a worker that can code is handed it", function()
		local d = work.decide({
			asked = "R0100",
			rafts = { reviewable("R0100", "c0100", { codeReview = "open", codeRound = 1 }) },
			issues = { issue("c0100", { status = "active", raft = "R0100" }) },
			capable = cap("grok"), -- grok has light: code/normal
		})
		t.expect(d.action).toBe("review")
	end)

	it("an unnamed pick skips the unit it cannot do for one it can, and the skipped one stays a fact", function()
		local issues = {
			issue("c0090"), -- design/normal: light
			issue("c0095", { level = "risky" }), -- design/risky: heavy
			issue("c0099", { deps = { "c0090" }, status = "prepared", designReady = true, sized = true }),
		}
		local claude = work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("claude") })
		t.expect(claude.ticket).toBe("c0090")
		local kimi = work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("kimi") })
		t.expect(kimi.ticket).toBe("c0095") -- kimi has heavy only
		t.expect(kimi.action).toBe("draft")
		-- c0099 depends on the skipped c0090: it is never handed out as if c0090 had landed
		local grok = work.decide({
			rafts = {},
			issues = { issues[1], issues[3] },
			session = "s",
			capable = cap("kimi"),
		})
		t.expect(grok.action).toBe("wait")
		t.expect(grok.ticket ~= "c0099").toBe(true)
	end)

	it("when every unit needs what the CLI lacks, an unnamed worker waits with the same words", function()
		local d = work.decide({
			rafts = {},
			issues = { issue("c0090"), issue("c0091") },
			session = "s",
			capable = cap("kimi"),
		})
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d.why, "design/normal (light: claude, grok)")).toBe(true)
		t.expect(has(d.why, "c0090")).toBe(true)
		t.expect(work.report({ rafts = {}, issues = {}, session = "s" }, d)).toBe(work.say(d))
	end)

	it("with no capability nothing changes", function()
		local d = work.decide({ rafts = {}, issues = { issue("c0090") }, session = "s" })
		t.expect(d.action).toBe("draft")
	end)

	it("a skipped unit of a named raft's closure goes to the unit that can be worked", function()
		local dep = reviewable("R0090", "c0090") -- its next action is a review: heavy
		local top = raft("R0100", {
			where = "active",
			issues = { "c0100" },
			layers = {},
			outside = { "c0090" },
			depsMet = false,
		})
		local other = reviewable("R0080", "c0080", { codeReview = "open", codeRound = 1 }) -- an answer: code
		local issues = {
			issue("c0080", { status = "active", raft = "R0080" }),
			issue("c0090", { status = "active", raft = "R0090" }),
			issue("c0100", { status = "prepared", raft = "R0100", deps = { "c0090", "c0080" } }),
		}
		local d = work.decide({
			asked = "R0100",
			rafts = { top, dep, other },
			issues = issues,
			capable = cap("grok"),
		})
		t.expect(d.raft).toBe("R0080")
		-- when R0080 is done too, only the review is left: the wait names it
		local d2 = work.decide({
			asked = "R0100",
			rafts = { top, dep },
			issues = { issues[2], issues[3] },
			capable = cap("grok"),
		})
		t.expect(d2.action).toBe("wait")
		t.expect(string.sub(d2.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d2.why, "R0090")).toBe(true)
	end)

	it("a spec of the skill: z-work says what the wait is and what to do, with the engine's own words", function()
		local skill = fs.readFile(`{TOP}/z-nile/skills/z-work/SKILL.md`)
		t.expect(has(skill, work.WAITING)).toBe(true)
		t.expect(has(skill, "does not clear by itself")).toBe(true)
	end)

	it("workerlive.capability names the worker's CLI from the environment, and never under dispatch", function()
		local grok = workerlive.capability({ ZN_CLI = "grok" }, LAYERS)
		t.expect(grok ~= nil).toBe(true)
		t.expect((grok :: work.Capability).cli).toBe("grok")
		t.expect(workerlive.capability({ ZN_CLI = "grok", ZN_DISPATCH = "1" }, LAYERS)).toBe(nil)
		t.expect(workerlive.capability({}, LAYERS)).toBe(nil) -- no CLI can be told: no filter
		t.expect(workerlive.capability({ ZN_CLI = "grok" }, nil)).toBe(nil) -- the file cannot be read: no filter
	end)

	it("work status names a unit no registered worker can deliver, and the kind of worker it waits for", function()
		local r = reviewable("R0100", "c0100")
		local workers = { { id = "grok-1@h", cli = "grok", can = models.canList(LAYERS, "grok") } }
		local lines = workcan.waitingFor({ r }, workers, function(a: string, l: string): string
			return models.waiting(LAYERS, a, l)
		end)
		t.expect(#lines).toBe(1)
		t.expect(lines[1]).toBe("R0100: waiting for a worker with code-review/normal (heavy: claude, kimi)")
		local both = { workers[1], { id = "claude-2@h", cli = "claude", can = models.canList(LAYERS, "claude") } }
		t.expect(#workcan.waitingFor({ r }, both, function(a: string, l: string): string
			return models.waiting(LAYERS, a, l)
		end)).toBe(0)
		t.expect(#workcan.waitingFor({ r }, {}, function(): string
			return ""
		end)).toBe(0) -- no worker registered: nothing is said to wait
	end)
end)
