--!strict
-- f0464 AC4: under ./zn dispatch a prepared ticket in no raft goes to `z-ready` on the ticket (`./zn ready <id>`, no
-- --on), never to raft-plan or z-raft; a ready that ends ok but leaves it with no raft stops the chain; once readied
-- the chain follows its raft. A rafting the dispatcher began before f0464 (its rafting worktree or PR) goes on as it
-- did. Pure: dispatch.next over facts.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local function facts(over: { [string]: any }): dispatch.Facts
	local f: { [string]: any } = {
		id = "c0010",
		folder = "pickman/.tracker/issues/c0010",
		root = "pickman/.tracker",
		kind = "issue",
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
	} :: any
end

local function act(f: dispatch.Facts): string
	local a = dispatch.next(f)
	if a.kind == "step" then
		return `step {a.step} {a.target}`
	elseif a.kind == "merge" then
		return `merge {a.gate} {a.pr}`
	end
	return `stop {a.code}`
end

return t.spec("f0464 the dispatcher readies a raftless ticket alone", function(it)
	it("AC4: a prepared ticket in no raft is readied by z-ready on the ticket, with no --on", function()
		t.expect(act(facts({}))).toBe("step z-ready c0010")
		t.expect(dispatch.scriptArgv("z-ready", "c0010")).toEqual({ "./zn", "ready", "c0010" })
		for _, step in { "raft-plan", "z-raft" } do
			t.expect(act(facts({})) ~= `step {step} c0010`).toBe(true)
		end
		-- after the prep gate merged (the last step was z-design), the next step is still z-ready
		t.expect(act(facts({ last = { step = "z-design", outcome = "ok" } }))).toBe("step z-ready c0010")
	end)

	it(
		"AC4: a z-ready that ended ok but left the ticket with no raft stops; a readied one is followed",
		function()
			local stopped = dispatch.next(facts({ last = { step = "z-ready", outcome = "ok" } }))
			t.expect(stopped.kind).toBe("stop")
			t.expect(stopped.code).toBe(dispatch.EXIT.failure)
			t.expect(string.find(stopped.why or "", "has no raft", 1, true) ~= nil).toBe(true)
			-- a refused ready (a dependency not landed, no approval) is a failed step: the chain stops for a retry
			t.expect(act(facts({ last = { step = "z-ready", outcome = "failed" } }))).toBe("stop 1")
			t.expect(act(facts({
				where = "active",
				status = "active",
				raft = "R0050",
				last = { step = "z-ready", outcome = "ok" },
			}))).toBe("step follow R0050")
			-- the raft it made is readied already: the raft's chain runs z-run
			t.expect(act(facts({ kind = "raft", id = "R0050", where = "active", status = "active" })))
				.toBe("step z-run R0050")
		end
	)

	it("AC4: a rafting begun before f0464 goes on as it did", function()
		t.expect(act(facts({ localRaft = "R0050", last = { step = "raft-plan", outcome = "ok" } })))
			.toBe("step z-raft R0050")
		t.expect(act(facts({ localRaft = "R0050", last = { step = "z-raft", outcome = "ok" }, pr = pr() })))
			.toBe("merge raft 7")
		t.expect(act(facts({ raft = "R0050" }))).toBe("step follow R0050")
		-- a prepared raft in the backlog is readied as before
		t.expect(act(facts({ kind = "raft", id = "R0050" }))).toBe("step z-ready R0050")
	end)
end)
