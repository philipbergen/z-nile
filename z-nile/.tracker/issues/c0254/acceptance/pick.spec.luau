--!strict
-- c0254 AC1, AC2, AC3, AC5, AC7: the race window before and after a claim, ownership by stamp, the text a lost worker is told, the
-- exit codes of a push, and who holds what for a rafting claim. Pure: the dispatcher's origin is a stub, the loop's world a fake,
-- and the one file written is a claim memory under .cache/c0254-pick.
local dispatch = require("@znile/engine/dispatch")
local dispatcher = require("@znile/engine/dispatcher")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local supervise = require("@znile/engine/supervise")
local t = require("@tests/lib/t")
local workloop = require("@znile/engine/workloop")
local xhost = require("@znile/engine/xhost")

local BASE = (fixture.physical(".") :: string) .. "/.cache/c0254-pick"

local function seen(state: string, status: string, stamp: string): xhost.Seen
	return { state = state, status = status, stamp = stamp }
end

local function facts(over: { [string]: any }): dispatch.Facts
	local f: any = {
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
	for k, v in over do
		f[k] = v
	end
	return f :: dispatch.Facts
end

return t.spec("c0254 the race window, ownership by stamp and the push exits", function(it)
	it("AC1: a draft pick is still ours only while the issue is new or carries our own stamp", function()
		t.expect(xhost.pickHeld("draft", seen("backlog", "new", "new-a-b-c"), "", nil)).toBe("ok")
		t.expect(xhost.pickHeld("draft", seen("backlog", "preparing", "preparing-x-y-z"), "", nil))
			.toBe("taken")
		t.expect(
			xhost.pickHeld("draft", seen("backlog", "preparing", "preparing-x-y-z"), "preparing-x-y-z", nil)
		)
			.toBe("ok")
		t.expect(xhost.pickHeld("draft", seen("backlog", "prepared", "prepared-a-b-c"), "", nil))
			.toBe("taken")
		t.expect(xhost.pickHeld("draft", nil, "", nil)).toBe("taken")
	end)

	it(
		"AC1: a raft pick is still ours only while the raft waits prepared in the backlog or carries our own stamp",
		function()
			t.expect(xhost.pickHeld("raft", seen("backlog", "prepared", "prepared-a-b-c"), "", nil))
				.toBe("ok")
			t.expect(xhost.pickHeld("raft", seen("active", "active", "active-x-y-z"), "", nil)).toBe("taken")
			t.expect(xhost.pickHeld("raft", seen("active", "active", "active-x-y-z"), "active-x-y-z", nil))
				.toBe("ok")
			t.expect(xhost.pickHeld("raft", seen("done", "done", "done-a-b-c"), "", nil)).toBe("taken")
		end
	)

	it("AC1: a rafting pick is taken when a preparing raft that is not ours lists the issue", function()
		local issue = seen("backlog", "prepared", "prepared-a-b-c")
		t.expect(xhost.pickHeld("rafting", issue, "", nil)).toBe("ok")
		t.expect(xhost.pickHeld("rafting", issue, "", { id = "R0200", stamp = "preparing-x-y-z" }))
			.toBe("taken")
		t.expect(
			xhost.pickHeld("rafting", issue, "preparing-x-y-z", { id = "R0200", stamp = "preparing-x-y-z" })
		)
			.toBe("ok")
		t.expect(xhost.pickHeld("rafting", seen("backlog", "preparing", "preparing-x-y-z"), "", nil))
			.toBe("taken")
	end)

	it(
		"AC1: a lost pick is left to the takeover's lease, and a claim already ours stays ours only by its stamp",
		function()
			t.expect(xhost.pickHeld("lost", seen("active", "active", "active-x-y-z"), "", nil)).toBe("ok")
			t.expect(xhost.stillMine(seen("active", "active", "active-x-y-z"), "active-x-y-z")).toBe(true)
			t.expect(xhost.stillMine(seen("active", "active", "active-other-one-two"), "active-x-y-z"))
				.toBe(false)
			-- our own steps took the item on to prepared or done: not a takeover
			t.expect(xhost.stillMine(seen("backlog", "prepared", "prepared-a-b-c"), "preparing-x-y-z"))
				.toBe(true)
			t.expect(xhost.stillMine(nil, "preparing-x-y-z")).toBe(false)
		end
	)

	it(
		"AC1: a worker's draft or raft that another worker holds ends the run with the taken exit before any step",
		function()
			local draft = dispatch.next(facts({
				status = "preparing",
				pick = "draft",
				owned = false,
				taken = "c0010 is no longer the draft it was picked as",
			}))
			t.expect(draft.kind).toBe("stop")
			t.expect(draft.code).toBe(dispatch.EXIT.taken)
			local raft = dispatch.next(facts({
				id = "R0010",
				kind = "raft",
				where = "active",
				status = "active",
				pick = "raft",
				owned = false,
			}))
			t.expect(raft.kind).toBe("stop")
			t.expect(raft.code).toBe(dispatch.EXIT.taken)
			-- an issue preparing under a claim that is not ours, whatever the run state's history says
			local byHistory =
				dispatch.next(facts({ status = "preparing", pick = "draft", ownClaim = true, owned = false }))
			t.expect(byHistory.code).toBe(dispatch.EXIT.taken)
		end
	)

	it(
		"AC1: a pick another worker finished meanwhile is taken, whatever step the facts would otherwise ask for",
		function()
			local done = dispatch.next(facts({
				status = "prepared",
				design = "ready",
				pick = "draft",
				taken = "c0010 is no longer the draft it was picked as",
			}))
			t.expect(done.kind).toBe("stop")
			t.expect(done.code).toBe(dispatch.EXIT.taken)
			-- the same facts for a plain dispatch go on to the rafting step
			t.expect(
				dispatch.next(facts({ worker = false, status = "prepared", design = "ready", taken = "" })).step
			)
				.toBe("raft-plan")
		end
	)

	it("AC1: a plain dispatch of the same facts behaves as before", function()
		t.expect(dispatch.next(facts({ worker = false, status = "preparing", ownClaim = true })).step)
			.toBe("z-design")
		t.expect(dispatch.next(facts({ worker = false, status = "preparing", ownClaim = false })).code)
			.toBe(dispatch.EXIT.failure)
		t.expect(
			dispatch.next(
				facts({ worker = false, id = "R0010", kind = "raft", where = "active", status = "active" })
			).step
		).toBe("z-run")
		t.expect(dispatch.next(facts({ worker = false, status = "new" })).step).toBe("z-design")
	end)

	it(
		"AC1: a lost pick is taken over by the claim step (an issue) or a stop then a ready (a raft); an owned raft runs",
		function()
			local lostIssue = dispatch.next(facts({ status = "preparing", pick = "lost", owned = false }))
			t.expect(lostIssue.step).toBe("claim")
			local lostRaft = dispatch.next(facts({
				id = "R0010",
				kind = "raft",
				where = "active",
				status = "active",
				pick = "lost",
				owned = false,
			}))
			t.expect(lostRaft.step).toBe("z-stop")
			local readied = dispatch.next(
				facts({ id = "R0010", kind = "raft", where = "backlog", status = "prepared", pick = "lost" })
			)
			t.expect(readied.step).toBe("z-ready")
			local mine = dispatch.next(facts({
				id = "R0010",
				kind = "raft",
				where = "active",
				status = "active",
				pick = "raft",
				owned = true,
			}))
			t.expect(mine.step).toBe("z-run")
		end
	)

	local function ctxWith(opts: {
		stamp: string?,
		state: string?,
		token: string?,
		memory: string?,
		rafted: xhost.RaftedBy?,
	}): any
		return {
			origin = function(_id: string): any
				if opts.stamp == nil then
					return nil
				end
				return {
					path = "p",
					state = opts.state or "backlog",
					status = "x",
					front = { status = opts.stamp },
				}
			end,
			memoryIn = function(_dir: string, _id: string)
				return opts.memory or ""
			end,
			claimAttempt = function(_id: string, _stamp: string)
				return opts.token
			end,
			raftedBy = function(_id: string)
				return opts.rafted
			end,
		}
	end

	it(
		"AC1: a claim whose commit carries this attempt's token is ours even when no memory says so",
		function()
			local st = { worktree = "/x" } :: any
			local c = ctxWith({ stamp = "active-x-y-z", state = "active", token = "tok1" })
			t.expect(dispatcher.claimVerdict(c, st, "z-ready", "R0010", "backlog", "prepared", 1, "tok1"))
				.toBe("ours")
			-- another attempt's token, and no token at all, are another worker's claim
			local other = ctxWith({ stamp = "active-x-y-z", state = "active", token = "tok2" })
			t.expect(dispatcher.claimVerdict(other, st, "z-ready", "R0010", "backlog", "prepared", 1, "tok1"))
				.toBe("lost")
			local bare = ctxWith({ stamp = "active-x-y-z", state = "active" })
			t.expect(dispatcher.claimVerdict(bare, st, "z-ready", "R0010", "backlog", "prepared", 1, "tok1"))
				.toBe("lost")
		end
	)

	it(
		"AC1: a rafting step is lost only when a preparing raft that is not this run's lists the issue",
		function()
			local st = { worktree = "/x" } :: any
			local foreign =
				ctxWith({ stamp = "prepared-a-b-c", rafted = { id = "R0200", stamp = "preparing-x-y-z" } })
			t.expect(
				dispatcher.claimVerdict(foreign, st, "raft-plan", "c0010", "backlog", "prepared", 1, "t")
			)
				.toBe("lost")
			local none = ctxWith({ stamp = "prepared-a-b-c" })
			t.expect(dispatcher.claimVerdict(none, st, "raft-plan", "c0010", "backlog", "prepared", 1, "t"))
				.toBe("failed")
			t.expect(dispatcher.claimVerdict(none, st, "raft-plan", "c0010", "backlog", "prepared", 0, "t"))
				.toBe("won")
			local ours = { worktree = "/x", claim = { id = "R0200", stamp = "preparing-x-y-z" } } :: any
			t.expect(
				dispatcher.claimVerdict(foreign, ours, "raft-plan", "c0010", "backlog", "prepared", 1, "t")
			)
				.toBe("failed")
		end
	)

	it(
		"AC1: a claim that landed is recorded in the run state and in c0274's claim memory of the worktree that works it",
		function()
			if fs.isDir(BASE) then
				fs.removeDir(BASE)
			end
			fs.writeDir(BASE)
			local st = { worktree = BASE } :: any
			local c = ctxWith({ stamp = "active-x-y-z", state = "active" })
			dispatcher.recordClaim(c, st, "R0010", BASE)
			t.expect(st.claim.id).toBe("R0010")
			t.expect(st.claim.stamp).toBe("active-x-y-z")
			t.expect(fs.isFile(`{BASE}/.cache/tracker-stamp-R0010`)).toBe(true)
			t.expect(
				if fs.isFile(`{BASE}/.cache/tracker-stamp-R0010`)
					then fs.readFile(`{BASE}/.cache/tracker-stamp-R0010`)
					else ""
			).toBe("active-x-y-z")
			-- a stamp that is not a claim (the item moved on) records nothing
			local st2 = { worktree = BASE } :: any
			dispatcher.recordClaim(ctxWith({ stamp = "prepared-a-b-c" }), st2, "R0011", BASE)
			t.expect(st2.claim).toBe(nil)
			t.expect(fs.isFile(`{BASE}/.cache/tracker-stamp-R0011`)).toBe(false)
		end
	)

	it(
		"AC1: the supervisor passes the pick's kind to the dispatcher, and reads the new exit codes",
		function()
			local args = supervise.dispatchArgs(
				{ id = "R0010", kind = "lost", why = "x" },
				{ cli = "claude", noRun = false, retry = false }
			)
			t.expect(table.concat(args, " ")).toBe("dispatch R0010 --worker --pick lost --cli claude")
			t.expect(supervise.afterDispatch("raft", 7, 0).kind).toBe("stop")
			t.expect(supervise.EXIT.pushRefused).toBe(dispatch.EXIT.pushRefused)
		end
	)

	local function world(
		nexts: { string },
		codes: { [string]: number }
	): (workloop.World, { string }, { number }, { supervise.State })
		local calls: { string } = {}
		local sleeps: { number } = {}
		local states: { supervise.State } = {}
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
				return codes[args[2] :: string] or 0
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
			state = function(s)
				table.insert(states, s)
			end,
			say = function() end,
			held = "",
			cli = nil,
			noRun = false,
			idleSeconds = nil,
		}
		return w, calls, sleeps, states
	end

	it("AC1: lost, then another item, then lost again is not two losses in a row", function()
		local w, _calls, sleeps = world(
			{ "R0010 raft a", "R0020 raft b", "R0010 raft c", "R0030 raft d" },
			{ R0010 = 6 }
		)
		workloop.run(w, { once = false, maxItems = 2 })
		t.expect(#sleeps).toBe(0)
	end)

	it("AC1: a raft the previous run held that turns out to be taken is no longer held", function()
		local w, _calls, _sleeps, states = world({}, { R0010 = 6 })
		w.held = "R0010"
		workloop.run(w, { once = true, maxItems = nil })
		local last = states[#states] :: supervise.State
		t.expect(last.held).toBe("")
		t.expect(last.state).toBe("stopped")
		-- and right after the item ended `taken`, before anything else is asked of next
		local after: supervise.State? = nil
		for _, s in states do
			if s.state == "working" and s.item == "" then
				after = s
			end
		end
		t.expect(after ~= nil and after.held or "x").toBe("")
	end)

	it(
		"AC2: a lost worker is told c0274's own words and to stop, never to continue on the taker's branch",
		function()
			local f: xhost.PushFacts = {
				publishing = true,
				branch = "prep-hello",
				hasUpstream = true,
				originHas = true,
				behind = 0,
				claim = "taken",
				owner = "c0010",
				originStamp = "preparing-x-y-z",
			}
			local d = xhost.pushDecision(f)
			t.expect(d.action).toBe("refuse")
			t.expect(d.why).toBe(
				"c0010's claim was taken over (now preparing-x-y-z): this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)"
			)
			f.claim, f.originStamp = "ended", nil
			t.expect(xhost.pushDecision(f).why).toBe(
				"c0010's claim ended: this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)"
			)
			t.expect((string.find(d.why, "continue", 1, true))).toBe(nil)
		end
	)

	it(
		"AC2: a numbered copy that holds no claim never pushes an item that is under a live claim, a layer's included",
		function()
			local f: xhost.PushFacts = {
				publishing = true,
				branch = "R0010/1/c0011",
				hasUpstream = true,
				originHas = true,
				behind = 0,
				claim = "unheld",
				owner = "R0010",
				originStamp = "active-x-y-z",
				copy = true,
			}
			local d = xhost.pushDecision(f)
			t.expect(d.action).toBe("refuse")
			t.expect(string.find(d.why, "holds no claim", 1, true) ~= nil).toBe(true)
			-- a person's own worktree that never claimed it is not a copy, and pushes as it always did
			f.copy = false
			t.expect(xhost.pushDecision(f).action).toBe("push")
			-- a layer under a claim this checkout holds is pushed; an item nobody claims is a person's
			f.claim = "held"
			t.expect(xhost.pushDecision(f).action).toBe("push")
			f.claim, f.originStamp = "unheld", "prepared-a-b-c"
			t.expect(xhost.pushDecision(f).action).toBe("push")
			f.claim, f.originStamp, f.hasUpstream = "taken", "active-q-r-s", false
			t.expect(xhost.pushDecision(f).action).toBe("refuse")
		end
	)

	it(
		"AC2, AC7: staleMember is c0277's rule: a worktree is stale when a claim it remembers is over and none is still its own",
		function()
			t.expect(heartbeat.staleMember({
				{ id = "c0010", remembered = "preparing-a-b-c", current = "preparing-x-y-z" },
			})).toBe(true)
			t.expect(
				heartbeat.staleMember({ { id = "c0010", remembered = "preparing-a-b-c", current = nil } })
			)
				.toBe(true)
			t.expect(heartbeat.staleMember({
				{ id = "c0010", remembered = "preparing-a-b-c", current = "preparing-a-b-c" },
			})).toBe(false)
			t.expect(
				heartbeat.staleMember({ { id = "c0010", remembered = "", current = "preparing-x-y-z" } })
			)
				.toBe(false)
			t.expect(heartbeat.staleMember({
				{ id = "c0010", remembered = "a", current = "b" },
				{ id = "c0011", remembered = "c", current = "c" },
			})).toBe(false)
		end
	)

	it(
		"AC3: the exit codes of a push are distinct from every dispatch code the supervisor reads as moved",
		function()
			t.expect(dispatch.EXIT.pushRefused).toBe(7)
			t.expect(dispatch.EXIT.pushRefused ~= dispatch.EXIT.taken).toBe(true)
			t.expect(supervise.afterDispatch("raft", 0, 0).kind).toBe("done")
		end
	)

	it("AC5: a trailer may carry the attempt token, and the newest one for a stamp is found", function()
		local a = xhost.trailer("R0010", "active-x-y-z", { host = "h", cli = "claude", model = "m" }, "tok1")
		t.expect(a).toBe("Worker: R0010 active-x-y-z host=h cli=claude model=m attempt=tok1")
		local parsed = xhost.parseTrailer(a)
		t.expect(parsed ~= nil and parsed.attempt or "").toBe("tok1")
		t.expect(xhost.parseTrailer("Worker: R0010 active-x-y-z host=h cli=claude model=m junk")).toBe(nil)
		t.expect(xhost.attemptOf({ a }, "R0010", "active-x-y-z")).toBe("tok1")
		t.expect(xhost.attemptOf({ a }, "R0010", "active-other-one-two")).toBe(nil)
		t.expect(
			xhost.attemptOf({ "Worker: R0010 active-x-y-z host=h cli=c model=-" }, "R0010", "active-x-y-z")
		)
			.toBe(nil)
	end)

	it("AC5: a raft and each member a rafting claim stamped are named, one trailer line each", function()
		local who = { host = "h1", cli = "grok", model = "" }
		local lines =
			{ xhost.trailer("c0010", "preparing-x-y-z", who), xhost.trailer("R0200", "preparing-x-y-z", who) }
		local holders = xhost.holders(lines, { R0200 = "preparing-x-y-z", c0010 = "preparing-x-y-z" })
		t.expect(holders.R0200.cli).toBe("grok")
		t.expect(holders.c0010.cli).toBe("grok")
	end)

	it(
		"AC1: a z-design prompt of a worker's run says the issue is already claimed, and a plain run's does not",
		function()
			local base: dispatch.PromptInput = {
				step = "z-design",
				id = "c0010",
				skillPath = "z-nile/skills/z-design/SKILL.md",
				worktree = "/w",
				stateDir = "/s",
			}
			base.claimed = "preparing-x-y-z"
			local worker = dispatch.prompt(base)
			t.expect(
				string.find(
					worker,
					"already claimed for this run (stamp `preparing-x-y-z`): skip the claim in step 1; do not claim it again.",
					1,
					true
				) ~= nil
			).toBe(true)
			base.claimed = nil
			t.expect((string.find(dispatch.prompt(base), "already claimed", 1, true))).toBe(nil)
		end
	)

	it("AC4: a code review's record line carries the reviewer's own CLI next to its model", function()
		t.expect(dispatcher.reviewRecordLine("c0010", "review-001", "grok-4.7", "grok", false))
			.toBe('record: ./zn commit -m "c0010: review-001" --phase code-review --model grok-4.7 --cli grok')
		t.expect(dispatcher.reviewRecordLine("c0010", "review-001", "grok-4.7", "grok", true)).toBe(
			'record: ./zn commit -m "c0010: review-001" --phase code-review --model grok-4.7 --cli grok --issue c0010'
		)
		t.expect(dispatcher.reviewRecordLine("c0010", "review-001", "grok-4.7", nil, false))
			.toBe('record: ./zn commit -m "c0010: review-001" --phase code-review --model grok-4.7')
	end)
end)
