--!strict
-- The worker's one next action, the dispatch trail a running step leaves, and Kimi's session wire.
local adapters = require("@znile/engine/adapters")
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
		root = "",
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
		t.expect(string.find(none.why, "R0008: needs a human", 1, true) ~= nil).toBe(true)
		t.expect(string.find(none.why, "R0007: is new", 1, true) ~= nil).toBe(true)
		t.expect(string.find(none.why, "R0030: is held", 1, true) ~= nil).toBe(true)
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
		local tracing = decide({ open }, "R0010", nil)
		t.expect(tracing.action).toBe("trace")
		local step1 = string.find(tracing.why, "Phase 5 step 1", 1, true)
		local skeleton = string.find(tracing.why, "skeleton", 1, true)
		t.expect(step1 ~= nil and skeleton ~= nil and (step1 :: number) < (skeleton :: number)).toBe(true)
		open.trace = true
		t.expect(decide({ open }, "R0010", nil).action).toBe("final-review")
		open.finalReview = "approved"
		open.traceOk = false
		t.expect(decide({ open }, "R0010", nil).action).toBe("trace")
		open.traceOk = true
		t.expect(decide({ open }, "R0010", nil).action).toBe("done")
	end)

	it("does not resume a held raft unless it was named, and a named raft ends", function()
		local held =
			raft({ where = "active", status = "active", layers = { layer(1, "c0010", 1, true, false) } })
		local other = raft({ id = "R0001" })
		local stayed = decide({ other, held }, nil, "R0010")
		t.expect(stayed.raft).toBe("R0001")
		t.expect(stayed.action).toBe("ready")
		local named = decide({ other, held }, "R0010", nil)
		t.expect(named.raft).toBe("R0010")
		t.expect(named.action).toBe("implement")
		held.questions = true
		t.expect(decide({ held }, "R0010", nil).action).toBe("release")
		held.where = "backlog"
		held.status = "prepared"
		local released = decide({ held, other }, "R0010", nil)
		t.expect(released.action).toBe("end")
		t.expect(string.find(released.why, "fresh session", 1, true) ~= nil).toBe(true)
		local landed = raft({ where = "done", status = "done" })
		local again = decide({ landed, other }, nil, "R0010")
		t.expect(again.action).toBe("ready")
		t.expect(again.raft).toBe("R0001")
		local namedEnd = decide({ landed, other }, "R0010", nil)
		t.expect(namedEnd.action).toBe("end")
		t.expect(namedEnd.raft).toBe("R0010")
		t.expect(decide({ other }, "R9999", nil).action).toBe("none")
		local lines = work.status({
			held,
			raft({ id = "R0002", where = "active", status = "active", layers = {}, holder = "", since = "" }),
		})
		t.expect(lines[1]).toBe("R0002 claimed holder unknown since unknown")
		t.expect(string.find(work.say(named), "R0010 layer 1 c0010: implement c0010 - ", 1, true) ~= nil)
			.toBe(true)
	end)

	it("lands one raft, skips an unapproved one, lands the next, and stops", function()
		local reason =
			"c0002 has no approval: run ./zn approve c0002, then ./zn approve c0002 --publish, from the worktree that holds the design."
		local first = raft({ id = "R0001", block = "" })
		local skipped = raft({ id = "R0002", block = reason })
		local third = raft({ id = "R0003", block = "" })
		local function step(rafts: { work.RaftFact }): string
			local input: work.Input = { rafts = rafts, released = 0 }
			return work.report(input, work.decide(input))
		end
		local claim = step({ first, skipped, third })
		t.expect(string.find(claim, "R0001: ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(claim, reason, 1, true) ~= nil).toBe(true)
		t.expect(string.find(claim, "R0003:", 1, true) == nil).toBe(true)
		first.where = "done"
		first.status = "done"
		first.block = nil
		local nextClaim = step({ first, skipped, third })
		t.expect(string.find(nextClaim, "R0003: ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(nextClaim, reason, 1, true) ~= nil).toBe(true)
		third.where = "done"
		third.status = "done"
		third.block = nil
		local done = step({ first, skipped, third })
		t.expect(string.find(done, "nothing to do - ", 1, true) ~= nil).toBe(true)
		t.expect(string.find(done, "R0002: " .. reason, 1, true) ~= nil).toBe(true)
	end)

	it("stops after two blocked releases, and a named raft still ends on its own", function()
		local open = raft({ id = "R0004", block = "" })
		local input: work.Input = { rafts = { open }, released = work.BLOCKED_IN_A_ROW }
		local stopped = work.report(input, work.decide(input))
		t.expect(stopped).toBe(`nothing to do - {work.blockedWhy()}`)
		local landed = raft({ id = "R0001", where = "done", status = "done" })
		local another = raft({ id = "R0009", block = "" })
		local named = work.decide({
			asked = "R0001",
			released = work.BLOCKED_IN_A_ROW,
			rafts = { landed, another },
		})
		t.expect(named.action).toBe("end")
		t.expect(named.raft).toBe("R0001")
		local held = raft({
			id = "R0061",
			where = "active",
			status = "active",
			holder = "Ada <ada@example>",
			layers = { layer(1, "c0010", 1, true, false) },
		})
		local offer = work.decide({
			author = "Ada <ada@example>",
			rafts = { held, another },
		})
		t.expect(offer.raft).toBe("R0009")
		t.expect(string.find(offer.why, "you hold R0061: name one to resume it", 1, true) ~= nil).toBe(true)
	end)

	it("offers this project's raft from its folder, and any project from the root", function()
		local nile = raft({ id = "R0030", root = "z-nile/.tracker", block = "" })
		local pick = raft({ id = "R0094", root = "pickman/.tracker", block = "" })
		local root = work.decide({ rafts = { pick, nile } })
		t.expect(root.raft).toBe("R0030")
		t.expect(work.decide({ scope = "", rafts = { pick, nile } }).raft).toBe("R0030")
		t.expect(work.decide({ scope = "pickman/.tracker", rafts = { pick, nile } }).raft).toBe("R0094")
		t.expect(work.decide({ scope = "z-nile/.tracker", rafts = { pick, nile } }).raft).toBe("R0030")
		local named = work.decide({ asked = "R0030", scope = "pickman/.tracker", rafts = { pick, nile } })
		t.expect(named.raft).toBe("R0030")
		t.expect(named.action).toBe("ready")
		local held = raft({
			id = "R0061",
			root = "z-nile/.tracker",
			where = "active",
			status = "active",
			holder = "Ada <ada@example>",
			block = "is active",
		})
		local blocked = raft({
			id = "R0095",
			root = "pickman/.tracker",
			block = "f0148 depends on f0147, which is backlog on origin/main",
		})
		local input: work.Input = {
			author = "Ada <ada@example>",
			scope = "pickman/.tracker",
			rafts = { nile, held, blocked },
		}
		local quiet = work.report(input, work.decide(input))
		t.expect(string.find(quiet, "nothing to do - no claimable raft in pickman", 1, true) ~= nil)
			.toBe(true)
		t.expect(string.find(quiet, "R0095: f0148 depends on f0147", 1, true) ~= nil).toBe(true)
		t.expect(string.find(quiet, "R0030", 1, true) == nil).toBe(true)
		t.expect(string.find(quiet, "you hold", 1, true) == nil).toBe(true)
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

	it("counts a Kimi wire of this checkout only, and a Claude message id once", function()
		t.expect((sessions.kimi(WIRE) :: sessions.Part).tokens).toBe(2361)
		t.expect(sessions.kimi("not a wire") == nil).toBe(true)
		local twice =
			'{"type":"assistant","timestamp":"2026-11-03T23:33:14.633Z","message":{"id":"msg_1","model":"claude-opus-4","usage":{"input_tokens":2,"cache_creation_input_tokens":10,"output_tokens":4}}}\n'
		local claude = sessions.claude(twice .. twice, "2026-11-03T23:33:00.000Z", "2026-11-03T23:34:00.000Z")
		t.expect((claude :: sessions.Part).tokens).toBe(16)
		local root = ".cache/work-kimi"
		pcall(function()
			fs.removeDir(root)
		end)
		fs.writeDir(`{root}/sessions/ws/abc/agents/main`)
		fs.writeDir(`{root}/sessions/other/xyz/agents/main`)
		fs.writeFile(`{root}/sessions/ws/abc/state.json`, '{"cwd":"anywhere"}\n')
		fs.writeFile(`{root}/sessions/other/xyz/state.json`, '{"cwd":"/not-this"}\n')
		fs.writeFile(`{root}/sessions/ws/abc/agents/main/wire.jsonl`, WIRE .. "\n")
		fs.writeFile(
			`{root}/sessions/other/xyz/agents/main/wire.jsonl`,
			'{"type":"usage.record","usage":{"inputOther":99999,"output":1,"inputCacheCreation":0}}\n'
		)
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

	it(
		"d0328: measures a Claude session under the real folder of a .worktree cwd that ends in a slash",
		function()
			local root = ".cache/work-claude-cwd"
			pcall(function()
				fs.removeDir(root)
			end)
			-- Claude Code's folder for /a/b/.worktree/x: no trailing "-", and "-" for the dot too
			local folder = `{root}/home/.claude/projects/-a-b--worktree-x`
			fs.writeDir(folder)
			local line1 =
				'{"type":"assistant","timestamp":"2026-11-03T23:33:00.000Z","message":{"id":"msg_1","model":"claude-opus-4","usage":{"input_tokens":2,"cache_creation_input_tokens":10,"output_tokens":4}}}\n'
			local line2 =
				'{"type":"assistant","timestamp":"2026-11-03T23:33:10.000Z","message":{"id":"msg_2","model":"claude-opus-4","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"output_tokens":3}}}\n'
			fs.writeFile(`{folder}/s1.jsonl`, line1 .. line2)
			local oldHome = process.env.HOME
			process.env.HOME = `{process.cwd}/{root}/home`
			local reading = sessionread.span(
				"/a/b/.worktree/x/",
				"2020-01-01T00:00:00.000Z",
				0,
				"2099-01-01T00:00:00.000Z",
				os.time()
			)
			process.env.HOME = oldHome
			t.expect(reading.model).toBe("claude-opus-4")
			t.expect(reading.tokens).toBe(20)
			t.expect(reading.ai).toBe(10)
		end
	)

	it("agrees with dispatch.next on the shared facts, and not on an active raft's action", function()
		local function facts(over: { [string]: any }): dispatch.Facts
			local f: { [string]: any } = {
				id = "R0010",
				folder = "z-nile/.tracker/rafts/R0010",
				root = "z-nile/.tracker",
				kind = "raft",
				where = "backlog",
				status = "prepared",
				design = "ready",
				raft = "",
				ownClaim = false,
				localRaft = "",
				pr = nil,
				questions = false,
				openHuman = {},
				last = nil,
				uncovered = {},
				autoMerge = { "prep", "raft" },
				description = nil,
			}
			for k, v in over do
				f[k] = v
			end
			return f :: any
		end
		local function stepOf(f: dispatch.Facts): string
			local a = dispatch.next(f)
			return if a.kind == "step" then a.step :: string else `stop {a.code}`
		end
		local prepared = raft({})
		t.expect(decide({ prepared }, nil, nil).action).toBe("ready")
		t.expect(stepOf(facts({}))).toBe("z-ready")
		local doneRaft = raft({ where = "done", status = "done" })
		t.expect(decide({ doneRaft }, "R0010", nil).action).toBe("end")
		t.expect(stepOf(facts({ where = "done", status = "done" }))).toBe("stop 0")
		local asked = raft({ where = "active", status = "active", questions = true })
		t.expect(decide({ asked }, "R0010", nil).action).toBe("release")
		t.expect(stepOf(facts({ where = "active", status = "active", questions = true }))).toBe("stop 3")
		local building = raft({
			where = "active",
			status = "active",
			layers = { layer(1, "c0010", 1, true, false) },
		})
		local action = decide({ building }, "R0010", nil).action
		local pipe = stepOf(facts({ where = "active", status = "active" }))
		t.expect(action).toBe("implement")
		t.expect(pipe).toBe("z-run")
		t.expect(action ~= pipe).toBe(true)
	end)

	it("names a tool call in the trail instead of the stream JSON", function()
		local acc = adapters.newAcc()
		adapters.get("claude-cli").feed(
			acc,
			'{"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","name":"Bash","input":{"command":"git status"}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":10,"output_tokens":4}}}'
		)
		t.expect(acc.note).toBe("Bash git status")
		t.expect(string.find(acc.note, "{", 1, true) == nil).toBe(true)
		local report = dispatch.trailReport(acc.note .. "\n", 16, true)
		t.expect(report[2]).toBe("  Bash git status")
		adapters.get("claude-cli").feed(
			acc,
			'{"type":"assistant","message":{"id":"msg_1","content":[{"type":"tool_use","name":"Bash","input":{"command":"git diff"}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":10,"output_tokens":4}}}'
		)
		t.expect(acc.live).toBe(16)
	end)

	it("keeps the 'you hold' note on an unnamed resume or landing of a held raft", function()
		local author = "Ada <ada@example>"
		local function held(id: string, layers: { work.LayerFact }): work.RaftFact
			return raft({ id = id, where = "active", status = "active", holder = author, layers = layers })
		end
		local function pick(rafts: { work.RaftFact }): work.Decision
			return work.decide({ author = author, session = "s1", carriers = {}, rafts = rafts })
		end
		local building = held("R0071", { layer(1, "c0010", 1, true, false) })
		local landing = held("R0072", { layer(1, "c0010", 3, false, true) })
		local resumed = pick({ building, landing })
		local prefix = "Resuming R0071: you hold it and no live session carries it. "
		t.expect(resumed.raft).toBe("R0071")
		t.expect(string.sub(resumed.why, 1, #prefix)).toBe(prefix)
		t.expect(string.find(resumed.why, "you hold R0072: name one to resume it. ", 1, true) ~= nil)
			.toBe(true)
		local alone = pick({ building })
		t.expect(alone.raft).toBe("R0071")
		t.expect(string.sub(alone.why, 1, #prefix)).toBe(prefix)
		t.expect(string.find(alone.why, "you hold", #prefix, true) == nil).toBe(true)
		local ready = held("R0073", { layer(1, "c0010", 3, false, true) })
		ready.codeReview = "resolved"
		ready.finalReview = "approved"
		ready.stacked = true
		ready.trace = true
		ready.traceOk = true
		local toLand = pick({ ready, held("R0074", { layer(1, "c0010", 1, true, false) }) })
		local note = "you hold R0074: name one to resume it. "
		t.expect(toLand.action).toBe("done")
		t.expect(string.sub(toLand.why, 1, #note)).toBe(note)
	end)

	it("resumes a held raft built on an unlanded raft only after every pick with nothing unmet", function()
		local author = "Ada <ada@example>"
		local function pick(rafts: { work.RaftFact }): work.Decision
			return work.decide({ author = author, session = "s1", carriers = {}, rafts = rafts })
		end
		local function onBase(landed: boolean): work.RaftFact
			return raft({
				id = "R0030",
				where = "active",
				status = "active",
				holder = author,
				layers = { layer(1, "c0010", 1, true, false) },
				on = "R0005",
				onLanded = landed,
			})
		end
		local fresh = raft({ id = "R0040" })
		t.expect(work.forRaft(fresh).action).toBe("ready")
		-- the tier wins: a raft ready accepts comes before the held raft whose base has not landed
		local first = pick({ onBase(false), fresh })
		t.expect(first.raft).toBe("R0040")
		t.expect(first.action).toBe("ready")
		-- with nothing else to do it is resumed
		local alone = pick({ onBase(false) })
		t.expect(alone.raft).toBe("R0030")
		t.expect(string.sub(alone.why, 1, 15)).toBe("Resuming R0030:")
		-- once the base has landed nothing is unmet, and the held raft comes first again
		local landed = pick({ onBase(true), fresh })
		t.expect(landed.raft).toBe("R0030")
	end)

	it("names Claude Code's project folders for a checkout, strict spelling first", function()
		local dirs = sessionread.claudeDirs("/a/b/.worktree/x")
		local function tail(path: string): string
			return string.match(path, "/%.claude/projects/(.*)$") :: string
		end
		t.expect(#dirs).toBe(2)
		t.expect(tail(dirs[1])).toBe("-a-b--worktree-x")
		t.expect(tail(dirs[2])).toBe("-a-b-.worktree-x")
		local plain = sessionread.claudeDirs("/a/b/x")
		t.expect(#plain).toBe(1)
		t.expect(tail(plain[1])).toBe("-a-b-x")
	end)

	it("pins the z-work skill's count of releases", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local text = fs.readFile(`{top}/z-nile/skills/z-work/SKILL.md`)
		t.expect(
			string.find(
				text,
				"A `draft` you give back (`./zn status <id> new`) and a `fix` that changed nothing each add one to that count",
				1,
				true
			) ~= nil
		).toBe(true)
	end)
end)
