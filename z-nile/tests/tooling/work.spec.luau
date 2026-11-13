--!strict
-- The worker's one next action, the dispatch trail a running step leaves, and Kimi's session wire.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sessionread = require("@znile/engine/sessionread")
local sessions = require("@znile/engine/sessions")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local WIRE =
	'{"type":"usage.record","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0}}'

local function layer(
	pos: number,
	issue: string,
	commits: number,
	onlyStart: boolean,
	finished: boolean
): work.LayerFact
	return {
		position = pos,
		issue = issue,
		name = `R0010/{pos}/{issue}`,
		commits = commits,
		onlyStart = onlyStart,
		finished = finished,
	}
end

local function raft(over: { [string]: any }): work.RaftFact
	local r: work.RaftFact = {
		id = "R0010",
		title = "t",
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010" },
		layers = {},
		holder = "Ada <ada@example>",
		since = "2026-11-12T00:00:00-08:00",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

local function decide(rafts: { work.RaftFact }, asked: string?, held: string?): work.Decision
	return work.decide({ asked = asked, held = held, rafts = rafts })
end

return t.spec("z-work's next action", function(it)
	it("takes the lowest claimable raft, and says why there is nothing", function()
		local low = raft({ id = "R0009" })
		local high = raft({ id = "R0020" })
		local d = decide({ high, low }, nil, nil)
		t.expect(d.raft).toBe("R0009")
		t.expect(d.action).toBe("ready")
		local blocked = raft({ id = "R0008", questions = true })
		local raw = raft({ id = "R0007", status = "new", designReady = false })
		local none = decide({ blocked, raw, raft({ id = "R0030", where = "active" }) }, nil, nil)
		t.expect(none.action).toBe("none")
		t.expect(string.find(none.why, "R0008 needs a human", 1, true) ~= nil).toBe(true)
		t.expect(string.find(none.why, "R0007 is new", 1, true) ~= nil).toBe(true)
		t.expect(string.find(none.why, "R0030 is held", 1, true) ~= nil).toBe(true)
		t.expect(string.find(work.say(none), "nothing to do - ", 1, true) ~= nil).toBe(true)
	end)

	it("builds a start-only layer, then finishes, and does not land early", function()
		local open = raft({
			where = "active",
			status = "active",
			layers = { layer(1, "c0010", 1, true, false) },
		})
		local built = decide({ open }, "R0010", nil)
		t.expect(built.action).toBe("implement")
		t.expect(string.find(built.why, "Do not run ./zn finish yet", 1, true) ~= nil).toBe(true)
		open.layers = { layer(1, "c0010", 3, false, false) }
		t.expect(decide({ open }, "R0010", nil).action).toBe("finish")
		open.layers = { layer(1, "c0010", 1, false, true) }
		t.expect(decide({ open }, "R0010", nil).action).toBe("restack")
		open.stacked = true
		t.expect(decide({ open }, "R0010", nil).action).toBe("review")
		open.codeReview = "open"
		local answering = decide({ open }, "R0010", nil)
		t.expect(answering.action).toBe("review")
		t.expect(string.find(answering.why, "Do not guess", 1, true) ~= nil).toBe(true)
		open.codeReview = "resolved"
		t.expect(decide({ open }, "R0010", nil).action).toBe("trace")
		open.trace = true
		t.expect(decide({ open }, "R0010", nil).action).toBe("final-review")
		open.finalReview = "approved"
		open.traceOk = false
		t.expect(decide({ open }, "R0010", nil).action).toBe("trace")
		open.traceOk = true
		t.expect(decide({ open }, "R0010", nil).action).toBe("done")
	end)

	it("stays with the raft it holds, releases on questions, and ends when that raft is over", function()
		local held =
			raft({ where = "active", status = "active", layers = { layer(1, "c0010", 1, true, false) } })
		local other = raft({ id = "R0001" })
		local stayed = decide({ other, held }, nil, "R0010")
		t.expect(stayed.raft).toBe("R0010")
		t.expect(stayed.action).toBe("implement")
		held.questions = true
		t.expect(decide({ held }, "R0010", nil).action).toBe("release")
		held.where = "backlog"
		held.status = "prepared"
		local released = decide({ held, other }, "R0010", nil)
		t.expect(released.action).toBe("end")
		t.expect(string.find(released.why, "fresh session", 1, true) ~= nil).toBe(true)
		local landed = raft({ where = "done", status = "done" })
		local again = decide({ landed, other }, nil, "R0010")
		t.expect(again.action).toBe("end")
		t.expect(again.raft).toBe("R0010")
		t.expect(decide({ other }, "R9999", nil).action).toBe("none")
		local lines = work.status({
			held,
			raft({ id = "R0002", where = "active", status = "active", layers = {}, holder = "", since = "" }),
		})
		t.expect(lines[1]).toBe("R0002 claimed holder unknown since unknown")
		t.expect(string.find(work.say(stayed), "R0010 layer 1 c0010: implement c0010 - ", 1, true) ~= nil)
			.toBe(true)
	end)

	it("prints the last lines of a running step's trail", function()
		local body = ""
		for i = 1, 10 do
			body ..= `line {i}\n`
		end
		local report = dispatch.trailReport(body, 12, true)
		t.expect(report[1]).toBe("trail: 10 lines, last 8")
		t.expect(report[2]).toBe("  line 3")
		t.expect(report[9]).toBe("  line 10")
		t.expect(report[10]).toBe("tokens: 12 running")
		local quiet = dispatch.trailReport("", 0, false)
		t.expect(quiet[1]).toBe("trail: none")
		t.expect(quiet[2]).toBe("tokens: 0")
	end)

	it("counts a Kimi wire the way the adapter does, and leaves the other CLIs unmeasured", function()
		t.expect((sessions.kimi(WIRE) :: sessions.Part).tokens).toBe(2361)
		t.expect(sessions.kimi("not a wire") == nil).toBe(true)
		local root = ".cache/work-kimi"
		pcall(function()
			fs.removeDir(root)
		end)
		fs.writeDir(`{root}/sessions/ws/abc/agents/main`)
		fs.writeFile(`{root}/sessions/ws/abc/agents/main/wire.jsonl`, WIRE .. "\n")
		local oldHome = process.env.HOME
		local oldKimi = process.env.PICKMAN_KIMI_SESSIONS
		process.env.HOME = `{process.cwd}/{root}/home`
		process.env.PICKMAN_KIMI_SESSIONS = `{process.cwd}/{root}/sessions`
		fs.writeDir(process.env.HOME :: string)
		local reading =
			sessionread.span("anywhere", "2020-01-01T00:00:00.000Z", 0, "2099-01-01T00:00:00.000Z", os.time())
		process.env.HOME = oldHome
		process.env.PICKMAN_KIMI_SESSIONS = oldKimi or ""
		t.expect(reading.tokens).toBe(2361)
		t.expect(string.find(reading.note, "kimi tokens=2361", 1, true) ~= nil).toBe(true)
		t.expect(string.find(reading.note, "claude unmeasured", 1, true) ~= nil).toBe(true)
	end)
end)
