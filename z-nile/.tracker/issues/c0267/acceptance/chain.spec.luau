--!strict
-- c0267 AC1-AC4: the chain's design step is a draft a person approves. The chain designs, merges the prep and rafts
-- without stopping for an approval; it stops, waiting for the person (exit 3, not a failure), where a raft would be
-- readied while one of its issues has no approval on origin/main that matches its contract. Pure: dispatch.next on
-- facts.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function facts(over: { [string]: any }): dispatch.Facts
	local f: { [string]: any } = {
		id = "R0050",
		folder = "z-nile/.tracker/rafts/R0050",
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

local function pr(): dispatch.Pr
	return {
		number = 7,
		state = "OPEN",
		draft = false,
		green = true,
		mergeable = true,
		head = "abc",
		judged = nil,
	}
end

local function act(f: dispatch.Facts): string
	local a = dispatch.next(f)
	if a.kind == "step" then
		return `step {a.step} {a.target or ""}`
	elseif a.kind == "merge" then
		return `merge {a.gate}`
	end
	return `stop {a.code}`
end

local NONE = { id = "c0010", state = "none", changed = {} }
local CHANGED = { id = "c0011", state = "changed", changed = { "check.sh", "design" } }
local BAD = { id = "c0012", state = "bad", changed = {} }

return t.spec("c0267: the chain waits for a person's approval before a raft starts", function(it)
	it(
		"AC1: a prepared backlog raft with an unapproved issue stops for the person, exit 3, not a failure",
		function()
			local a = dispatch.next(facts({ unapproved = { NONE } }))
			t.expect(a.kind).toBe("stop")
			t.expect(a.code).toBe(dispatch.EXIT.user)
			t.expect(a.code).toBe(3)
			t.expect(a.waiting).toBe("approval")
			t.expect(a.step).toBe(nil)
			local why = a.why or ""
			t.expect(has(why, "waiting for the person (not a failure)")).toBe(true)
			t.expect(has(why, "R0050")).toBe(true)
			t.expect(has(why, "retry")).toBe(false)
			t.expect(has(why, "failed")).toBe(false)
		end
	)

	it(
		"AC1: the stop names each issue, why, and the commands that get it through, in the order given",
		function()
			local why = dispatch.next(facts({ unapproved = { NONE, CHANGED, BAD } })).why or ""
			t.expect(has(why, "c0010: no approval.")).toBe(true)
			t.expect(has(why, "c0011: its contract changed since approval (check.sh, design).")).toBe(true)
			t.expect(has(why, "c0012: its approval.md does not parse.")).toBe(true)
			local a10 = string.find(why, "c0010: ", 1, true) or 0
			local a11 = string.find(why, "c0011: ", 1, true) or 0
			local a12 = string.find(why, "c0012: ", 1, true) or 0
			t.expect(a10 < a11 and a11 < a12).toBe(true)
			for _, id in { "c0010", "c0011", "c0012" } do
				t.expect(
					has(
						why,
						`cd "$(./zn worktree approve-{id}-$(date +%s) --from origin/main)" && ./zn approve {id} && ./zn approve {id} --publish`
					)
				).toBe(true)
			end
			t.expect(has(why, "In a terminal of your own, from the main checkout")).toBe(true)
			t.expect(has(why, "Then run ./zn dispatch R0050 again.")).toBe(true)
			-- the same text dispatch.waitingWhy gives, so the board and status can print it
			t.expect(why).toBe(dispatch.waitingWhy("R0050", { NONE, CHANGED, BAD }))
		end
	)

	it("AC2: every issue approved (or the approvals not read, as before) readies the raft", function()
		t.expect(act(facts({ unapproved = {} }))).toBe("step z-ready R0050")
		t.expect(act(facts({}))).toBe("step z-ready R0050")
	end)

	it(
		"AC2: approvals that could not be read stop as a failure that names why, never as a z-ready",
		function()
			local a = dispatch.next(facts({ unreadable = "git ls-tree failed" }))
			t.expect(a.kind).toBe("stop")
			t.expect(a.code).toBe(dispatch.EXIT.failure)
			t.expect(has(a.why or "", "git ls-tree failed")).toBe(true)
			t.expect(has(a.why or "", "R0050")).toBe(true)
			t.expect(a.waiting).toBe(nil)
			-- unreadable wins over a list that says nothing is missing
			t.expect(act(facts({ unreadable = "x", unapproved = {} }))).toBe("stop 1")
		end
	)

	it(
		"AC3: the design step drafts, and the chain merges the prep and rafts without waiting for an approval",
		function()
			local waits = { NONE }
			-- an issue: design, the prep gate, raft-plan, z-raft, the rafting gate, then it follows its raft
			local issue = { kind = "issue", id = "c0010", unapproved = waits }
			local function with(over: { [string]: any }): dispatch.Facts
				local all = table.clone(issue) :: { [string]: any }
				for k, v in over do
					all[k] = v
				end
				return facts(all)
			end
			t.expect(act(with({ status = "new", design = "draft" }))).toBe("step z-design c0010")
			t.expect(act(with({ status = "preparing", ownClaim = true, pr = pr() }))).toBe("merge prep")
			t.expect(act(with({ status = "prepared", design = "ready" }))).toBe("step raft-plan c0010")
			t.expect(act(with({ status = "prepared", design = "ready", localRaft = "R0050" })))
				.toBe("step z-raft R0050")
			t.expect(act(with({ status = "prepared", design = "ready", pr = pr() }))).toBe("merge raft")
			t.expect(act(with({ status = "prepared", design = "ready", raft = "R0050" })))
				.toBe("step follow R0050")
		end
	)

	it("AC3: a raft already active is not stopped by the list (ready already held its approvals)", function()
		t.expect(act(facts({ where = "active", status = "active", unapproved = { NONE } })))
			.toBe("step z-run R0050")
		t.expect(act(facts({ where = "backlog", status = "preparing", unapproved = { NONE } })))
			.toBe("stop 1")
	end)

	it("AC4: the stops that come first still come first", function()
		local q = dispatch.next(facts({ questions = true, unapproved = { NONE } }))
		t.expect(q.code).toBe(3)
		t.expect(has(q.why or "", "questions.md")).toBe(true)
		t.expect(q.waiting).toBe(nil)
		local open = dispatch.next(facts({ openHuman = { "F2" }, unapproved = { NONE } }))
		t.expect(has(open.why or "", "## Open to the human")).toBe(true)
		t.expect(act(facts({ last = { step = "z-raft", outcome = "cap" }, unapproved = { NONE } })))
			.toBe("stop 1")
		t.expect(act(facts({ last = { step = "z-ready", outcome = "tripwire" }, unapproved = { NONE } })))
			.toBe("stop 5")
		local done = dispatch.next(facts({ where = "done", status = "done", unapproved = { NONE } }))
		t.expect(done.code).toBe(0)
	end)
end)
