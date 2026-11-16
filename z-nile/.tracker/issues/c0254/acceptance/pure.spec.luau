--!strict
-- c0254 AC1, AC3, AC4, AC5: the pure rules of workers on several hosts (xhost.luau) and the three places that read them: the
-- dispatcher's chain (a claim step before a worker's model, the `taken` exit), the supervisor (a lost race is not a failure),
-- and the loop (the next pick is asked at once). Nothing starts a process; the dispatcher's origin is a stub.
local dispatch = require("@znile/engine/dispatch")
local dispatcher = require("@znile/engine/dispatcher")
local heartbeat = require("@znile/engine/heartbeat")
local supervise = require("@znile/engine/supervise")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workloop = require("@znile/engine/workloop")
local xhost = require("@znile/engine/xhost")

local function seen(state: string, status: string, stamp: string): xhost.Seen
	return { state = state, status = status, stamp = stamp }
end

local BEFORE = seen("backlog", "new", "new-aaa-bbb-ccc")

return t.spec("c0254 workers on several hosts: the pure rules", function(it)
	it("AC1: a claim step that exits 0 is won", function()
		t.expect(
			xhost.claimOutcome(0, BEFORE, seen("backlog", "preparing", "preparing-x-y-z"), "preparing-x-y-z")
		)
			.toBe("won")
	end)

	it(
		"AC1: a failed claim is lost only when origin/main shows the item moved under another stamp",
		function()
			local after = seen("backlog", "preparing", "preparing-x-y-z")
			t.expect(xhost.claimOutcome(1, BEFORE, after, "")).toBe("lost")
			t.expect(xhost.claimOutcome(1, BEFORE, after, "preparing-other-one-two")).toBe("lost")
			t.expect(
				xhost.claimOutcome(
					1,
					seen("backlog", "prepared", "p"),
					seen("active", "active", "active-a-b-c"),
					""
				)
			).toBe("lost")
			t.expect(
				xhost.claimOutcome(
					1,
					seen("backlog", "prepared", "p"),
					seen("done", "done", "done-a-b-c"),
					""
				)
			)
				.toBe("lost")
		end
	)

	it(
		"AC1: a failed claim that moved nothing, that cannot be read, or whose stamp is this worker's is a failure",
		function()
			t.expect(xhost.claimOutcome(1, BEFORE, seen("backlog", "new", "new-aaa-bbb-ccc"), ""))
				.toBe("failed")
			t.expect(xhost.claimOutcome(1, BEFORE, nil, "")).toBe("failed")
			-- the push landed and the step failed afterwards: the claim is this worker's own
			t.expect(
				xhost.claimOutcome(
					1,
					BEFORE,
					seen("backlog", "preparing", "preparing-x-y-z"),
					"preparing-x-y-z"
				)
			).toBe("failed")
		end
	)

	it("AC1: the dispatcher asks origin/main after a failed claim step, and only for a claim step", function()
		local reads = 0
		local ctx = {
			origin = function(_id: string)
				reads += 1
				return {
					path = "p",
					state = "backlog",
					status = "preparing",
					front = { status = "preparing-x-y-z" },
				}
			end,
			memoryIn = function(_dir: string, _id: string)
				return ""
			end,
		} :: any
		local st = { worktree = "/x" } :: any
		t.expect(dispatcher.claimVerdict(ctx, st, "claim", "c0010", "backlog", "new", 1)).toBe("lost")
		t.expect(dispatcher.claimVerdict(ctx, st, "z-ready", "R0010", "backlog", "prepared", 1)).toBe("lost")
		t.expect(dispatcher.claimVerdict(ctx, st, "z-ready", "R0010", "backlog", "prepared", 0)).toBe("won")
		local before = reads
		t.expect(dispatcher.claimVerdict(ctx, st, "raft-plan", "c0010", "backlog", "new", 1)).toBe("failed")
		t.expect(reads).toBe(before)
		local own = {
			origin = ctx.origin,
			memoryIn = function(_dir: string, _id: string)
				return "preparing-x-y-z"
			end,
		} :: any
		t.expect(dispatcher.claimVerdict(own, st, "claim", "c0010", "backlog", "new", 1)).toBe("failed")
	end)

	it("AC1: a lost claim leaves no failed step behind in the run state", function()
		local st = {
			history = { { step = "z-design", outcome = "ok" }, { step = "claim", outcome = "failed" } },
			step = "claim",
			outcome = "failed",
			detail = "exit 1",
		} :: any
		dispatcher.dropLostAttempt(st)
		t.expect(#st.history).toBe(1)
		t.expect(st.history[1].step).toBe("z-design")
		t.expect(st.step).toBe(nil)
		t.expect(st.outcome).toBe(nil)
		t.expect(string.find(st.detail, "lost the claim", 1, true) ~= nil).toBe(true)
	end)

	it("AC1: a worker's issue is claimed by its own step before any model starts", function()
		local facts: dispatch.Facts = {
			folder = "",
			root = "",
			id = "c0010",
			kind = "issue",
			where = "backlog",
			status = "new",
			design = "draft",
			raft = "",
			ownClaim = false,
			worker = true,
			localRaft = "",
			pr = nil,
			questions = false,
			blocked = nil,
			openHuman = {},
			last = nil,
			uncovered = {},
			autoMerge = {},
			description = nil,
			layered = false,
			land = nil,
			blockRequest = nil,
		}
		local a = dispatch.next(facts)
		t.expect(a.kind).toBe("step")
		t.expect(a.step).toBe("claim")
		-- a plain dispatch (no --worker) goes to z-design as before
		facts.worker = false
		t.expect((dispatch.next(facts)).step).toBe("z-design")
		-- the claim step is a script that runs `status <id> preparing` in the issue's prep worktree
		t.expect(table.concat(dispatch.scriptArgv("claim", "c0010"), " ")).toBe("./zn status c0010 preparing")
		t.expect(dispatch.step("claim").where).toBe("prep")
		-- once claimed, the chain reaches z-design
		facts.worker, facts.status, facts.ownClaim = true, "preparing", true
		t.expect((dispatch.next(facts)).step).toBe("z-design")
		-- a claim step that ended ok with the issue still new stops the chain
		facts.status, facts.ownClaim, facts.last = "new", false, { step = "claim", outcome = "ok" }
		local stop = dispatch.next(facts)
		t.expect(stop.kind).toBe("stop")
		t.expect(stop.code).toBe(dispatch.EXIT.failure)
	end)

	it("AC1: the dispatcher and the supervisor share one exit code for a lost race", function()
		t.expect(dispatch.EXIT.taken).toBe(6)
		t.expect(supervise.EXIT.taken).toBe(dispatch.EXIT.taken)
		t.expect(supervise.afterDispatch("raft", 6, 0).kind).toBe("taken")
		t.expect(supervise.afterDispatch("draft", 6, 1).kind).toBe("taken")
		-- a failure is still retried once, then stops
		t.expect(supervise.afterDispatch("raft", 1, 0).kind).toBe("retry")
		t.expect(supervise.afterDispatch("raft", 1, 1).kind).toBe("stop")
	end)

	local function world(
		nexts: { string },
		codes: { [string]: number }
	): (workloop.World, { string }, { number })
		local calls: { string } = {}
		local sleeps: { number } = {}
		local n = 0
		local w: workloop.World = {
			next = function()
				n += 1
				local what = nexts[n]
				if what == nil then
					return "", "next: nothing to take: no claimable raft", 1
				end
				return what .. "\n", "", 0
			end,
			dispatch = function(args)
				table.insert(calls, table.concat(args, " "))
				return codes[args[#args - 1] or ""] or codes[string.match(args[2] or "", "%S+") or ""] or 0
			end,
			lock = function()
				return true
			end,
			unlock = function() end,
			now = function()
				return 1000
			end,
			sleep = function(s)
				table.insert(sleeps, s)
			end,
			stopped = function()
				return false
			end,
			state = function() end,
			say = function() end,
			held = "",
			cli = nil,
			noRun = false,
			idleSeconds = nil,
		}
		return w, calls, sleeps
	end

	it(
		"AC1: a lost race takes the next pick at once, is not a failure and is not counted as an item taken",
		function()
			local w, calls, sleeps = world({ "R0010 raft first", "R0020 raft second" }, { R0010 = 6 })
			local summary = workloop.run(w, { once = false, maxItems = 1 })
			t.expect(#calls).toBe(2)
			t.expect(string.find(calls[1] :: string, "R0010", 1, true) ~= nil).toBe(true)
			t.expect(string.find(calls[2] :: string, "R0020", 1, true) ~= nil).toBe(true)
			t.expect(#sleeps).toBe(0)
			t.expect(summary.moved[1]).toBe("R0020")
			t.expect((summary.lost :: { string })[1]).toBe("R0010")
			t.expect(#summary.blocked).toBe(0)
			t.expect(
				string.find(supervise.summary(summary), "claimed by another worker first: R0010", 1, true)
					~= nil
			).toBe(true)
		end
	)

	it("AC1: the same item lost twice in a row waits one idle period instead of spinning", function()
		local w, _calls, sleeps = world({ "R0010 raft a", "R0010 raft b", "R0020 raft c" }, { R0010 = 6 })
		workloop.run(w, { once = false, maxItems = 1 })
		t.expect(#sleeps).toBe(1)
		t.expect(sleeps[1]).toBe(supervise.IDLE_SECONDS)
	end)

	it("AC1: a run that lost nothing prints the summary it printed before", function()
		local text = supervise.summary({ moved = { "R0010" }, blocked = {}, stopped = "the stack is empty" })
		t.expect((string.find(text, "claimed by another", 1, true))).toBe(nil)
	end)

	it("AC3: every commit on a layer or prep branch is pushed, a first push sets the upstream", function()
		local base: xhost.PushFacts = {
			publishing = true,
			branch = "prep-hello",
			hasUpstream = false,
			originHas = false,
			behind = 0,
			claim = "held",
		}
		t.expect(xhost.pushDecision(base).action).toBe("push-new")
		base.hasUpstream = true
		base.originHas = true
		t.expect(xhost.pushDecision(base).action).toBe("push")
		base.branch, base.hasUpstream, base.originHas = "R0010/2/c0248", false, false
		t.expect(xhost.pushDecision(base).action).toBe("push-new")
		-- a checkout that never claimed it (a person's own session) pushes too
		base.claim = "unheld"
		t.expect(xhost.pushDecision(base).action).toBe("push-new")
	end)

	it("AC2, AC3: a worker whose claim was taken over or ended never pushes the branch", function()
		for _, claim in { "taken", "ended" } do
			local d = xhost.pushDecision({
				publishing = true,
				branch = "prep-hello",
				hasUpstream = true,
				originHas = true,
				behind = 0,
				claim = claim,
			})
			t.expect(d.action).toBe("refuse")
			t.expect(string.find(d.why, "not pushing prep-hello", 1, true) ~= nil).toBe(true)
		end
	end)

	it("AC2, AC3: nothing is pushed over commits origin has, or when they cannot be counted", function()
		local f: xhost.PushFacts = {
			publishing = true,
			branch = "prep-hello",
			hasUpstream = true,
			originHas = true,
			behind = 2,
			claim = "held",
		}
		t.expect(xhost.pushDecision(f).action).toBe("refuse")
		f.behind = nil
		t.expect(xhost.pushDecision(f).action).toBe("refuse")
		-- origin has no such branch: nothing to be behind
		f.originHas, f.behind, f.hasUpstream = false, 0, false
		t.expect(xhost.pushDecision(f).action).toBe("push-new")
	end)

	it("AC3: any other branch keeps today's rule: pushed only with an upstream, and never main", function()
		local f: xhost.PushFacts = {
			publishing = true,
			branch = "scratch",
			hasUpstream = false,
			originHas = false,
			behind = 0,
			claim = "taken",
		}
		t.expect(xhost.pushDecision(f).action).toBe("skip")
		f.hasUpstream = true
		t.expect(xhost.pushDecision(f).action).toBe("push")
		f.branch = "main"
		t.expect(xhost.pushDecision(f).action).toBe("skip")
		f.branch = nil
		t.expect(xhost.pushDecision(f).action).toBe("skip")
		f.branch, f.publishing = "prep-hello", false
		t.expect(xhost.pushDecision(f).action).toBe("skip")
	end)

	it("AC3: branch kinds, and the claim each is keyed by", function()
		t.expect(xhost.branchKind("R0010/1/c0248")).toBe("layer")
		t.expect(xhost.branchKind("prep-cross-host-workers")).toBe("prep")
		t.expect(xhost.branchKind("proto-c0254")).toBe("other")
		t.expect(xhost.branchKind(nil)).toBe("other")
		t.expect(xhost.raftOfLayer("R0010/1/c0248")).toBe("R0010")
		t.expect(xhost.raftOfLayer("prep-x")).toBe(nil)
	end)

	it("AC2: the claim states xhost reads are heartbeat.holds's", function()
		t.expect(heartbeat.holds("a", "a")).toBe("held")
		t.expect(heartbeat.holds("a", "b")).toBe("taken")
		t.expect(heartbeat.holds("a", nil)).toBe("ended")
		t.expect(heartbeat.holds("", "b")).toBe("unheld")
	end)

	it("AC4: a worker's identity is its host, CLI and model", function()
		local w = xhost.identity({ ZN_CLI = "grok", ZN_MODEL = "grok-4.7" }, "M5-Max.local\n")
		t.expect(w.host).toBe("m5-max.local")
		t.expect(w.cli).toBe("grok")
		t.expect(w.model).toBe("grok-4.7")
	end)

	it("AC4: a person's session has its CLI detected, and what nothing says is unknown", function()
		t.expect(xhost.identity({ CLAUDECODE = "1" }, "h").cli).toBe("claude")
		t.expect(xhost.identity({ KIMI_SESSION_ID = "s" }, "h").cli).toBe("kimi")
		-- the dispatcher's own word wins over a marker
		t.expect(xhost.identity({ ZN_CLI = "agent", CLAUDECODE = "1" }, "h").cli).toBe("agent")
		local none = xhost.identity({}, nil)
		t.expect(none.cli).toBe("unknown")
		t.expect(none.model).toBe("")
		t.expect(none.host).toBe("host")
		-- a value that is not a name is not recorded
		t.expect(xhost.identity({ ZN_CLI = "a b;c", ZN_MODEL = "x y" }, "h").cli).toBe("unknown")
		t.expect(xhost.identity({ ZN_MODEL = "x y" }, "h").model).toBe("")
	end)

	it(
		"AC5: the Worker trailer round-trips and reads the newest holder of the item's current stamp",
		function()
			local a = xhost.trailer(
				"c0010",
				"preparing-a-b-c",
				{ host = "h1", cli = "claude", model = "claude-opus-5-5" }
			)
			local b = xhost.trailer("c0010", "preparing-d-e-f", { host = "h2", cli = "grok", model = "" })
			t.expect(a).toBe("Worker: c0010 preparing-a-b-c host=h1 cli=claude model=claude-opus-5-5")
			local parsed = xhost.parseTrailer(b)
			t.expect(parsed ~= nil and parsed.model or "x").toBe("")
			t.expect(xhost.parseTrailer("Worker: nonsense")).toBe(nil)
			-- newest first: b (the takeover) is the holder of the current stamp; a's stamp is gone
			local holders = xhost.holders({ b, a }, { c0010 = "preparing-d-e-f" })
			t.expect(holders.c0010.host).toBe("h2")
			t.expect(xhost.holderText(holders.c0010)).toBe("h2 (grok)")
			-- two trailers for one stamp (a claim restated): the newest, listed first, is the holder
			local newer =
				xhost.trailer("c0010", "preparing-d-e-f", { host = "h3", cli = "agent", model = "" })
			t.expect(xhost.holders({ newer, b }, { c0010 = "preparing-d-e-f" }).c0010.host).toBe("h3")
			-- a stamp nobody's trailer names has no holder
			t.expect(xhost.holders({ b, a }, { c0010 = "preparing-z-z-z" }).c0010).toBe(nil)
			t.expect(xhost.holderText(xhost.holders({ a }, { c0010 = "preparing-a-b-c" }).c0010))
				.toBe("h1 (claude, claude-opus-5-5)")
		end
	)

	it(
		"AC5: ./zn work status names the worker that holds each raft, and says nothing extra when none is known",
		function()
			local function raft(worker: string?): work.RaftFact
				return {
					id = "R0010",
					title = "t",
					where = "active",
					status = "active",
					designReady = true,
					depsMet = true,
					blocked = nil,
					issues = {},
					layers = {},
					holder = "Ann <ann@example.invalid>",
					worker = worker,
					since = "2026-11-16T10:00:00Z",
					stacked = false,
					codeReview = "none",
					finalReview = "none",
					codeModel = nil,
					trace = false,
					traceOk = false,
					block = "",
					root = "",
				}
			end
			local with = work.status({ raft("h2 (grok, grok-4.7)") })[1] :: string
			t.expect(
				string.find(
					with,
					"holder Ann <ann@example.invalid> worker h2 (grok, grok-4.7) since",
					1,
					true
				) ~= nil
			).toBe(true)
			local without = work.status({ raft(nil) })[1] :: string
			t.expect((string.find(without, "worker", 1, true))).toBe(nil)
		end
	)
end)
